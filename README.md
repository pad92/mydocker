# Portainer Stacks Migrator to Git

This project contains self-contained Python scripts to cleanly export and migrate all configuration settings from your **Portainer stacks** (both `docker-compose.yml` files and environment variables) to version control them in a Git repository.

## Features

- No dependencies beyond the standard Python 3 library, so there's no need for `pip` or virtual environments.
- Security is handled for you: it writes a `.env` file with the real values, a `.env.example` template with only the keys so it's safe to commit, and a root `.gitignore` that excludes `.env` files automatically.
- Supports both Portainer API access tokens (recommended) and classic username/password authentication.
- Can skip SSL verification for Portainer instances using self-signed certificates.
- Exports each stack as `stack_name/docker-compose.yml`.
- Switches Portainer stacks from "Web Editor" to "Git Repository" mode via the API without losing data.

---

## Stacks Hosted in this Repository

Here is the complete list of Docker Compose stacks managed in this repository:

| Stack | Description | Main Service |
| :--- | :--- | :--- |
| [**adguard**](./adguard/README.md) | DNS-level ad and tracker blocker | AdGuard Home |
| [**audiomuse_ai**](./audiomuse_ai/README.md) | AI-powered audio tools suite | Audiomuse AI |
| [**beszel**](./beszel/README.md) | Lightweight server performance dashboard and alerting dashboard gateway | Beszel Hub |
| [**beszel-agent**](./beszel-agent/README.md) | Lightweight client metrics agent executing resource monitoring on host system | Beszel Agent |
| [**bookmarks**](./bookmarks/README.md) | Personal link sharing, bookmarking page, and blog index | Shaarli |
| [**cloudflared**](./cloudflared/README.md) | Secure routing tunnel connecting local resources to Cloudflare CDN edge network | Cloudflare Tunnel |
| [**code-server**](./code-server/README.md) | VS Code editor accessible inside browser tabs | VS Code Server |
| [**crowdsec**](./crowdsec/README.md) | Collaborative behavior detection engine blocking scanner IP logs and malicious activities | CrowdSec |
| [**dockhand**](./dockhand/README.md) | Automated Docker container management and helper tool | Dockhand |
| [**forgejo**](./forgejo/README.md) | Self-hosted Git forge with Actions and package registry, replacing Gitea | Forgejo |
| [**freshrss**](./freshrss/README.md) | Self-hosted RSS feed aggregator and reader | FreshRSS |
| [**frigate**](./frigate/README.md) | Network Video Recorder (NVR) with real-time AI object detection for IP cameras | Frigate |
| [**gitea**](./gitea/README.md) | Super fast, lightweight, and painless self-hosted Git developer service | Gitea |
| [**gitlab**](./gitlab/README.md) | Git project hoster, issue tracker, and DevOps integration server | GitLab |
| [**gitlab-runner**](./gitlab-runner/README.md) | Local CI/CD pipeline build executor for GitLab projects | GitLab Runner |
| [**glance**](./glance/README.md) | Personal startpage aggregation dashboard page | Glance Dashboard |
| [**grafana**](./grafana/README.md) | Advanced monitoring visualization metrics dashboards aggregator | Grafana |
| [**grampsweb**](./grampsweb/README.md) | Web app for collaborative genealogy built on Gramps | Gramps Web |
| [**homeassistant**](./homeassistant/README.md) | Central home automation router putting local privacy and local controls first | Home Assistant |
| [**immich**](./immich/README.md) | High-performance self-hosted photo & video backup solution | Immich |
| [**karakeep**](./karakeep/README.md) | High-performance bookmarks manager with fast search | Karakeep |
| [**librespeed**](./librespeed/README.md) | Self-hosted speed test server | LibreSpeed |
| [**management**](./management/README.md) | Portainer CE/EE, Traefik routing gateway, and service status monitors stack | Portainer & Traefik |
| [**manyfold**](./manyfold/README.md) | Multi-user digital asset manager for 3D printing STL and CAD files | Manyfold |
| [**minio**](./minio/README.md) | High-performance Amazon S3-compatible object storage server | MinIO |
| [**netbox**](./netbox/README.md) | Network resource management and infrastructure documentation (IPAM / DCIM) platform | NetBox |
| [**netdata**](./netdata/README.md) | Real-time system performance monitoring and troubleshooting | Netdata |
| [**nextcloud**](./nextcloud/README.md) | Safe home storage storage system and document sharing suite | Nextcloud |
| [**ng**](./ng/README.md) | Media servers and downloaders suite (Radarr, Sonarr, etc.) | Arr Stack |
| [**ollama**](./ollama/README.md) | Hardware-accelerated local LLM models inference engine | Ollama |
| [**omni-tools**](./omni-tools/README.md) | A collection of handy daily utilities | Omni-Tools |
| [**openobserve**](./openobserve/README.md) | Observability platform for logs, metrics, and traces | OpenObserve |
| [**openproject**](./openproject/README.md) | Collaborative project management and tracking tool | OpenProject |
| [**overleaf**](./overleaf/README.md) | Collaborative browser-based LaTeX compiler and editor | Overleaf (ShareLaTeX) |
| [**papermerge**](./papermerge/README.md) | Open source document management system for digital archives | Papermerge DMS |
| [**photoprism**](./photoprism/README.md) | AI-powered digital photo aggregation catalog manager | PhotoPrism |
| [**plex**](./plex/README.md) | Centralized video, TV show, movie, and audio streaming hub server | Plex Media Server |
| [**scanopy**](./scanopy/README.md) | Document digitization and archiving solution | Scanopy |
| [**spotify-to-plex**](./spotify-to-plex/README.md) | Sync utility to transfer Spotify playlists to Plex Media Server | Spotify to Plex |
| [**stable-diffusion**](./stable-diffusion/README.md) | AI image generator | Stable Diffusion WebUI |
| [**todo**](./todo/README.md) | Task list and todo management dashboard | Donetick |
| [**trilium**](./trilium/README.md) | Hierarchical personal note-taking application focusing on large personal knowledge bases | Trilium Notes |
| [**tududi**](./tududi/README.md) | Minimal personal task manager interface | Tududi |
| [**vaultwarden**](./vaultwarden/README.md) | Alternative lightweight Bitwarden password vault server in Rust | Vaultwarden |
| [**watchtower**](./watchtower/README.md) | Automated helper daemon to keep running docker container images up to date | Watchtower |

