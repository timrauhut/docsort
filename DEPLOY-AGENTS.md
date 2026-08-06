# Deploying DocSort — instructions for coding agents

**Audience:** agents shipping code to the production Raspberry Pi.  
**Policy:** only deploy when the **user explicitly asks**. Confirm the Pi is reachable before long builds.  
**Human deep-dive:** `DEPLOY.md`. **Architecture:** `LLM-WIKI.md`.

---

## 0. What “production” is (this repo’s real topology)

| Item | Value |
|------|--------|
| Host | `192.168.178.158` |
| SSH | `pi@…` port **`2222`**, key `~/.ssh/id_ed25519` |
| App URL | `https://docsort.local` or `https://192.168.178.158` |
| Health | `GET /up` → **200** |
| Orchestration | **Kamal 2** (`config/deploy.yml`) |
| Image arch | **arm64** (build on Apple Silicon / multi-arch) |
| Registry | `localhost:5555` (local Docker registry on the **build machine**, not a public registry) |
| Why not plain `kamal deploy`? | Pi cannot pull from the Mac’s registry reliably → **build on Mac → `docker save` \| SSH `docker load` → `kamal deploy --skip-push`** |

Containers on the Pi:

- `docsort-web-<gitsha>` — Rails + Thruster + Solid Queue in Puma  
- `docsort-ollama` — LLM accessory  
- `kamal-proxy` — HTTPS front with a custom LAN certificate (hosts: IP, `docsort.local`, `docsort`)

Data volumes: `docsort_storage` → `/rails/storage` (SQLite, blobs, sorted/, inbox/). Migrations run on container boot (`db:prepare` via entrypoint).

---

## 1. Preconditions (check every time)

Run from repo root on the **operator Mac** (not on the Pi):

```bash
export PATH="/opt/homebrew/opt/ruby/bin:/opt/homebrew/lib/ruby/gems/4.0.0/bin:$(pwd)/vendor/bundle/ruby/4.0.0/bin:$PATH"
cd /Users/tr/Projects/docsort   # or the workspace path

# 1) Git: image tag = HEAD. Uncommitted deploy-critical code must be committed first.
git status -sb
git rev-parse HEAD

# 2) Secrets
test -f config/master.key || { echo "missing master.key"; exit 1; }
test -f config/tls/docsort.pem || { echo "missing LAN TLS certificate; run bin/setup-lan-tls"; exit 1; }
test -f config/tls/docsort-key.pem || { echo "missing LAN TLS private key; run bin/setup-lan-tls"; exit 1; }

# Prefer explicit admin password (also used as WebDAV seed password)
PASS=$(cat /tmp/docsort-admin-password.txt 2>/dev/null || true)
export DOCSORT_ADMIN_PASSWORD="${PASS:-${DOCSORT_ADMIN_PASSWORD:-}}"
# Legacy alias still accepted by .kamal/secrets:
export WEBDAV_PASSWORD="${DOCSORT_ADMIN_PASSWORD:-$WEBDAV_PASSWORD}"

if [ -z "${DOCSORT_ADMIN_PASSWORD:-}" ] && [ -z "${WEBDAV_PASSWORD:-}" ]; then
  echo "Set DOCSORT_ADMIN_PASSWORD (or WEBDAV_PASSWORD) before deploy"
  exit 1
fi

# 3) Pi online?
ssh -p 2222 -i "$HOME/.ssh/id_ed25519" -o BatchMode=yes -o ConnectTimeout=10 \
  pi@192.168.178.158 "echo ok"
```

If SSH fails (`Host is down` / timeout): **stop**. Tell the user the Pi is offline; do not start a 5‑minute build that cannot transfer.

Also need: Docker Desktop running (for `bin/kamal build` and local registry).

---

## 2. Standard release (subsequent deploys) — copy this recipe

This is the **proven** path used after logo/UI/OCR changes:

