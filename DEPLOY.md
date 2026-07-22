# Deploying DocSort with Kamal

Kamal (DHH / 37signals) deploys DocSort as Docker containers on your own server:

| Container | Role |
|-----------|------|
| **docsort** (web) | Rails + Thruster + Solid Queue (in Puma) |
| **docsort-ollama** (accessory) | Local LLM for classification |
| **kamal-proxy** | HTTP/HTTPS entrypoint |

Persistent data:

- `docsort_storage` → SQLite, Active Storage, `sorted/`, WebDAV inbox  
- `ollama_data` → downloaded model weights  

---

## Prerequisites

1. A Linux server (VPS or Raspberry Pi 5 64-bit) with SSH access  
2. DNS A/AAAA record if you want HTTPS (optional)  
3. Local machine with **Docker**, **Ruby**, and this repo  
4. `config/master.key` present (Rails credentials)  
5. **At least one git commit** — Kamal tags images with `git rev-parse HEAD`  

```bash
# If the repo has no commits yet:
git add -A && git commit -m "Initial DocSort commit"
```

---

## 1. Configure

### Edit `config/deploy.yml`

Replace every **<<< CHANGE ME >>>**:

| Field | Example |
|-------|---------|
| `servers.web` | `203.0.113.10` |
| `accessories.ollama.host` | same IP |
| `image` | `youruser/docsort` (Docker Hub) or keep `docsort` for local registry |
| `registry` | Docker Hub / `ghcr.io` / `localhost:5555` |
| `builder.arch` | `amd64` (most VPS) or **`arm64`** (Pi 5) |
| `proxy.ssl` / `host` | `true` + `docs.example.com` for Let's Encrypt |
| `OLLAMA_MODEL` | `llama3.2` or `llama3.2:1b` on Pi |

If you enable `proxy.ssl: true`, also set in `env.clear`:

```yaml
ASSUME_SSL: true
FORCE_SSL: true
```

### Secrets

```bash
cp config/deploy.env.example .env.deploy   # optional personal file — do not commit
export WEBDAV_PASSWORD='a-long-random-secret'
```

`.kamal/secrets` already loads `RAILS_MASTER_KEY` from `config/master.key` and requires `WEBDAV_PASSWORD`.

### Registry options

**A. Single server, simple (default)**  
`registry.server: localhost:5555` — Kamal runs a local registry on the host. No Docker Hub account.

**B. Docker Hub**

```yaml
registry:
  # server: docker.io   # default
  username:
    - KAMAL_REGISTRY_USERNAME
  password:
    - KAMAL_REGISTRY_PASSWORD
image: youruser/docsort
```

```bash
export KAMAL_REGISTRY_USERNAME=youruser
export KAMAL_REGISTRY_PASSWORD=dckr_pat_...
```

**C. GHCR**

```yaml
registry:
  server: ghcr.io
  username:
    - KAMAL_REGISTRY_USERNAME
  password:
    - KAMAL_REGISTRY_PASSWORD
image: ghcr.io/youruser/docsort
```

---

## 2. Preflight

```bash
export WEBDAV_PASSWORD='…'
bin/kamal-doctor
```

Fix any `FAIL` lines before continuing.

---

## 3. First deploy

```bash
export WEBDAV_PASSWORD='…'
# optional: export OLLAMA_PULL_MODEL=llama3.2:1b   # Pi-friendly

bin/kamal-setup
```

This runs `kamal setup` (install Docker if needed, start proxy, boot accessories, build, deploy) and pulls the Ollama model.

Manual equivalent:

```bash
bin/kamal setup
bin/kamal accessory boot ollama
bin/kamal-ollama pull
```

---

## 4. Day-to-day deploys

```bash
export WEBDAV_PASSWORD='…'
bin/kamal-deploy
# or: bin/kamal deploy
```

---

## 5. Helper scripts

