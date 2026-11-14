# Forgejo

This stack runs Forgejo 15 (LTS), PostgreSQL 17 and a Forgejo Actions runner
behind Traefik. It replaces the `gitea` stack. As with Gitea, the external
network `traefik_gateway` and the certificate resolver `stepca` must already
exist. HTTP redirects to HTTPS, and SSH is published on `FORGEJO_SSH_PORT`.

## Why the Gitea data is not reused

Forgejo can only start on the data of Gitea 1.22 or older
([Forgejo documentation](https://forgejo.org/docs/v15.0/admin/upgrade/from-gitea/)).
Production runs Gitea 28.3.0, whose database schema Forgejo does not know.
Copying `/rpool/docker/gitea` into Forgejo's directories would at best stop
Forgejo at start-up and at worst damage the copied database.

Instead, Forgejo starts on an empty database and each repository is imported
with Forgejo's migration tool, driven by `migrate_repos.py` (see
[Migration from Gitea](#migration-from-gitea)). Gitea stays untouched until the
switch, so going back is a matter of restarting it.

## Configuration

Copy `.env.example` to `.env`, fill in the blanks and run `chmod 600 .env`.
Production directories:

| Variable | Host directory | Container destination |
| --- | --- | --- |
| `FORGEJO_DATA_DIR` | `/rpool/docker/forgejo/data` | Forgejo `/data` |
| `FORGEJO_DB_DATA_DIR` | `/rpool/docker/forgejo/postgres` | PostgreSQL `/var/lib/postgresql/data` |
| `FORGEJO_RUNNER_DATA_DIR` | `/rpool/docker/forgejo/runner` | Runner `/data` |

`ROOT_URL` is `https://<FORGEJO_DOMAIN>/`, and SSH clone URLs use
`FORGEJO_DOMAIN` and `FORGEJO_SSH_PORT`. The web installer is disabled
(`INSTALL_LOCK`): Forgejo creates its schema on first start, and its secrets
(`SECRET_KEY`, `INTERNAL_TOKEN`, `JWT_SECRET`) in
`<FORGEJO_DATA_DIR>/gitea/conf/app.ini`. Back that file up with the data.

Settings that differ from Forgejo's defaults:

- `DEFAULT_ACTIONS_URL=https://github.com`: as with Gitea, `uses:
  actions/checkout@v4` is fetched from github.com. Forgejo's default is
  data.forgejo.org.
- `ALLOW_LOCALNETWORKS=false`: set it to true only during the import,
  because Forgejo refuses to migrate from a private address such as
  git.home.lan.
- Forgejo and the runner mount the host CA bundle, so they trust the step-ca
  certificates of `*.home.lan`.

Any setting made directly in Gitea's `app.ini` (mail, webhook allow list,
registration, and so on) must be carried over by hand, as
`FORGEJO__<section>__<KEY>` variables in `docker-compose.yml`. Compare with
`/rpool/docker/gitea/data/gitea/conf/app.ini` before going live.

## First start

Create the runner directory with the owner given in `.env`. The other two
directories are created by Docker:

```sh
install -d -m 700 -o 1000 -g 1000 /rpool/docker/forgejo/runner
```

To keep Gitea's SSH host keys, so that clients do not get a "host key changed"
warning after the switch, copy them before the first start. Forgejo generates
keys only when these files are missing:

```sh
install -d -m 700 /rpool/docker/forgejo/data/ssh
cp -p /rpool/docker/gitea/data/ssh/ssh_host_* /rpool/docker/forgejo/data/ssh/
```

Start the stack without the runner, then create the admin account. The CLI
prints a generated password, to be changed at first login:

```sh
docker compose up -d forgejo db
docker exec -u git forgejo forgejo admin user create --admin \
  --username <name> --email <email> --random-password
```

## Actions runner

The runner connects to `http://forgejo:3000` inside the compose network. It
registers with a secret shared with Forgejo:

```sh
secret="$(openssl rand -hex 20)"
docker exec -u git forgejo forgejo forgejo-cli actions register \
  --name <runner name> --secret "$secret"
```

The command prints the runner UUID. Copy `runner-config.example.yml` to
`/rpool/docker/forgejo/runner/config.yml` (owner 1000, mode 600), set `uuid` to
the printed UUID and `token` to the secret, then `docker compose up -d runner`.
The command can be run again with the same secret: it does not create a
second runner.

The example config follows the Gitea runner's `config.yaml`
(`/rpool/docker/gitea/runner`):

- the labels `ubuntu-latest`, `ubuntu-24.04` and `ubuntu-22.04` on the
  `docker.gitea.com/runner-images` images, which the Gitea runner declares
  from its `config.yaml` rather than the `GITEA_RUNNER_LABELS` given at
  registration;
- jobs on the stack network `forgejo_forgejo`, where they reach the cache
  server and Forgejo. The compose file fixes that name, so it does not depend
  on the Compose project name;
- the host's `docker.sock` mounted into jobs (`docker_host: automount`), so
  that `docker build` and `docker push` work. Forgejo mounts nothing by
  default;
- the job image pulled for every job, and the CA bundle mounted into jobs.

The cache is kept in `/data/cache`, so it survives a new runner container.
Jobs are not privileged: Docker runs through the host socket, not through a
`docker:dind` service as on the GitLab runner.

Through `docker.sock`, the runner and its jobs control the host's Docker
daemon: only run trusted workflows on it.

## Migration from Gitea

### 1. Prepare Forgejo next to Gitea

Use a temporary name such as `forgejo.home.lan`: add it to DNS so that it
points at Traefik, set `FORGEJO_DOMAIN=forgejo.home.lan`,
`FORGEJO_SSH_PORT=2223` (Gitea keeps 2222) and
`FORGEJO_MIGRATIONS_ALLOW_LOCALNETWORKS=true`, then follow
[First start](#first-start) and [Actions runner](#actions-runner).

Owners of repositories (user accounts and organisations) do not need to be
created by hand: the script does it, see below.

### 2. Freeze and back up Gitea

Gitea keeps running during the import, and nothing makes it read-only: ask
users to stop pushing, and stop its runner. Then back up Gitea (database dump
and data directory). A push made after a repository has been imported is not
in Forgejo.

### 3. Import

Create two tokens. In Gitea, with an admin account (to see every private
repository): `read:repository`, `read:issue`, `read:user`,
`read:organization`, `read:package`. In Forgejo, with an admin account:
`write:repository`, `write:organization`, `read:user`, `write:admin`. These
are the scopes used by `tests/test_stack.sh`. Then run the script without `--apply` and read the plan:

```sh
read -rs GITEA_TOKEN && read -rs FORGEJO_TOKEN && export GITEA_TOKEN FORGEJO_TOKEN
python3 migrate_repos.py --source https://git.home.lan \
  --target https://forgejo.home.lan
```

Add `--apply` to run it. `--only owner/repo` restricts a run to one
repository, which is useful for a first test.

If Traefik serves its default self-signed certificate for the new domain
(step-ca has not issued one yet), the script stops with
`CERTIFICATE_VERIFY_FAILED`. Fix the certificate first if you can.
`--insecure` skips the certificate check for the Forgejo target only, and
prints a warning. Both tokens are then sent to a server whose identity is not
checked: use it only on the local network, for the time of the import.

The script:

- creates the owners missing in Forgejo. An organisation gets the full name,
  description, website, location and visibility it has in Gitea. A user
  account gets the same username, email, full name and visibility, never the
  admin flag, and a random password that nobody knows and that must be
  changed at first login. Before logging in, each user resets it with
  "Forgot password" if mail is set up, or an admin sets a temporary one in
  Site administration > User accounts.
  Accounts that log in through LDAP or OAuth2 in Gitea become local accounts;
  link them to their authentication source again in the admin panel. An
  owner that cannot be created (for example, its email is already used by
  another Forgejo account) is reported, and its repositories are skipped;
- copies code, LFS, wiki, issues, pull requests, labels, milestones and
  releases, and keeps the private flag and the description;
- recreates pull mirrors as mirrors of their upstream URL. Credentials of a
  private upstream cannot be read from Gitea and must be entered again;
- archives again the repositories archived in Gitea. Gitea hides the pull
  requests of an archived repository from its API, so these are copied
  without pull requests. With `--unarchive-source`, the script unarchives each
  of them in Gitea for the time of its copy and archives it again afterwards.
  The Gitea token then needs `write:repository` instead of `read:repository`;
- skips repositories already in Forgejo, so a run can be repeated. When
  Forgejo reports a failed migration, the script deletes the partial copy it
  leaves behind, so that the next run imports it again;
- lists the packages at the end, because Forgejo does not copy them. Push
  container images again, for example with
  `skopeo copy --all docker://git.home.lan/<owner>/<image>:<tag> docker://forgejo.home.lan/<owner>/<image>:<tag>`
  after logging in to both registries.

The dry run prints the owners it would create (`create user <name>`,
`create organisation <name>`). The exit status is 1 when anything was skipped
or failed. Each problem is
printed on its own line.

Forgejo's migration does not copy the following, which must be set up again:
SSH and GPG keys of users, two-factor authentication, personal access tokens,
OAuth2 applications, Actions secrets and variables, webhooks, deploy keys,
collaborators, organisation teams, branch protection rules, stars and
watches. Issues and comments keep the name of their original author, but are
not linked to the matching Forgejo account.

### 4. Check

Browse a few repositories, clone over HTTPS and over SSH (port 2223), run a
trusted workflow, and push a test image to the registry.

### 5. Switch

1. Stop the `gitea` stack (`docker compose down` in `gitea/`, or from
   Portainer). Its data stays in `/rpool/docker/gitea`.
2. In `forgejo/.env`, set `FORGEJO_DOMAIN=git.home.lan`, `FORGEJO_SSH_PORT=2222`
   and `FORGEJO_MIGRATIONS_ALLOW_LOCALNETWORKS=false`, then run
   `docker compose up -d`.
3. Remove the temporary DNS name.

Clone URLs do not change (same host, port and paths). If the SSH host keys
were not copied, clients must remove the old key with
`ssh-keygen -R '[git.home.lan]:2222'`. Registry users log in again with a
Forgejo token.

### Rollback

Before the switch, stop or remove the `forgejo` stack. After the switch, stop
it, then restart the `gitea` stack: its data was not modified. Anything pushed
to Forgejo in the meantime has to be pushed again to Gitea.

Deleting `/rpool/docker/gitea` is a separate decision, to be taken once Forgejo
has run without problems for a while.

## Validate

From this directory, without printing the resolved secrets:

```sh
docker compose --env-file .env config --quiet
```

Tests (Docker, Docker Compose 2.23+, jq, curl and python3 needed):

```sh
python3 -m unittest discover -s tests
./tests/test_stack.sh
```

`test_stack.sh` checks the rendered compose file, then starts this stack and a
`gitea/gitea:latest` on throwaway containers. It imports a private repository,
an organisation repository with an issue, a label and a release, an archived
repository with a pull request, a repository whose owner is missing, and one
whose owner cannot be created. It
also checks that the runner runs a job through `docker.sock`. The unit tests
cover the cases the end-to-end test cannot trigger, such as a migration that
times out or fails on the server side.