```bash
export PATH="/opt/homebrew/opt/ruby/bin:/opt/homebrew/lib/ruby/gems/4.0.0/bin:$(pwd)/vendor/bundle/ruby/4.0.0/bin:$PATH"
cd /Users/tr/Projects/docsort

PASS=$(cat /tmp/docsort-admin-password.txt 2>/dev/null || true)
export DOCSORT_ADMIN_PASSWORD="${PASS:-changeme}"   # only if file missing; prefer real secret
export WEBDAV_PASSWORD="$DOCSORT_ADMIN_PASSWORD"

# Commit deployable changes first if needed
# git add … && git commit -m "…"

# A) Build arm64 image and push to local registry on the Mac
bin/kamal build push

TAG=$(git rev-parse HEAD)
echo "TAG=$TAG"

# B) Ensure the image exists as a local docker image for save
docker pull "localhost:5555/docsort:${TAG}"

# C) Transfer image to Pi (no registry pull on Pi)
docker save "localhost:5555/docsort:${TAG}" | \
  ssh -p 2222 -i "$HOME/.ssh/id_ed25519" \
    -o BatchMode=yes -o ServerAliveInterval=15 -o ServerAliveCountMax=120 \
    pi@192.168.178.158 "docker load"

# D) Tag + preserve Rails master key / admin password on Pi
ssh -p 2222 -i "$HOME/.ssh/id_ed25519" -o BatchMode=yes pi@192.168.178.158 \
  "docker tag localhost:5555/docsort:${TAG} localhost:5555/docsort:latest
   KEY=\$(grep '^RAILS_MASTER_KEY=' .kamal/apps/docsort/env/roles/web.env 2>/dev/null | cut -d= -f2-)
   if [ -n \"\$KEY\" ]; then
     printf 'RAILS_MASTER_KEY=%s\nDOCSORT_ADMIN_PASSWORD=%s\n' \"\$KEY\" '${DOCSORT_ADMIN_PASSWORD}' \
       > .kamal/apps/docsort/env/roles/web.env
     chmod 600 .kamal/apps/docsort/env/roles/web.env
   fi"

# E) Roll containers (proxy + web). Migrations apply via entrypoint.
bin/kamal deploy --skip-push

# F) Verify
DOCSORT_CA="$(mkcert -CAROOT)/rootCA.pem"
curl --cacert "$DOCSORT_CA" -sS -m 10 -o /dev/null -w "up %{http_code}\n" https://docsort.local/up \
  || curl --cacert "$DOCSORT_CA" -sS -m 10 -o /dev/null -w "up-ip %{http_code}\n" https://192.168.178.158/up
```

**Success criteria**

- Exit code 0 from `bin/kamal deploy --skip-push`  
- `/up` returns **200**  
- Running web container name contains the new git SHA (`docker ps` on Pi)

**Timeouts:** build + transfer often **2–6 minutes**. Use a long command timeout; do not kill mid-`docker save|load`.

---

## 3. First-time / bootstrap (rare)

Only if Kamal has never been set up on the host:

1. Fill `config/deploy.yml` (already set for this Pi).  
2. `export DOCSORT_ADMIN_PASSWORD='…'` (strong; ≤72 bytes for bcrypt).  
3. `bin/kamal-doctor`  
4. `bin/kamal-setup` **or** manual: install Docker on Pi, `bin/kamal setup`, boot ollama accessory.  
5. Pull model: `bin/kamal accessory exec ollama -- "ollama pull llama3.2:latest"`  
6. Then use §2 for every later release.

mDNS name `docsort.local` is published by systemd unit **`docsort-mdns.service`** on the Pi (`avahi-publish -a -R docsort.local 192.168.178.158`). Re-check if hostname resolution breaks after OS changes.

---

## 4. Secrets rules (do not invent)

| Secret | Source |
|--------|--------|
| `RAILS_MASTER_KEY` | `config/master.key` via `.kamal/secrets` (never commit key contents into chat logs if avoidable) |
| `DOCSORT_ADMIN_PASSWORD` | Must be **exported** before Kamal; seeds admin + WebDAV password |
| `WEBDAV_PASSWORD` | Legacy alias → mapped to `DOCSORT_ADMIN_PASSWORD` in `.kamal/secrets` |
| `DOCSORT_TLS_CERTIFICATE` / `DOCSORT_TLS_PRIVATE_KEY` | Loaded from gitignored `config/tls/` files generated by `bin/setup-lan-tls` |