| Script | Purpose |
|--------|---------|
| `bin/kamal` | Wrapper → `bundle exec kamal` |
| `bin/kamal-doctor` | Local preflight checks |
| `bin/kamal-setup` | First-time bootstrap + model pull |
| `bin/kamal-deploy` | Build & deploy app |
| `bin/kamal-ollama` | boot / pull / list / logs for Ollama |

### Ollama helpers

```bash
bin/kamal-ollama boot
bin/kamal-ollama pull          # llama3.2 (or $OLLAMA_PULL_MODEL)
bin/kamal-ollama pull-small    # llama3.2:1b for Raspberry Pi
bin/kamal-ollama list
bin/kamal-ollama logs
```

### App helpers (Kamal aliases)

```bash
bin/kamal logs
bin/kamal console
bin/kamal shell
bin/kamal seed
bin/kamal app exec 'bin/rails runner "p Document.count"'
```

---

## 6. Hooks (`.kamal/hooks/`)

| Hook | What it does |
|------|----------------|
| `pre-build` | Ensures master.key, WEBDAV_PASSWORD, assets entry exist |
| `pre-deploy` | Logs deploy metadata |
| `post-deploy` | Prints next steps (model pull, etc.) |
| `post-app-boot` | Confirms boot |
| `docker-setup` | Fired when Docker is installed on the host |

Hooks must be executable (`chmod +x .kamal/hooks/*`).

---

## 7. After deploy — verify

```bash
curl -fsS http://SERVER/up
# Web UI
open http://SERVER/
# WebDAV
curl -T ./test.pdf -u docsort:$WEBDAV_PASSWORD http://SERVER/webdav/test.pdf
```

Dashboard should show **Ollama Online** once the model is pulled and the accessory is healthy.

---

## 8. Raspberry Pi 5 notes

```yaml
# config/deploy.yml
builder:
  arch: arm64
env:
  clear:
    OLLAMA_MODEL: llama3.2:1b
    OLLAMA_TIMEOUT: 600
```

```bash
export OLLAMA_PULL_MODEL=llama3.2:1b
bin/kamal-setup
```

Use **8 GB+ RAM** if possible. Prefer SSD/NVMe over SD for model + SQLite.

Building **arm64** images from an Apple Silicon Mac is native; from an Intel Mac you may need a remote builder.

---

## 9. Data & backups

On the server, Docker volumes hold everything important:

```bash
# list volumes
ssh root@SERVER docker volume ls | grep -E 'docsort|ollama'

# backup app storage (SQLite + files)
ssh root@SERVER 'docker run --rm -v docsort_storage:/data -v $(pwd):/backup alpine tar czf /backup/docsort-storage.tgz -C /data .'
```

---

## 10. Troubleshooting

| Symptom | Fix |
|---------|-----|
| `WEBDAV_PASSWORD` error in pre-build | `export WEBDAV_PASSWORD=…` |
| Build fails on `vendor/` | Ensure `vendor/bundle` is dockerignored (it is) |
| App up, Ollama offline | `bin/kamal-ollama boot` then `pull` |
| Slow classification | Smaller model / higher `OLLAMA_TIMEOUT` |
| SSL not issuing | DNS must point to server; `proxy.ssl: true` + open 80/443 |
| 502 from proxy | `bin/kamal app logs` · check `/up` |
| Jobs not running | `SOLID_QUEUE_IN_PUMA: true` must be set (default) |

```bash
bin/kamal app details
bin/kamal accessory details ollama
bin/kamal proxy details
```

---

## Quick checklist

- [ ] `config/deploy.yml` server IP + ollama host  
- [ ] `builder.arch` correct (`amd64` / `arm64`)  
- [ ] Registry configured  
- [ ] `export WEBDAV_PASSWORD=…`  
- [ ] `bin/kamal-doctor` clean  
- [ ] `bin/kamal-setup`  
- [ ] Model listed via `bin/kamal-ollama list`  
- [ ] `curl http://SERVER/up` → 200  
