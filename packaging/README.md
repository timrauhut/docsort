# DocSort one-command installer

The first distribution milestone installs a Docker Compose production stack and a `docsort` lifecycle command on Linux ARM64 or AMD64.

User-facing installation:

```bash
curl -fsSL https://get.docsort.app/install.sh | sudo sh -s -- --domain docs.example.com --image REGISTRY/IMAGE:VERSION
```

LAN-only installation:

```bash
curl -fsSL https://get.docsort.app/install.sh | sudo sh -s -- --lan --image REGISTRY/IMAGE:VERSION
```

LAN mode deliberately reports that it uses HTTP. Browser-trusted, unattended HTTPS requires a registered domain; domain mode uses Caddy and Let's Encrypt automatically.

The installer installs Docker on Linux when needed, generates unique application/admin/WebDAV secrets in `/opt/docsort/docsort.env` with mode `0600`, creates a named `docsort_storage` volume, optionally installs Ollama with `qwen2.5:3b`, starts the app, and waits for `/up`.

It also installs the existing Restic backup timers. Local encrypted backups work without cloud credentials and use `/var/backups/docsort/restic`. R2 is enabled later by filling `/etc/docsort-backup.env`; the repository password is generated once at `/etc/docsort-backup-password` with mode `0600` and must be copied to an offline password manager.

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
2. Publish `packaging/docsort` as `docsort`, `packaging/install.sh` as `install.sh`, and a tar archive containing the contents of `ops/backup/` as `backup.tar.gz` under the same download base.

## Local smoke test

```bash
docker build -t docsort:installer-test .
sudo DOCSORT_CLI_FILE="$PWD/packaging/docsort" \
  DOCSORT_BACKUP_DIR="$PWD/ops/backup" \
  DOCSORT_INSTALL_ROOT=/tmp/docsort-installer-test \
  sh packaging/install.sh --lan --image docsort:installer-test --no-ollama
```
