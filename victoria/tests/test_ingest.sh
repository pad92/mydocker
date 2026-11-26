#!/usr/bin/env bash
# End-to-end ingestion test: VictoriaLogs and Vector (the pipeline as Compose
# renders it with .env.example) on a throwaway internal network, one real
# OTLP/HTTP protobuf request to Vector with a stream-name header, then a LogsQL
# query to check what VictoriaLogs stored. Covers what the Vector unit tests
# cannot: the opentelemetry source, the HTTP sink and its query string
# (_stream_fields, _msg_field, _time_field), and the Content-Type.
# Needs Docker, Docker Compose 2.23+, jq and python3; no published port, no Internet.
# Usage: ./tests/test_ingest.sh
set -euo pipefail

stack_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_file="$stack_dir/.env.example"
logs_image="victoriametrics/victoria-logs:$(sed -n 's/^VICTORIA_LOGS_VERSION=//p' "$env_file")"
vector_image="timberio/vector:$(sed -n 's/^VECTOR_VERSION=//p' "$env_file")-distroless-libc"
# HTTP client: the image of victoria-init, already needed by the stack.
client_image="${CLIENT_IMAGE:-busybox:1.37}"

suffix="$$-$RANDOM"
network="victoria-ingest-test-$suffix"
logs_name="victorialogs-test-$suffix"
vector_name="vector-test-$suffix"
work_dir="$(mktemp -d)"

cleanup() {
  docker rm -f "$vector_name" "$logs_name" >/dev/null 2>&1 || true
  docker network rm "$network" >/dev/null 2>&1 || true
  rm -rf "$work_dir"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  echo "--- vector logs" >&2
  docker logs "$vector_name" 2>&1 | tail -n 30 >&2 || true
  exit 1
}

# Same rendering as test_vector.sh: the file the container really receives.
PUID="${PUID:-1000}" PGID="${PGID:-1000}" docker compose \
  --project-directory "$stack_dir" --env-file "$env_file" \
  config --format json | jq -er '.configs.vector_config.content | gsub("\\$\\$"; "$")' > "$work_dir/vector.yaml"
chmod -R a+rX "$work_dir"

docker network create --internal "$network" >/dev/null
# Alias victorialogs: the host name of the sink URI.
docker run -d --name "$logs_name" --network "$network" --network-alias victorialogs \
  --tmpfs /data "$logs_image" -storageDataPath=/data -httpListenAddr=:9428 >/dev/null
docker run -d --name "$vector_name" --network "$network" --network-alias vector \
  --tmpfs /var/lib/vector -v "$work_dir/vector.yaml:/etc/vector/vector.yaml:ro" \
  "$vector_image" >/dev/null

client() {
  docker run --rm --network "$network" "$client_image" "$@"
}

# Vector listens once its sources are up; VictoriaLogs may still be starting
# (the sink retries).
ready=""
for _ in $(seq 1 30); do
  if client wget -q -O /dev/null http://victorialogs:9428/health 2>/dev/null \
    && client nc -z vector 4318 2>/dev/null; then
    ready=1
    break
  fi
  sleep 1
done
[[ -n "$ready" ]] || fail "victorialogs or vector did not start"

marker="ingest-test-$suffix"
now_s="$(date +%s)"
# OTLP protobuf (ExportLogsServiceRequest), encoded by hand: the OTLP/HTTP
# source of Vector refuses JSON (500, invalid content-type), and protobuf is
# what the collectors send (otlp_http exporter default).
python3 -I - "$work_dir/request.http" "GET /cb?code=s3cr3t&x=1 $marker" "$now_s" <<'PY_EOF'
import struct, sys

out, msg, now_s = sys.argv[1], sys.argv[2], int(sys.argv[3])

def varint(n):
    b = b""
    while True:
        byte, n = n & 0x7F, n >> 7
        b += bytes([byte | (0x80 if n else 0)])
        if not n:
            return b