On the Pi, Kamal writes `.kamal/apps/docsort/env/roles/web.env`. When re-writing that file in the SSH step, **always re-read `RAILS_MASTER_KEY` from the existing file** so you do not wipe the master key.

Admin password file sometimes used on the operator Mac: `/tmp/docsort-admin-password.txt` (not in git).

---

## 5. What deploy does / does not do

**Does**

- Build new Docker image tagged with **git SHA**  
- Start new web container, proxy cutover, stop old  
- Run DB migrate/prepare inside the new app  
- Keep `docsort_storage` volume (documents/users survive)

**Does not**

- Auto-commit your working tree — **commit first** if code must ship  
- Pull Ollama models unless you run accessory pull  
- Fix a dead Pi / Wi‑Fi  
- Deploy uncommitted files

Schema migrations: included in the image; applied at boot. If migrate fails, container may fail healthcheck — read `bin/kamal app logs` / `docker logs` on Pi.

---

## 6. Failure playbook

| Symptom | Action |
|---------|--------|
| SSH timeout / host down | Abort; tell user Pi offline |
| `bin/kamal build` fails | Docker not running / arch / Dockerfile apt |
| `docker load` hangs | Network; increase ServerAlive; retry when Pi back |
| Deploy health fail `/up` | Check admin password length; `RAILS_MASTER_KEY`; `docker logs` on new web container |
| App up but old UI | Hard-refresh / favicon cache; confirm container name has new SHA |
| `docsort.local` NXDOMAIN | Ping IP; restart `docsort-mdns` / avahi on Pi |
| Kamal lock stuck | `bin/kamal lock release` (only if no other deploy running) |

Quick Pi checks:

```bash
ssh -p 2222 -i ~/.ssh/id_ed25519 pi@192.168.178.158 \
  'docker ps --filter label=service=docsort --format "{{.Names}} {{.Status}}"'
```

---

## 7. Anti-patterns (agents)

1. **Do not** run `bin/kamal deploy` **without** `--skip-push` after a manual `docker load` unless the Pi can actually pull `localhost:5555` from the Mac (it usually cannot).  
2. **Do not** `export DOCSORT_ADMIN_PASSWORD=changeme` on a real re-seed production env unless the user wants that. Prefer the password already on the Pi’s `web.env`.  
3. **Do not** force-push or rewrite published history to “fix” tags.  
4. **Do not** deploy mid-refactor without the user asking.  
5. **Do not** drop the storage volume.  
6. Prefer **one** deploy after a batch of commits, not one deploy per typo, unless the user wants each change live.

---

## 8. Minimal checklist (paste into agent todos)

- [ ] User asked to deploy  
- [ ] Changes committed (`git rev-parse HEAD` is the release)  
- [ ] `DOCSORT_ADMIN_PASSWORD` or existing Pi env strategy set  
- [ ] SSH to Pi succeeds  
- [ ] `bin/kamal build push`  
- [ ] `docker save | ssh docker load`  
- [ ] Tag + preserve `web.env` keys  
- [ ] `bin/kamal deploy --skip-push`  
- [ ] `/up` → 200  
- [ ] Report version SHA + URL to user  

---

## 9. Related paths

| Path | Role |
|------|------|
| `config/deploy.yml` | Hosts, proxy hosts, env, builder arch, SSH |
| `.kamal/secrets` | How secrets are injected |
| `Dockerfile` | Runtime image (tesseract, poppler, Ruby) |
| `bin/docker-entrypoint` | `db:prepare`, seed |
| `bin/kamal-deploy` | Thin wrapper; **not** the save/load path |
| `DEPLOY.md` | Generic Kamal / registry options |

---

*End of agent deploy guide.*
