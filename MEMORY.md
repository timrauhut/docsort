# DocSort — project memory

**Last updated:** 2026-07-22  
**Location:** `/Users/tr/Projects/docsort`  
**Stack:** Ruby on Rails 8.1.3 · Ruby 4.0.6 (Homebrew) · SQLite · Active Storage · Solid Queue (in Puma prod / async dev) · Tailwind · Stimulus · Turbo · Ollama (local LLM) · Kamal-ready  

This file is the working handoff for the project. Prefer it over re-exploring the repo.

---

## Purpose

Local-first document management:

- Upload via **web UI** or **WebDAV**
- **Classify** with Ollama (any chat model) + rule/keyword fallbacks
- Detect **issuer / brand** (letterhead, From:, GmbH/AG/Ltd, domains)
- **Auto-create category directories** and sort copies under `storage/sorted/`
- Browse, typeahead search, reclassify, manual assign, create category from issuer

---

## How to run (dev, this machine)

```bash
export PATH="/opt/homebrew/opt/ruby/bin:/opt/homebrew/lib/ruby/gems/4.0.0/bin:$PATH"
cd /Users/tr/Projects/docsort
bundle config set --local path 'vendor/bundle'   # already configured
bundle install
bin/rails db:prepare
bin/rails db:seed
bin/rails server -p 3000 -b 127.0.0.1
# or: bin/dev  (server + tailwind watch)
```

| URL | Notes |
|-----|--------|
| http://127.0.0.1:3000 | Web UI |
| http://127.0.0.1:3000/webdav | WebDAV (user `docsort` / password `upload123` in dev) |
| http://127.0.0.1:11434 | Ollama API |

**Ruby:** Homebrew 4.x required (system `/usr/bin/ruby` is too old). Gems in `vendor/bundle`.

**Restart note:** Background server jobs may hit max runtime and die; restart with the command above.

---

## Architecture

```
Upload (web form | WebDAV PUT)
  → DocumentIngestor
      → Document row + Active Storage blob
  → ClassifyDocumentJob
      → TextExtractor (PDF via pdf-reader, text/*, filename cues)
      → DocumentClassifier
          1) ClassificationRule (regex, priority)
          2) OllamaClient JSON chat (if available)
          3) Category keyword scoring
          + IssuerDetector (heuristics) merged with model issuer
          + IssuerCategoryResolver (match or auto-create issuers/<slug>)
      → DocumentOrganizer
          → storage/sorted/<category_path>[/<issuer-slug>]/filename
```

### Key paths

| Area | Path |
|------|------|
| Models | `app/models/{document,category,classification_rule}.rb` |
| Services | `app/services/{document_classifier,issuer_detector,issuer_category_resolver,ollama_client,text_extractor,document_ingestor,document_organizer}.rb` |
| Job | `app/jobs/classify_document_job.rb` |
| WebDAV | `app/controllers/webdav_controller.rb` |
| Documents | `app/controllers/documents_controller.rb` (+ autocomplete, create_issuer_category) |
| Typeahead | `app/javascript/controllers/typeahead_controller.js` |
| Design system CSS | `app/assets/stylesheets/application.css` |
| Layout | `app/views/layouts/application.html.erb` |
| Seeds | `db/seeds.rb` |
| Config knobs | `config/application.rb` (`config.x.*`) |
| Puma WebDAV methods | `config/puma.rb` |
| Deploy guide | `DEPLOY.md` |
| Kamal | `config/deploy.yml`, `.kamal/secrets`, `.kamal/hooks/*` |
| Scripts | `bin/kamal`, `bin/kamal-setup`, `bin/kamal-deploy`, `bin/kamal-ollama`, `bin/kamal-doctor` |

### Document statuses / sources

- Status: `pending` · `processing` · `classified` · `failed` · `unsorted`
- Source: `web` · `webdav` · `api`
- Extra fields: `issuer`, `issuer_confidence`, `classifier_used`, `relative_path`, `metadata` (JSON)

---

## Where data is stored