def ld(field, data):  # length-delimited field
    if isinstance(data, str):
        data = data.encode()
    return varint(field << 3 | 2) + varint(len(data)) + data

def kv(key, value):  # KeyValue{key, AnyValue{string_value}}
    return ld(1, key) + ld(2, ld(1, value))

record = (
    b"\x09" + struct.pack("<Q", now_s * 10**9)  # time_unix_nano (fixed64)
    + b"\x10" + varint(13)                      # severity_number WARN
    + ld(3, "WARN")                             # severity_text
    + ld(5, ld(1, msg))                         # body
    + ld(6, kv("app.Level", "warn"))            # attributes
)
resource = ld(1, kv("host.name", "srv.example.com")) + ld(1, kv("container.name", "web"))
resource_logs = ld(1, resource) + ld(2, ld(2, record))  # scope_logs.log_records
body = ld(1, resource_logs)
# A raw HTTP request for nc: BusyBox wget cuts a posted body at its first NUL
# byte, and the fixed64 time has some.
head = (
    "POST /v1/logs HTTP/1.1\r\nHost: vector:4318\r\n"
    "Content-Type: application/x-protobuf\r\nstream-name: docker\r\n"
    f"Content-Length: {len(body)}\r\nConnection: close\r\n\r\n"
)
with open(out, "wb") as f:
    f.write(head.encode() + body)
PY_EOF
chmod a+r "$work_dir/request.http"

# The opentelemetry source answers once the sink has written the batch
# (acknowledgements, batch timeout 1 s): a 200 means VictoriaLogs accepted it.
# The sleep keeps nc reading until Vector answers and closes. read returns on
# the status line, without waiting for the sleep.
started="$EPOCHREALTIME"
IFS= read -r response < <(docker run --rm --network "$network" -v "$work_dir/request.http:/request.http:ro" \
  "$client_image" sh -c '(cat /request.http; sleep 15) | nc vector 4318')
elapsed_ms=$(( (${EPOCHREALTIME/./} - ${started/./}) / 1000 ))
response="${response%$'\r'}"
[[ "$response" == "HTTP/1.1 200 OK" ]] || fail "OTLP request refused by vector: $response"
# A lone record never fills a batch, so the answer comes after the batch
# timeout. 3.5 s leaves room for the client container to start; a 5 s timeout
# fails.
(( elapsed_ms < 3500 )) || fail "OTLP answer took ${elapsed_ms} ms; is the victorialogs batch timeout above 1 s?"
echo "OTLP answer in ${elapsed_ms} ms"

query="$(jq -rn --arg q "\"$marker\"" '$q | @uri')"
result=""
for _ in $(seq 1 15); do
  result="$(client wget -q -O - "http://victorialogs:9428/select/logsql/query?query=$query" || true)"
  [[ -n "$result" ]] && break
  sleep 1
done
[[ -n "$result" ]] || fail "record not found in VictoriaLogs"
[[ "$(wc -l <<<"$result")" -eq 1 ]] || fail "expected one record, got: $result"

check() {
  local field="$1" expected="$2" actual
  actual="$(jq -r --arg f "$field" '.[$f] // empty' <<<"$result")"
  [[ "$actual" == "$expected" ]] || fail "$field: expected '$expected', got '$actual' in $result"
}

check log_stream docker
check host_name srv.example.com
check container_name web
check severity WARN
check app_level warn
check level warn
# _msg comes from body (_msg_field), with the URL secret masked by
# redact_url_secrets on the way.
check _msg "GET /cb?code=[REDACTED]&x=1 $marker"
check _stream '{container_name="web",host_name="srv.example.com",log_stream="docker"}'
# _time from the record time (_time_field), not the arrival time.
expected_time="$(date -u -d "@$now_s" +%Y-%m-%dT%H:%M:%SZ)"
check _time "$expected_time"

echo "OK: one OTLP record stored with its stream, fields and time"
