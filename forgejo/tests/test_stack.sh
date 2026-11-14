#!/usr/bin/env bash
# Checks the compose file rendered with .env.example, then runs the migration
# end to end on throwaway containers (own network, no host port):
# - Forgejo starts from the compose file with PostgreSQL, without web installer;
# - a Gitea (gitea/gitea:latest, same image as production) is filled with a
#   private user repository, an organisation repository with an issue, a label
#   and a release, an archived repository, a repository whose owner is missing
#   in Forgejo, a repository whose owner cannot be created in Forgejo (email
#   already taken), and a generic package;
# - migrate_repos.py, with the token scopes given in README.md: the dry run
#   changes nothing, --apply creates the missing owners, copies everything it
#   can and reports the failed owner and the package, a second run copies only
#   what was left;
# - the runner connects with runner-config.example.yml and runs a job through
#   the host's docker.sock; the job reaches the Docker daemon and the cache.
# Needs Docker, Docker Compose 2.23+, jq, curl and python3.
# Usage: ./tests/test_stack.sh
set -euo pipefail

stack_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$(mktemp -d)"
project="forgejo-test-$$"
gitea="$project-gitea"

compose() {
  docker compose --project-name "$project" --project-directory "$stack_dir" \
    --env-file "$work_dir/test.env" -f "$stack_dir/docker-compose.yml" \
    -f "$work_dir/override.yml" "$@"
}
cleanup() {
  docker rm -f "$gitea" >/dev/null 2>&1 || true
  compose down --volumes >/dev/null 2>&1 || true
  # Files written by the containers belong to other users: remove them from a
  # container rather than asking for sudo.
  docker run --rm -v "$work_dir:/w" alpine:3 sh -c 'rm -rf /w/*' >/dev/null 2>&1 || true
  rm -rf "$work_dir"
}
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

docker_gid="$(getent group docker | cut -d: -f3)"
[ -n "$docker_gid" ] || fail "no docker group on this host"
mkdir -p "$work_dir"/{data,postgres,runner}
sed -e "s/^USER_UID=.*/USER_UID=$(id -u)/" -e "s/^USER_GID=.*/USER_GID=$(id -g)/" \
  -e "s/^FORGEJO_RUNNER_UID=.*/FORGEJO_RUNNER_UID=$(id -u)/" \
  -e "s/^FORGEJO_RUNNER_GID=.*/FORGEJO_RUNNER_GID=$(id -g)/" \
  -e "s/^DOCKER_GID=.*/DOCKER_GID=$docker_gid/" \
  -e "s|^FORGEJO_DATA_DIR=.*|FORGEJO_DATA_DIR=$work_dir/data|" \
  -e "s|^FORGEJO_DB_DATA_DIR=.*|FORGEJO_DB_DATA_DIR=$work_dir/postgres|" \
  -e "s|^FORGEJO_RUNNER_DATA_DIR=.*|FORGEJO_RUNNER_DATA_DIR=$work_dir/runner|" \
  -e "s/^FORGEJO_DB_PASSWORD=.*/FORGEJO_DB_PASSWORD=$(openssl rand -hex 12)/" \
  "$stack_dir/.env.example" > "$work_dir/test.env"

# Static checks on the rendered compose file.
render() { env "$@" docker compose --project-directory "$stack_dir" \
  --env-file "$work_dir/test.env" config --format json; }