| What | Path |
|------|------|
| SQLite (dev) | `storage/development.sqlite3` |
| Active Storage originals | `storage/<xx>/<yy>/…` (hashed) |
| Sorted copies | `storage/sorted/<category>/[issuer/]file` |
| WebDAV inbox | `storage/inbox/` |
| Ollama models | **Outside app** — `~/.ollama` (macOS) or Kamal volume `ollama_data` |

Seeded category dirs:  
`finance/invoices`, `finance/receipts`, `legal/contracts`, `hr/resumes`, `work/reports`, `work/technical`, `personal/correspondence`, `unsorted`  
(+ runtime `issuers/<brand>/` when auto-created)

### Env overrides

| Variable | Default / notes |
|----------|-----------------|
| `OLLAMA_HOST` | `http://localhost:11434` |
| `OLLAMA_MODEL` | `llama3.2` — **any Ollama chat model** (Gemma, etc.) |
| `OLLAMA_TIMEOUT` | `120` (raise on Pi / large models) |
| `WEBDAV_USERNAME` / `WEBDAV_PASSWORD` | `docsort` / `upload123` in dev |
| `DOCSORT_SORTED_ROOT` / `DOCSORT_INBOX_ROOT` | under `storage/` |
| `DOCSORT_AUTO_ISSUER_CATEGORIES` | `true` |
| `DOCSORT_AUTO_SEED` | `true` in Docker entrypoint |
| `ASSUME_SSL` / `FORCE_SSL` | prod behind Kamal TLS proxy |

---

## UI / brand

**“Archive Ink” design:** warm paper `#f3efe6`, deep ink, copper `#c45c26`, Fraunces + DM Sans + IBM Plex Mono.

**Logo assets:**
- `public/icon.svg` — app mark (stacked papers + copper tab)
- `public/logo.svg` — wordmark
- `public/icon.png`, `apple-touch-icon.png`, `favicon-32.png`

**Upload CTAs:** header `.btn-upload` (pulse), page CTAs, floating `.fab-upload` (bottom-right).

**Typeahead:** `/documents/autocomplete`, capture-phase arrow keys, Turbo Frame table updates, pause form submit while navigating.

---

## Issuer / brand detection

1. **IssuerDetector** — From:/Absender, legal suffixes (GmbH, AG, Ltd…), domains, filename tokens  
2. **Ollama** — JSON fields `issuer`, `issuer_confidence`  
3. Stored on document; table column + show page chip  
4. **IssuerCategoryResolver** — match existing category or auto-create `issuer-<slug>` → dir `issuers/<slug>`  
5. **Create category** button: `POST /documents/:id/create_issuer_category`  
6. Organizer nests non-issuer categories under `<issuer-slug>/` when issuer present  

Smoke: Telekom-style letter → issuer `Deutsche Telekom AG`.

---

## Ollama models (app is model-agnostic)

- Client: `POST /api/chat` + `format: json` — no Llama-specific code  
- Switch model: `export OLLAMA_MODEL=gemma2:2b` (or any tag from `ollama list`)  
- **Gemma vs default `llama3.2` (~3B):**  
  - small Gemma (`2b`) → usually **faster, weaker** JSON/issuer quality  
  - larger Gemma (`9b`) → can match/beat 3B, needs more RAM  
  - not a free upgrade; A/B with reclassify  
- Pi 5: prefer `llama3.2:1b` or `gemma2:2b`, `OLLAMA_TIMEOUT=300–600`, arm64 Kamal builds  
- Classification still works offline via rules + keywords  

---

## Features checklist (built)

- [x] Web multi-upload + WebDAV ingest  
- [x] PDF/text extraction + classify job  
- [x] Rules / Ollama / keywords  
- [x] Issuer detection + optional issuer categories  
- [x] Auto directory sort  
- [x] Dashboard (stats, Ollama status, WebDAV help)  
- [x] Documents CRUD-ish, typeahead, filters  
- [x] Categories CRUD  
- [x] Archive Ink UI + logo + obvious upload  
- [x] Kamal full kit (DEPLOY.md, hooks, doctor/setup/deploy/ollama scripts)  
- [x] Docker entrypoint: `db:prepare`, auto-seed if empty categories  
- [x] Tests: `document_classifier_test`, `issuer_detector_test`  

