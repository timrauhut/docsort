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
curl -fsSL https://get.docsort.app/install.sh | sh -s -- --lan
```

On macOS, configuration and encrypted local backups live under `~/Library/Application Support/DocSort`, the CLI is installed to `~/.local/bin/docsort`, and the nightly backup is scheduled with `launchd`. Docker Desktop must be running when DocSort or its backup executes.

LAN mode deliberately reports that it uses HTTP. Browser-trusted, unattended HTTPS requires a registered domain; domain mode uses Caddy and Let's Encrypt automatically.

The installer installs Docker on Linux when needed; macOS users install Docker Desktop because it is a signed GUI application requiring normal macOS approval. It generates unique application/admin/WebDAV secrets with mode `0600`, creates a named `docsort_storage` volume, optionally installs Ollama with `qwen2.5:3b`, starts the app, and waits for `/up`. On success it clearly prints the initial `admin` username and generated password. The initial value can be displayed with `docsort credentials --show`; after first sign-in the web app requires a new password, which is stored only as a secure hash and cannot be displayed by the CLI.

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

`docsort update` creates an encrypted backup before pulling images. It only reports success after the replacement web container passes its health check; if startup or health verification fails, it automatically restores the previously installed image.

Uninstall never removes the persistent data volume or secrets directory. Destructive removal is intentionally not automated.

## Publishing

1. Push a version tag such as `v0.3.0`. `.github/workflows/publish-image.yml` creates the GitHub Release, builds `linux/amd64` and `linux/arm64`, publishes version, SHA, and `stable` tags to `ghcr.io/timrauhut/docsort`, generates an SBOM/provenance, creates a GitHub build attestation, and attaches `install.sh`, `docsort`, and `backup.tar.gz` to the release. The installer downloads those assets through GitHub's `releases/latest/download` endpoint. It follows the explicit `stable` image channel and never uses `latest`; immutable version and SHA tags remain available for pinning and rollback.
2. After the first publish, set the `ghcr.io/timrauhut/docsort` package visibility to public so installations can pull it without GitHub credentials.

## Local smoke test

```bash
docker build -t docsort:installer-test .
sudo DOCSORT_CLI_FILE="$PWD/packaging/docsort" \
  DOCSORT_BACKUP_DIR="$PWD/ops/backup" \
  DOCSORT_INSTALL_ROOT=/tmp/docsort-installer-test \
  sh packaging/install.sh --lan --image docsort:installer-test --no-ollama
```