---

## Scripts Overview

| Script | Purpose |
| :--- | :--- |
| [`export_portainer.py`](#exporting-stacks) | Export docker-compose files and environment variables from Portainer into local directories |
| [`migrate_to_git.py`](#automated-migration-to-git-mode) | Switch Portainer stacks from "Web Editor" to "Git Repository" mode via the API |

---

## Prerequisites

- **Python 3.x** installed on your machine.
- A **Portainer (CE or EE)** instance.
- An **API Access Token** (generated in Portainer under *User settings* > *Access tokens*) **OR** your login credentials.

---

## Exporting Stacks

Use `export_portainer.py` to download all stack configurations from Portainer into local directories:

### Option A: Authentication via API Key (Recommended & Secure)

1. Obtain your API key from the Portainer interface (*User settings* -> *Access tokens*).
2. Run the script:

```bash
./export_portainer.py --url "https://portainer.your-domain.com" --token "ptr_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

### Option B: Authentication via Username / Password

The script will prompt you for your password interactively and securely:

```bash
./export_portainer.py --url "https://portainer.your-domain.com" --username "my_admin"
```

### Additional Options

- **Self-signed SSL certificates**: If your Portainer instance uses HTTPS with an unverified certificate, add the `--insecure` option:
  ```bash
  ./export_portainer.py --url "https://192.168.1.100:9443" --token "..." --insecure
  ```
- **Specify output directory**: By default, the export goes to the current directory. You can set another target path with `--output`:
  ```bash
  ./export_portainer.py --url "..." --token "..." --output "./stacks-export"
  ```

---

## Automated Migration to Git Mode

Once your stacks are exported and committed to Git, use `migrate_to_git.py` to automatically switch Portainer stacks from "Web Editor" mode to "Git Repository" mode via the API.

> [!IMPORTANT]
> Only stacks that already have a local directory (with `docker-compose.yml`) in this repository will be migrated. Stacks without a matching folder are skipped.

### Step 1: Preview with Dry Run

Always start with `--dry-run` to see a report of what would happen without making any changes:

```bash
./migrate_to_git.py \
  --url "https://portainer.your-domain.com" \
  --token "ptr_xxx" \
  --repo-url "https://gitea.your-domain.com/user/stacks.git" \
  --insecure \
  --dry-run
```

The report classifies each Portainer stack into one of four categories:

| Category | Description |
| :--- | :--- |
| `[git]` | Already managed via Git — no action needed |
| `[skip]` | No local directory found — will not be migrated |
| `[excl]` | Explicitly excluded via `--exclude` |
| `[migrate]` | Ready to be migrated to Git mode |

### Step 2: Run the Migration

```bash
./migrate_to_git.py \
  --url "https://portainer.your-domain.com" \
  --token "ptr_xxx" \
  --repo-url "https://gitea.your-domain.com/user/stacks.git" \
  --insecure
```

For each stack to migrate, the script will:
1. **Delete** the existing stack in Portainer (containers stop, but volumes and data are preserved).
2. **Wait** a few seconds (configurable with `--delay`).
3. **Recreate** the stack in "Repository" mode, pointing to the Git repository with the original environment variables.

### Migration Options

| Option | Description |
| :--- | :--- |
| `--dry-run` | Preview changes without modifying anything |
| `--exclude stack1 stack2` | Exclude specific stacks from migration |
| `--only stack1 stack2` | Only migrate the specified stacks |
| `--repo-ref refs/heads/main` | Git branch reference (default: `refs/heads/main`) |
| `--repo-username` / `--repo-password` | Git authentication (if the repository is private) |
| `--repo-insecure` | Skip TLS verification for the Git repository |
| `--auto-update` | Enable automatic Git polling in Portainer (5 min interval) |
| `--delay 3` | Seconds to wait between delete and recreate (default: 3) |
| `-y` | Skip the confirmation prompt |

### Example: Migrate Only Specific Stacks

```bash
./migrate_to_git.py \
  --url "https://portainer.local:9443" \
  --token "ptr_xxx" \
  --repo-url "https://gitea.local/pascal/mydocker.git" \
  --only plex immich grafana \
  --insecure
```

### Example: Migrate All Except Some Stacks

```bash
./migrate_to_git.py \
  --url "https://portainer.local:9443" \
  --token "ptr_xxx" \
  --repo-url "https://gitea.local/pascal/mydocker.git" \
  --exclude management cloudflared \
  --insecure
```

---

## Git Hooks Configuration (Secret Leak Prevention)

To prevent accidentally committing files containing secrets (like real `.env` files) or sensitive data to your Git repository, a leak detection system is configured in the `.githooks` folder.

To enable this automatic protection in your local repository, run the following commands from the root of your project:

```bash
# 1. Make hook scripts executable
chmod +x .githooks/pre-commit .githooks/post-commit .githooks/git-leak-shield.py

# 2. Configure Git to use the .githooks directory
git config core.hooksPath .githooks
```

### How It Works

- **`pre-commit`**: Automatically scans your staged changes before each commit. If a `.env` file, secret, API key, or sensitive data is detected, the commit is blocked immediately.
- **`post-commit`**: Displays a confirmation message after a commit is successfully and securely validated.

---

## Repository Structure after Export

Once the export is complete, your folder structure will look like this:

```text
mydocker/
├── export_portainer.py
├── README.md
├── .gitignore               # Protects your secrets by ignoring all .env files
├── stack-nginx/
│   ├── docker-compose.yml   # Raw compose file
│   ├── .env                 # Real values from Portainer (Ignored by Git)
│   └── .env.example         # Empty template ready to be committed
└── stack-database/
    ├── docker-compose.yml
    ├── .env
    └── .env.example
```

---

## Zero-Downtime Git & Portainer Migration Guide

Here is the complete method to version control your configurations and transition your existing Portainer stacks into Git-managed stacks, with no data loss and under 10 seconds of downtime.

---

### Step 1: Export Stacks from Portainer

Use `export_portainer.py` to download all stack configurations:

```bash
./export_portainer.py --url "https://portainer.local:9443" --token "ptr_xxx" --insecure
```

### Step 2: Initialize and Push the Git Repository

Thanks to the root `.gitignore` file, your real environment variables (`.env`) will never be pushed to Git. Only your deployment files and their templates (`.env.example`) will be versioned.

```bash
# 1. Initialize the local Git repository
git init

# 2. Add all files (real .env files are automatically excluded)
git add .

# 3. Perform the initial commit
git commit -m "feat: initial migration of Portainer stacks"

# 4. Configure the remote repository (e.g., Gitea) and push
git remote add origin <YOUR_GIT_REPO_URL>
git branch -M main
git push -u origin main
```

---

### Step 3: Understand Data Persistence

> [!NOTE]
> In Docker, databases and configuration files are stored in **volumes** or **local folders (bind mounts)**.
> Deleting a stack in Portainer only stops the containers but **does not delete your data**. Recreating the stack with the exact same configuration will instantly reconnect the containers to your existing volumes.

---

### Step 4: Migrate Stacks to Git Mode

#### Option A: Automated Migration (Recommended)

Use `migrate_to_git.py` to migrate all eligible stacks in one command:

```bash
# Preview first
./migrate_to_git.py \
  --url "https://portainer.local:9443" \
  --token "ptr_xxx" \
  --repo-url "https://gitea.home.lan/pascal/stacks.git" \
  --insecure --dry-run

# Then migrate
./migrate_to_git.py \
  --url "https://portainer.local:9443" \
  --token "ptr_xxx" \
  --repo-url "https://gitea.home.lan/pascal/stacks.git" \
  --insecure
```

See [Automated Migration to Git Mode](#automated-migration-to-git-mode) for all available options.

#### Option B: Manual Migration (Per Stack)

To convert a single stack from "Web Editor" mode to "Git Repository" mode manually:

1. **Copy the environment variables**:
   - Open the local folder of the exported stack (e.g., `./plex/`).
   - Open the `.env` file containing the real variables and **copy its entire content** (`KEY=VALUE`).

2. **Delete the old stack in Portainer**:
   - In Portainer, open the corresponding stack and click **Delete this stack** (containers will stop, but data persists).

3. **Recreate the stack in Git mode**:
   - Click **Add stack** immediately at the top right.
   - Configure the following fields:
     - **Name**: Enter the **exact same name** as the old stack (e.g., `plex`).
     - **Build method**: Select **Repository**.
     - **Repository URL**: Enter the HTTP/SSH URL of your Git repository (e.g., `https://gitea.home.lan/pascal/stacks.git`).
     - **Repository reference**: Enter your branch (e.g., `refs/heads/main`).
     - **Compose path**: Specify the exact path to the compose file (e.g., `plex/docker-compose.yml`).
   - In the **Environment variables** section:
     - Click the **Advanced mode** button (top right of the section).
     - **Paste** the entire content of the `.env` file copied in step 1.
   - Click **Deploy the stack**.

Docker recreates the stack within seconds. The containers restart identically, connected to their existing volumes, but now linked to your Git repository for future updates.