---

## Not built (discussed)

- OCR for image-only / scanned PDFs  
- In-process GGUF in Ruby (not recommended)  
- Email-to-ingest / chat bots  
- Mobile QR helper page  
- Web UI auth (only WebDAV basic auth today)  
- WebDAV dedupe by checksum  

---

## Phone → server (advice given)

1. WebDAV client → `/webdav`  
2. Browser → `/documents/new`  
3. Remote private: **Tailscale + WebDAV**  
4. Scanner apps that export to WebDAV  

---

## Deploy (Kamal)

Full guide: **`DEPLOY.md`**

```bash
# Edit config/deploy.yml: server IP, arch (amd64|arm64), registry, optional SSL
export WEBDAV_PASSWORD='strong-secret'
# Need at least one git commit (Kamal tags with HEAD)
bin/kamal-doctor
bin/kamal-setup      # first time + model pull
bin/kamal-deploy     # later
bin/kamal-ollama pull|list|logs
```

- App volume: `docsort_storage` → `/rails/storage`  
- Ollama accessory: `docsort-ollama`, volume `ollama_data`  
- Network: `OLLAMA_HOST=http://docsort-ollama:11434`  
- Placeholders still in deploy.yml: `192.168.0.1`, `docsort.example.com` until user fills real host  

Also: `docker-compose.yml` for local web+ollama.

---

## Known gotchas

1. Puma 8 needs WebDAV methods in `config/puma.rb`  
2. Routes must list WebDAV verbs explicitly (not only `via: :all`)  
3. Dev: `active_job` **async**; prod: Solid Queue in Puma  
4. Bundle path `vendor/bundle` (Homebrew gem perms)  
5. Typeahead: capture keydown + pause form submit while arrow-navigating  
6. Scanned PDFs without text → poor classify until OCR  
7. WebDAV re-PUT creates new Document each time  
8. Kamal needs git HEAD commit + Docker daemon + real server IP  
9. Dockerfile must not ship host `vendor/bundle` (dockerignored)  
10. Background `rails server` in agent sessions may auto-stop on max runtime  

---

## Useful commands

```bash
export PATH="/opt/homebrew/opt/ruby/bin:/opt/homebrew/lib/ruby/gems/4.0.0/bin:$PATH"
cd /Users/tr/Projects/docsort

bin/rails server -p 3000 -b 127.0.0.1
curl -T ./file.pdf -u docsort:upload123 http://127.0.0.1:3000/webdav/file.pdf

ollama list
ollama pull llama3.2
# export OLLAMA_MODEL=gemma2:2b

bin/rails test test/services/document_classifier_test.rb test/services/issuer_detector_test.rb
bin/kamal-doctor
```

---

## Seed categories

| Name | Path |
|------|------|
| Invoices | finance/invoices |
| Receipts | finance/receipts |
| Contracts | legal/contracts |
| Resumes | hr/resumes |
| Reports | work/reports |
| Correspondence | personal/correspondence |
| Technical | work/technical |
| Unsorted | unsorted |

Sample rules: filename `invoice` / `receipt`.

---

## Open next steps

1. Fill Kamal server IP / registry / SSL; first real deploy  
2. Production `WEBDAV_PASSWORD` (not `upload123`)  
3. Optional web UI auth  
4. OCR for scans  
5. WebDAV dedupe  
6. Mobile QR + upload helper  
7. User A/B test Gemma vs llama3.2 on their corpus  

---

## Related docs

- `LLM-WIKI.md` — **agent-oriented project overview** (prefer for architecture)  
- `AGENTS.md` — pointer for coding agents  
- `README.md` — quick start  
- `DEPLOY.md` — Kamal production  
- `MEMORY.md` — this file (session handoff; may lag)  

*End of memory dump.*
