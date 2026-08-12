#!/usr/bin/env sh
set -eu

DOWNLOAD_BASE="${DOCSORT_DOWNLOAD_BASE:-https://github.com/timrauhut/docsort/releases/latest/download}"
os_name="$(uname -s)"
if [ "$os_name" = Darwin ]; then
  INSTALL_BIN="${DOCSORT_INSTALL_BIN:-$HOME/.local/bin/docsort}"
else
  INSTALL_BIN="${DOCSORT_INSTALL_BIN:-/usr/local/bin/docsort}"
fi

if [ "$os_name" = Linux ] && [ "$(id -u)" -ne 0 ]; then
  echo "Run this installer with sudo." >&2
  exit 1
fi
if [ "$os_name" = Darwin ] && [ "$(id -u)" -eq 0 ]; then
  echo "On macOS, run this installer without sudo." >&2
  exit 1
fi

command -v curl >/dev/null 2>&1 || {
  echo "curl is required to install DocSort." >&2
  exit 1
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT INT TERM

if ! command -v docker >/dev/null 2>&1; then
  [ "$os_name" = Linux ] || {
    echo "Install and start Docker Desktop for Mac, then rerun this installer:" >&2
    echo "https://docs.docker.com/desktop/setup/install/mac-install/" >&2
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
docker info >/dev/null 2>&1 || {
  echo "Docker is installed but not running. Start Docker Desktop or the Docker service." >&2
  exit 1
}

if [ -n "${DOCSORT_CLI_FILE:-}" ]; then
  cp "$DOCSORT_CLI_FILE" "$tmp_dir/docsort"
else
  curl -fsSL "$DOWNLOAD_BASE/docsort" -o "$tmp_dir/docsort"
fi

install -d "$(dirname "$INSTALL_BIN")"
internal_bin="${INSTALL_BIN}.internal"
paths_file="${INSTALL_BIN}.paths"
install -m 0755 "$tmp_dir/docsort" "$internal_bin"
"$internal_bin" install "$@"

umask 077
{
  printf 'DOCSORT_INSTALL_ROOT=%s\n' "${DOCSORT_INSTALL_ROOT:-}"
  printf 'DOCSORT_BACKUP_ROOT=%s\n' "${DOCSORT_BACKUP_ROOT:-}"
} >"$paths_file"

cat >"$INSTALL_BIN" <<'SH'
#!/bin/sh
set -eu
paths_file="$0.paths"
internal_bin="$0.internal"
if [ -f "$paths_file" ]; then
  install_root="$(sed -n 's/^DOCSORT_INSTALL_ROOT=//p' "$paths_file")"
  backup_root="$(sed -n 's/^DOCSORT_BACKUP_ROOT=//p' "$paths_file")"
  [ -z "$install_root" ] || export DOCSORT_INSTALL_ROOT="$install_root"
  [ -z "$backup_root" ] || export DOCSORT_BACKUP_ROOT="$backup_root"
fi
exec "$internal_bin" "$@"
SH
chmod 0755 "$INSTALL_BIN"

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
  if [ "$os_name" = Darwin ]; then
    "$backup_dir/install-macos"
  else
    DOCSORT_INSTALL_ROOT="${DOCSORT_INSTALL_ROOT:-/opt/docsort}" \
      DOCSORT_BACKUP_ROOT="${DOCSORT_BACKUP_ROOT:-}" \
      "$backup_dir/install"
  fi
fi

echo "DocSort installation finished. Run 'docsort status' to verify it."
if [ "$os_name" = Darwin ]; then
  echo "If docsort is not found, add $HOME/.local/bin to your PATH."
fi