config="$(render)"
env_of() { jq -r ".services.forgejo.environment[\"$1\"]" <<<"$config"; }
[ "$(env_of FORGEJO__server__ROOT_URL)" = https://forgejo.example.com/ ] \
  || fail "ROOT_URL is not built from FORGEJO_DOMAIN"
[ "$(env_of FORGEJO__security__INSTALL_LOCK)" = true ] || fail "the web installer is open"
[ "$(env_of FORGEJO__migrations__ALLOW_LOCALNETWORKS)" = false ] \
  || fail "migrations from local networks are allowed by default"
[ "$(env_of FORGEJO__server__SSH_PORT)" = "$(jq -r '.services.forgejo.ports[0].published' <<<"$config")" ] \
  || fail "the advertised SSH port is not the published one"
[ "$(env_of FORGEJO__actions__DEFAULT_ACTIONS_URL)" = https://github.com ] \
  || fail "actions are not fetched from github.com as with Gitea"
[ "$(jq -r '.services.forgejo.labels["traefik.http.routers.forgejo_http.middlewares"]' <<<"$config")" = redirect-https ] \
  || fail "HTTP router does not redirect to HTTPS"
[ "$(docker compose --project-name other --project-directory "$stack_dir" --env-file "$work_dir/test.env" \
  config --format json | jq -r .networks.forgejo.name)" = forgejo_forgejo ] \
  || fail "the stack network name depends on the project name"
grep -q '^  network: forgejo_forgejo$' "$stack_dir/runner-config.example.yml" \
  || fail "the runner does not put jobs on the stack network"
jq -e ".services.runner.group_add | index(\"$docker_gid\")" <<<"$config" >/dev/null \
  || fail "the runner is not in the docker group"
for var in FORGEJO_DB_PASSWORD DOCKER_GID FORGEJO_DOMAIN; do
  if render "$var=" >/dev/null 2>&1; then fail "compose accepts an empty $var"; fi
done
echo "OK: static checks"

# Runtime. The traefik_gateway network becomes a private one, migrations from
# the test network are allowed, the SSH port is not published.
cat > "$work_dir/override.yml" <<EOF
services:
  forgejo:
    container_name: $project
    ports: !reset []
    environment:
      FORGEJO__migrations__ALLOW_LOCALNETWORKS: "true"
  db:
    container_name: $project-db
  runner:
    container_name: $project-runner
networks:
  forgejo:
    name: ${project}_forgejo
  traefik_gateway:
    external: false
    name: $project-gateway
EOF
compose up -d --quiet-pull forgejo db >/dev/null 2>&1 || fail "docker compose up failed"
network="${project}_forgejo"
# Gitea is reached by Forgejo as http://gitea-src:3000 (its ROOT_URL, used in
# clone URLs) and by this script through its IP address.
docker run -d --name "$gitea" --network "$network" --network-alias gitea-src \
  -e GITEA__security__INSTALL_LOCK=true -e GITEA__database__DB_TYPE=sqlite3 \
  -e GITEA__server__ROOT_URL=http://gitea-src:3000/ \
  -e GITEA__packages__ENABLED=true gitea/gitea:latest >/dev/null
ip_of() { docker inspect -f "{{(index .NetworkSettings.Networks \"$network\").IPAddress}}" "$1"; }
wait_healthy() {
  for _ in $(seq 1 90); do
    curl -fs -o /dev/null "$1/api/healthz" && return 0
    sleep 2
  done
  fail "$1 did not answer"
}
gitea_url="http://$(ip_of "$gitea"):3000"
forgejo_url="http://$(ip_of "$project"):3000"
wait_healthy "$gitea_url"
wait_healthy "$forgejo_url"
docker exec -u git "$project" grep -q '^INSTALL_LOCK *= *true' /data/gitea/conf/app.ini \
  || fail "app.ini is not locked"
echo "OK: Forgejo starts on PostgreSQL without web installer"

# Users and tokens, with the scopes documented in README.md.
add_user() { # cli container user [--admin]
  docker exec -u git "$2" "$1" admin user create --username "$3" --email "$3@example.test" \
    --random-password "${@:4}" >/dev/null
}
new_token() { # cli container user scopes name
  docker exec -u git "$2" "$1" admin user generate-access-token --username "$3" \
    --token-name "$5" --scopes "$4" --raw
}
add_user gitea "$gitea" gadmin --admin
add_user gitea "$gitea" alice
add_user gitea "$gitea" bob
add_user gitea "$gitea" carol
add_user forgejo "$project" fadmin --admin
add_user forgejo "$project" alice
# Takes carol's email, so that carol cannot be created in Forgejo.
docker exec -u git "$project" forgejo admin user create --username squatter \
  --email carol@example.test --random-password >/dev/null
GITEA_TOKEN="$(new_token gitea "$gitea" gadmin read:repository,read:issue,read:user,read:organization,read:package migration)"
FORGEJO_TOKEN="$(new_token forgejo "$project" fadmin write:repository,write:organization,read:user,write:admin migration)"
gitea_admin_token="$(new_token gitea "$gitea" gadmin all test)"
forgejo_admin_token="$(new_token forgejo "$project" fadmin all test)"
export GITEA_TOKEN FORGEJO_TOKEN

api() { # base token method path [json]
  curl -sS --fail-with-body -X "$3" -H "Authorization: token $2" \
    -H 'Content-Type: application/json' ${5:+--data "$5"} "$1/api/v1$4" \
    || fail "$3 $1/api/v1$4 failed"
}
gitea_api() { api "$gitea_url" "$gitea_admin_token" "$@"; }
forgejo_api() { api "$forgejo_url" "$forgejo_admin_token" "$@"; }

gitea_api POST /admin/users/alice/repos '{"name":"secret","private":true,"auto_init":true}' >/dev/null
# alice/old is archived with a pull request: Gitea hides the pull requests of
# archived repositories from the API.
gitea_api POST /admin/users/alice/repos '{"name":"old","auto_init":true}' >/dev/null
gitea_api POST /repos/alice/old/contents/feature.txt \
  "{\"content\":\"$(base64 -w0 <<<feature)\",\"message\":\"feature\",\"new_branch\":\"feature\"}" >/dev/null
base_branch="$(gitea_api GET /repos/alice/old | jq -r .default_branch)"
gitea_api POST /repos/alice/old/pulls \
  "{\"head\":\"feature\",\"base\":\"$base_branch\",\"title\":\"Add feature\"}" >/dev/null
gitea_api PATCH /repos/alice/old '{"archived":true}' >/dev/null
gitea_api POST /admin/users/bob/repos '{"name":"tools","auto_init":true}' >/dev/null
gitea_api POST /admin/users/carol/repos '{"name":"notes","auto_init":true}' >/dev/null
gitea_api POST /admin/users/gadmin/orgs '{"username":"team","full_name":"The Team"}' >/dev/null
gitea_api POST /orgs/team/repos '{"name":"app","auto_init":true,"description":"main app"}' >/dev/null
gitea_api POST /repos/team/app/labels '{"name":"bug","color":"#ee0701"}' >/dev/null
gitea_api POST /repos/team/app/issues '{"title":"Crash on start","body":"steps"}' >/dev/null
gitea_api POST /repos/team/app/releases '{"tag_name":"v1.0.0","name":"First"}' >/dev/null
curl -fsS -X PUT -H "Authorization: token $gitea_admin_token" \
  -H 'Content-Type: application/octet-stream' --data-binary 'payload' \
  "$gitea_url/api/packages/team/generic/blob/1.0.0/blob.txt" >/dev/null

migrate() { python3 "$stack_dir/migrate_repos.py" --source "$gitea_url" --target "$forgejo_url" "$@"; }
forgejo_repos() { forgejo_api GET '/repos/search?limit=50' | jq -r '[.data[].full_name] | sort | join(" ")'; }
pull_titles() { forgejo_api GET "/repos/$1/pulls?state=all" | jq -r '[.[].title] | join(",")'; }

# bob and the team organisation are missing in Forgejo: the dry run plans them.
out="$(migrate 2>&1)" || fail "the dry run failed: $out"
[ -z "$(forgejo_repos)" ] || fail "the dry run created repositories"
grep -q '^create organisation team$' <<<"$out" || fail "the dry run does not plan the organisation: $out"
grep -q '^create user bob$' <<<"$out" || fail "the dry run does not plan the user: $out"
[ "$(curl -sS -o /dev/null -w '%{http_code}' -H "Authorization: token $forgejo_admin_token" \
  "$forgejo_url/api/v1/users/bob")" = 404 ] || fail "the dry run created bob"
echo "OK: dry run changes nothing"

status=0
out="$(migrate --apply 2>&1)" || status=$?
[ "$status" = 1 ] || fail "an owner that cannot be created does not make the run fail (exit $status): $out"
grep -q '^FAILED owner carol: ' <<<"$out" || fail "the failed owner is not reported: $out"
grep -q '^skip carol/notes: its owner could not be created' <<<"$out" \
  || fail "the repository of the failed owner is not reported: $out"
grep -q 'generic team/blob:1.0.0' <<<"$out" || fail "the package is not listed: $out"
grep -q '^copy alice/old, archived, without pull requests$' <<<"$out" \
  || fail "the archived repository is not reported as copied without pull requests: $out"
[ "$(forgejo_repos)" = "alice/old alice/secret bob/tools team/app" ] \
  || fail "unexpected repositories in Forgejo: $(forgejo_repos)"
bob="$(forgejo_api GET /users/bob)"
[ "$(jq -r .email <<<"$bob")" = bob@example.test ] || fail "bob was not created with his Gitea email: $bob"
[ "$(jq -r .is_admin <<<"$bob")" = false ] || fail "bob was created as admin"
[ "$(forgejo_api GET /repos/alice/secret | jq -r .private)" = true ] || fail "alice/secret is not private"
[ "$(forgejo_api GET /repos/alice/old | jq -r .archived)" = true ] || fail "alice/old is not archived"
app="$(forgejo_api GET /repos/team/app)"
[ "$(jq -r '.description' <<<"$app")" = "main app" ] || fail "description lost: $app"
[ "$(jq -r '.mirror' <<<"$app")" = false ] || fail "team/app became a mirror"
[ "$(forgejo_api GET '/repos/team/app/issues?state=all&type=issues' | jq -r '.[0].title')" = "Crash on start" ] \
  || fail "the issue was not copied"
forgejo_api GET /repos/team/app/labels | jq -e '.[] | select(.name == "bug")' >/dev/null \
  || fail "the label was not copied"
[ "$(forgejo_api GET /repos/team/app/releases | jq -r '.[0].tag_name')" = v1.0.0 ] \
  || fail "the release was not copied"
[ "$(forgejo_api GET /orgs/team | jq -r .full_name)" = "The Team" ] || fail "the organisation was not created"
forgejo_api GET /repos/alice/secret/contents/README.md >/dev/null || fail "the code of alice/secret is missing"
echo "OK: owners created; repositories, issue, label, release, private and archived state copied"

forgejo_api DELETE /admin/users/squatter >/dev/null
out="$(migrate --apply 2>&1)" || fail "second run failed: $out"
grep -q '^create user carol$' <<<"$out" || fail "carol is not created on the second run: $out"
grep -q '^copy carol/notes$' <<<"$out" || fail "carol/notes is not copied on the second run: $out"
[ "$(grep -c 'already in Forgejo' <<<"$out")" = 4 ] || fail "copied repositories are not skipped: $out"
echo "OK: a second run copies only what was left"

# --unarchive-source keeps the pull requests of an archived repository. The
# Gitea token then needs write:repository.
forgejo_api DELETE /repos/alice/old >/dev/null
out="$(GITEA_TOKEN="$(new_token gitea "$gitea" gadmin \
  write:repository,read:issue,read:user,read:organization,read:package unarchive)" \
  migrate --only alice/old --unarchive-source --apply 2>&1)" || fail "--unarchive-source failed: $out"
[ "$(pull_titles alice/old)" = "Add feature" ] || fail "the pull request was not copied: $out"
[ "$(forgejo_api GET /repos/alice/old | jq -r .archived)" = true ] || fail "alice/old is not archived in Forgejo"
[ "$(gitea_api GET /repos/alice/old | jq -r .archived)" = true ] || fail "alice/old is not archived again in Gitea"
echo "OK: --unarchive-source copies the pull requests and archives the repository again"

# Runner: shared secret registered in Forgejo, config.yml from the example.
secret="$(openssl rand -hex 20)"
uuid="$(docker exec -u git "$project" forgejo forgejo-cli actions register --name test-runner --secret "$secret")"
# The test project has its own network name.
sed -e "s/00000000-0000-0000-0000-000000000000/$uuid/" -e "s/REPLACE_WITH_THE_RUNNER_SECRET/$secret/" \
  -e "s/network: forgejo_forgejo/network: ${project}_forgejo/" \
  "$stack_dir/runner-config.example.yml" > "$work_dir/runner/config.yml"
chmod 600 "$work_dir/runner/config.yml"
compose up -d --quiet-pull runner >/dev/null 2>&1 || fail "the runner did not start"
workflow='on: [push]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: test -s /etc/ssl/certs/ca-certificates.crt
      - run: docker info >/dev/null
      - run: test -n "$ACTIONS_CACHE_URL"
      - run: test "$(curl -s -o /dev/null -w "%{http_code}" "$ACTIONS_CACHE_URL")" != 000'
forgejo_api POST /admin/users/alice/repos '{"name":"ci","auto_init":true}' >/dev/null
forgejo_api POST /repos/alice/ci/contents/.forgejo/workflows/test.yml \
  "$(jq -n --arg c "$(base64 -w0 <<<"$workflow")" '{content: $c, message: "ci"}')" >/dev/null
for _ in $(seq 1 90); do
  task_status="$(forgejo_api GET /repos/alice/ci/actions/tasks | jq -r '.workflow_runs[0].status // empty')"
  case "$task_status" in success|failure|cancelled) break ;; esac
  sleep 4
done
[ "$task_status" = success ] || fail "the job did not succeed (status: ${task_status:-none})"
echo "OK: the runner runs a job that reaches the Docker daemon and the cache"
