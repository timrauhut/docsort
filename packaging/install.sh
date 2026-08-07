#!/usr/bin/env sh
set -eu

DOWNLOAD_BASE="${DOCSORT_DOWNLOAD_BASE:-https://get.docsort.app}"
INSTALL_BIN="${DOCSORT_INSTALL_BIN:-/usr/local/bin/docsort}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this installer with sudo." >&2
  exit 1
fi

command -v curl >/dev/null 2>&1 || {
  echo "curl is required to install DocSort." >&2
  exit 1
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT INT TERM

if ! command -v docker >/dev/null 2>&1; then
  [ "$(uname -s)" = Linux ] || {
    echo "Automatic Docker installation is supported on Linux only." >&2
    exit 1
  }
  echo "Docker is not installed; installing it with Docker's official convenience script."
  curl -fsSL https://get.docker.com -o "$tmp_dir/get-docker.sh"
  sh "$tmp_dir/get-docker.sh"
fi

docker compose version >/dev/null 2>&1 || {
  echo "Docker Compose v2 is required." >&2
  exit 1
}

if [ -n "${DOCSORT_CLI_FILE:-}" ]; then
  cp "$DOCSORT_CLI_FILE" "$tmp_dir/docsort"
else
  curl -fsSL "$DOWNLOAD_BASE/docsort" -o "$tmp_dir/docsort"
fi

install -m 0755 "$tmp_dir/docsort" "$INSTALL_BIN"
"$INSTALL_BIN" install "$@"

if [ "${DOCSORT_SKIP_BACKUPS:-false}" != true ]; then
  if [ -n "${DOCSORT_BACKUP_DIR:-}" ]; then
    backup_dir="$DOCSORT_BACKUP_DIR"
  else
    command -v tar >/dev/null 2>&1 || {
      echo "tar is required to install DocSort backups." >&2
      exit 1
    }
    curl -fsSL "$DOWNLOAD_BASE/backup.tar.gz" -o "$tmp_dir/backup.tar.gz"
    mkdir "$tmp_dir/backup"
    tar -xzf "$tmp_dir/backup.tar.gz" -C "$tmp_dir/backup"
    backup_dir="$tmp_dir/backup"
  fi
  "$backup_dir/install"
fi

echo "DocSort installation finished. Run 'docsort status' to verify it."
