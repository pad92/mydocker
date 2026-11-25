# Forgejo

This stack runs Forgejo 17, PostgreSQL 17 and a Forgejo Actions runner
behind Traefik. It replaces the `gitea` stack. The external network
`traefik_gateway` and the certificate resolver `stepca` must already exist.
HTTP redirects to HTTPS, and SSH is published on `FORGEJO_SSH_PORT`.

Forgejo cannot be downgraded: `FORGEJO_VERSION` must never be lower than the
version that last ran on the database.

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

- `DEFAULT_ACTIONS_URL=https://github.com`: `uses: actions/checkout@v4` is
  fetched from github.com, as it was with Gitea. Forgejo's default is
  data.forgejo.org.
- `DISABLE_REGISTRATION=true`: Forgejo lets anyone register by default.
  Accounts are created with the CLI (see [First start](#first-start)) or by
  an admin in Site administration.
- `ALLOW_LOCALNETWORKS=false`: Forgejo refuses to migrate from a private
  address. Set it to true only during an import from the local network: while
  it is true, any user can make Forgejo fetch internal URLs.
- `LFS_START_SERVER=true`: the Git LFS server is off in the image. While it
  is off, a migration copies the pointer files and drops the LFS objects
  without an error.
- The HTTPS router adds `Strict-Transport-Security` (one year) and
  `X-Content-Type-Options: nosniff` through the Traefik middleware
  `forgejo-headers`. Browsers then refuse to open the site over HTTP or with
  an invalid certificate, with no way to click through: renew the step-ca
  certificate before it expires.
- Forgejo and the runner mount the host CA bundle, so they trust the step-ca
  certificates of `*.example.lan`.

## First start

Create the runner directory with the owner given in `.env`. Docker creates
the other two:

```sh
install -d -m 700 -o 1000 -g 1000 /rpool/docker/forgejo/runner
```

Start the stack without the runner, then create the admin account. The CLI
prints a generated password, to be changed at first login:

```sh
docker compose up -d forgejo db
docker exec -u git forgejo forgejo admin user create --admin \
  --username <name> --email <email> --random-password
```

## Login with Authentik (OIDC)

Forgejo is not behind the Traefik forward-auth middleware: Git over HTTPS,
the API, `fj` and the runner cannot follow a browser login. Forgejo instead
uses Authentik as an OpenID Connect login source, next to its local accounts.

The management stack creates the Authentik side with the
`20-forward-auth-apps.yaml` blueprint: a confidential OAuth2 provider with
client ID `forgejo`, the application `forgejo` and the group `forgejo-users`.
Its only redirect URI is
`https://<FORGEJO_DOMAIN>/user/oauth2/authentik/callback`, built from
`FORGEJO_HOST_LOCAL` in `management/.env`, which must equal `FORGEJO_DOMAIN`.
The source must therefore be named `authentik` in Forgejo.

1. In Authentik, *Applications > Providers > Forgejo*, copy the client
   secret. Authentik generates it once and keeps it across blueprint applies.
2. Add the source. `read -rs` keeps the secret out of the shell history.
   `<auth host>` is the Authentik host browsers use (`AUTHENTIK_HOST_PUBLIC`
   if set, else `AUTHENTIK_HOST_LOCAL`); the Forgejo container must resolve
   it and trust its certificate (the host CA bundle is mounted):

   ```sh
   read -rs secret
   docker exec -u git forgejo forgejo admin auth add-oauth \
     --name authentik --provider openidConnect \
     --key forgejo --secret "$secret" \
     --auto-discover-url https://<auth host>/application/o/forgejo/.well-known/openid-configuration
   unset secret
   ```

3. Add the users to `forgejo-users` in Authentik. Authentik refuses the
   login of anyone else.
4. Link the existing accounts: with `DISABLE_REGISTRATION=true`, a first
   *Sign in with authentik* leads to a page where the user logs in with the
   local Forgejo password once; the Authentik identity is then linked to that
   account. No account is created through Authentik.

Limits:

- The `forgejo-users` binding only filters logins through Authentik. Local
  passwords, SSH keys and access tokens keep working as before.
- `docker exec -u git forgejo forgejo admin auth list` shows the source;
  `update-oauth --id <id> --secret ...` changes the secret after a rotation
  in Authentik.

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
Running the command again with the same secret does not create a second
runner.

The example config follows the `config.yaml` of the Gitea runner
(`/rpool/docker/gitea/runner`):

- The labels are `ubuntu-latest`, `ubuntu-24.04` and `ubuntu-22.04`, on the
  `docker.gitea.com/runner-images` images. The Gitea runner took them from its
  `config.yaml`, and ignored the `GITEA_RUNNER_LABELS` given at registration.
- Jobs run on the stack network `forgejo_forgejo`, where they reach the cache
  server and Forgejo. The compose file fixes that name, so it does not depend
  on the Compose project name.
- Jobs get the host's `docker.sock` (`docker_host: automount`), so that
  `docker build` and `docker push` work. Forgejo mounts nothing by default.
  Jobs are not privileged: Docker runs through the host socket, not through a
  `docker:dind` service as on the GitLab runner.
- The job image is pulled for every job, and the CA bundle is mounted into
  jobs.
- The cache is kept in `/data/cache`, so it survives a new runner container.

Through `docker.sock`, the runner and its jobs control the host's Docker
daemon: only run trusted workflows on it.

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
`gitea/gitea:latest` on throwaway containers, with Traefik disabled on them.
It checks that:

- the sign-up page offers no form and submitting one creates no account.
  `FORGEJO_TEST_EXPECT_REGISTRATION=open ./tests/test_stack.sh` proves that
  both checks can fail: with registration open, the form is there and the
  same request creates an account;
- the import copies a private repository, an organisation repository with an
  issue, a label and a release, and an archived repository with a pull
  request, and reports a repository whose owner is missing and one whose
  owner cannot be created;
- the runner runs a job through `docker.sock`.

The unit tests cover the cases the end-to-end test cannot trigger, such as a
migration that times out or fails on the server side.

## Migration from Gitea

Forgejo can only start on the data of Gitea 1.22 or older
([Forgejo documentation](https://forgejo.org/docs/v15.0/admin/upgrade/from-gitea/)).
Production ran Gitea 28.3.0, so Forgejo starts on an empty database and
`migrate_repos.py` imports each repository with Forgejo's migration tool.
Gitea's data in `/rpool/docker/gitea` is never modified.

### Procedure

1. Run Forgejo next to Gitea under a temporary DNS name that points at
   Traefik, with `FORGEJO_DOMAIN=forgejo.example.lan`, `FORGEJO_SSH_PORT=2223`
   and `FORGEJO_MIGRATIONS_ALLOW_LOCALNETWORKS=true`. Before the first start,
   copy Gitea's SSH host keys, so that clients get no "host key changed"
   warning after the switch:

   ```sh
   install -d -m 700 /rpool/docker/forgejo/data/ssh
   cp -p /rpool/docker/gitea/data/ssh/ssh_host_* /rpool/docker/forgejo/data/ssh/
   ```

   Carry over by hand the settings made in Gitea's `app.ini` (mail, webhook
   allow list, and so on), as `FORGEJO__<section>__<KEY>` variables in
   `docker-compose.yml`. Then follow [First start](#first-start) and
   [Actions runner](#actions-runner).
2. Ask users to stop pushing, stop Gitea's runner, and back up Gitea
   (database dump and data directory). Nothing makes Gitea read-only: a push
   made after a repository has been imported is not in Forgejo.
3. [Import](#import) the repositories, then set up again
   [what is not copied](#not-copied).
4. Check: browse a few repositories, clone over HTTPS and over SSH (port
   2223), run a trusted workflow, and push a test image to the registry.
5. Switch: stop the `gitea` stack. In `forgejo/.env`, set
   `FORGEJO_DOMAIN=git.example.lan`, `FORGEJO_SSH_PORT=2222` and
   `FORGEJO_MIGRATIONS_ALLOW_LOCALNETWORKS=false`, run `docker compose up -d`,
   and remove the temporary DNS name. Clone URLs do not change. Registry
   users log in again with a Forgejo token. If the SSH host keys were not
   copied, clients remove the old key with
   `ssh-keygen -R '[git.example.lan]:2222'`.

To roll back, stop the `forgejo` stack and restart the `gitea` stack.
Anything pushed to Forgejo in the meantime has to be pushed again to Gitea.
Delete `/rpool/docker/gitea` only once Forgejo has run without problems for a
while.

### Import

Create two tokens, each with an admin account. The Gitea admin account is
what lets the script see every private repository.

| Server | Scopes |
| --- | --- |
| Gitea | `read:repository`, `read:issue`, `read:user`, `read:organization`, `read:package` |
| Forgejo | `write:repository`, `write:organization`, `read:user`, `write:admin` |

Without `--apply`, the script prints its plan, including the owners it would
create:

```sh
read -rs GITEA_TOKEN && read -rs FORGEJO_TOKEN && export GITEA_TOKEN FORGEJO_TOKEN
python3 migrate_repos.py --source https://git.example.lan \
  --target https://forgejo.example.lan
```

Add `--apply` to run it, and `--only owner/repo` to restrict it to one
repository. The exit status is 1 when anything was skipped or failed, and
each problem is printed on its own line. A run can be repeated: repositories
already in Forgejo are skipped, and the partial copy left by a failed
migration is deleted, so the next run imports it again.

The script:

- creates the owners missing in Forgejo. An organisation keeps its full name,
  description, website, location and visibility. A user account keeps its
  username, email, full name and visibility, never the admin flag, and gets a
  random password that nobody knows: the user resets it with "Forgot
  password" if mail is set up, or an admin sets a temporary one in Site
  administration > User accounts. LDAP and OAuth2 accounts become local
  accounts, to be linked to their authentication source again in the admin
  panel. An owner that cannot be created (for example, its email is already
  used by another Forgejo account) is reported, and its repositories are
  skipped;
- copies code, LFS, wiki, issues, pull requests, labels, milestones and
  releases, and keeps the private flag and the description;
- recreates pull mirrors as mirrors of their upstream URL. Credentials of a
  private upstream cannot be read from Gitea and must be entered again;
- archives again the repositories archived in Gitea. Gitea hides their pull
  requests from its API, so they are copied without pull requests, unless
  `--unarchive-source` unarchives each of them in Gitea for the time of its
  copy. The Gitea token then needs `write:repository` in place of
  `read:repository`;
- lists the packages at the end, because Forgejo does not copy them.

If Traefik still serves its default self-signed certificate for the new
domain, the script stops with `CERTIFICATE_VERIFY_FAILED`. Fix the
certificate first if you can. `--insecure` skips the certificate check for
the Forgejo target only, and prints a warning. Both tokens are then sent to a
server whose identity is not checked: use it only on the local network, for
the time of the import.

### Not copied

Push container images again, for example with
`skopeo copy --all docker://git.example.lan/<owner>/<image>:<tag> docker://forgejo.example.lan/<owner>/<image>:<tag>`
after logging in to both registries.

Forgejo's migration does not copy the SSH and GPG keys of users, two-factor
authentication, personal access tokens, OAuth2 applications, Actions secrets
and variables, webhooks, deploy keys, collaborators, organisation teams,
branch protection rules, stars and watches. Until a user adds their GPG key
to their Forgejo account, their signed commits show as unverified. Issues and
comments keep the name of their original author, but are not linked to the
matching Forgejo account.
