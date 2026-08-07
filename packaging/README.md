# DocSort one-command installer

The installer creates a Docker Compose production stack and a `docsort` lifecycle command on Linux ARM64/AMD64 and macOS Apple Silicon/Intel.

User-facing installation:

```bash
curl -fsSL https://get.docsort.app/install.sh | sudo sh -s -- --domain docs.example.com --image REGISTRY/IMAGE:VERSION
```

LAN-only installation:

```bash
curl -fsSL https://get.docsort.app/install.sh | sudo sh -s -- --lan --image REGISTRY/IMAGE:VERSION
```

macOS installation runs as the logged-in user and requires Docker Desktop and Homebrew:

```bash
curl -fsSL https://get.docsort.app/install.sh | sh -s -- --lan --image REGISTRY/IMAGE:VERSION
```

On macOS, configuration and encrypted local backups live under `~/Library/Application Support/DocSort`, the CLI is installed to `~/.local/bin/docsort`, and the nightly backup is scheduled with `launchd`. Docker Desktop must be running when DocSort or its backup executes.

LAN mode deliberately reports that it uses HTTP. Browser-trusted, unattended HTTPS requires a registered domain; domain mode uses Caddy and Let's Encrypt automatically.

The installer installs Docker on Linux when needed; macOS users install Docker Desktop because it is a signed GUI application requiring normal macOS approval. It generates unique application/admin/WebDAV secrets with mode `0600`, creates a named `docsort_storage` volume, optionally installs Ollama with `qwen2.5:3b`, starts the app, and waits for `/up`.

It also installs encrypted Restic backup scheduling. On Linux, local backups use `/var/backups/docsort/restic`, R2 settings live in `/etc/docsort-backup.env`, and the repository password is `/etc/docsort-backup-password`. On macOS, the equivalent files live under `~/Library/Application Support/DocSort`. Local backups work without cloud credentials; the generated repository password must be copied to an offline password manager.

Lifecycle commands:

```bash
docsort status
docsort update
docsort logs web
docsort backup
docsort backup-status
docsort credentials
docsort doctor
docsort uninstall --confirm
```

Uninstall never removes the persistent data volume or secrets directory. Destructive removal is intentionally not automated.

## Publishing requirement

The application image is not yet hosted in a public registry. Before releasing the installer:

1. Publish the existing Dockerfile as a signed multi-architecture image and set that immutable image reference in the download-page command. Do not rely on an unpinned `latest` tag for customer upgrades.
2. Publish `packaging/docsort` as `docsort`, `packaging/install.sh` as `install.sh`, and a tar archive preserving executable modes and containing the contents of `ops/backup/` as `backup.tar.gz` under the same download base.

## Local smoke test

```bash
docker build -t docsort:installer-test .
sudo DOCSORT_CLI_FILE="$PWD/packaging/docsort" \
  DOCSORT_BACKUP_DIR="$PWD/ops/backup" \
  DOCSORT_INSTALL_ROOT=/tmp/docsort-installer-test \
  sh packaging/install.sh --lan --image docsort:installer-test --no-ollama
```
