# DocSort — LLM wiki (agent context)

**Last reviewed:** 2026-08-06  
**Audience:** coding agents and humans jumping into this repo.  
**Style:** dense, factual, navigational — not marketing.  

| Prefer | For |
|--------|-----|
| **This file** | Architecture, invariants, file map |
| `DEPLOY-AGENTS.md` | How to deploy to the Pi (canonical recipe) |
| `MEMORY.md` | Session handoff / chronological notes (may lag) |
| `README.md` | Human quickstart |
| `DEPLOY.md` | Kamal background / first-time bootstrap |

| | |
|--|--|
| **What** | Local-first multi-user document archive |
| **Where** | Workspace path (macOS dev) · Raspberry Pi LAN prod |
| **Stack** | Rails 8.1 · Ruby 4.0 · SQLite · Active Storage · Solid Queue · Tailwind · Stimulus · Turbo · Ollama · Kamal · Docker |
| **Prod URL** | **HTTPS** `https://docsort.local` or `https://192.168.178.158` |
| **Health** | `GET /up` → 200 (HTTP allowed for probe; app assumes TLS) |

---

## 1. One-sentence purpose

Upload documents (web or WebDAV) → extract text (PDF text layer + OCR fallback) → classify with rules / local LLM / keywords → detect issuer → copy into a sorted folder tree **per user**, all private on your hardware.

---

## 2. Mental model

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────────────┐
│ Web upload  │────▶│ DocumentIngestor │────▶│ Document (UUID PK)  │
│ WebDAV PUT  │     │ + ActiveStorage  │     │ status=pending      │
│ (size cap)  │     └──────────────────┘     └──────────┬──────────┘
└─────────────┘                                          │
                                              ClassifyDocumentJob
                                                         │
              ┌──────────────────────────────┼──────────────────────────────┐
              ▼                              ▼                              ▼
       TextExtractor                  DocumentClassifier              DocumentOrganizer
       all pages text                 1 rules 2 ollama 3 keywords     SafeStoragePath
       + OCR if sparse                + IssuerDetector/Resolver       sorted/<user>/…
                                                                      SortedCopy helpers
```

**Invariants agents must not break**

1. Documents are **scoped by `user_id`**. Controllers use `current_user.documents`. Never leak across users.
2. Document **primary keys are UUID strings** (v7 on create), not integers. Active Storage `record_id` is string for Document attachments.
3. Classification is **async** (`ClassifyDocumentJob`). Reclassify must not no-op on `processing`.
4. Sorted tree is a **copy** of the file; original stays in Active Storage. Cleanup uses `SortedCopy`.
5. **All filesystem joins under storage** go through `SafeStoragePath` (no `..` / absolute escape).
6. WebDAV auth = **same username/password as web login** (`User` + `has_secure_password`).
7. Prod jobs run **Solid Queue inside Puma** (`SOLID_QUEUE_IN_PUMA=true`). Dev jobs are **async**.
8. **Production auth and WebDAV are HTTPS-oriented.** Do not leave `DOCSORT_ALLOW_INSECURE_*` true on the Pi.
9. Upload size is capped (`DOCSORT_MAX_UPLOAD_BYTES`, default **100 MB**) for web and WebDAV.
10. **No social follow graph** — was added and **reverted**. Do not reintroduce unless asked.

---

## 3. Domain objects

| Model | PK | Role |
|-------|-----|------|
| `User` | int | Session + WebDAV identity; `admin` flag; owns documents |
| `Document` | **string UUID** | One uploaded file + classification metadata |
| `Category` | int | Shared taxonomy → `directory_path` under sorted root |
| `ClassificationRule` | int | Regex/priority → category (offline-capable) |

**No `Follow` model** in schema.

**Document fields (important)**  
`original_filename`, `status`, `source`, `title`, `summary`, `extracted_text`, `tags`, `issuer`, `issuer_confidence`, `confidence`, `classifier_used`, `relative_path`, `metadata` (JSON), `category_id`, `user_id`, `error_message`, `classified_at`, `content_type`, `byte_size`.

**Statuses:** `pending` | `processing` | `classified` | `failed` | `unsorted`  
**Sources:** `web` | `webdav` | `api`

**User storage roots**

```
storage/inbox/<username>/          # WebDAV write target (per user)
storage/sorted/<username>/<category_path>/[<issuer-slug>/]<file>
storage/<hash>/…                   # Active Storage blobs
```

Categories are **global** (shared names/paths); sorted copies are **namespaced by username**.

**Helpers**

| Class | Role |
|-------|------|
| `SafeStoragePath` | Resolve/contain paths under a root; reject traversal |
| `SortedCopy` | Locate/delete sorted file for a document; prune empty dirs |

---

## 4. Classification pipeline (detail)

### 4.1 Text extraction — `TextExtractor`

1. PDF: **embedded text all pages** (`pdf-reader`).
2. Per page: if sparse (< ~40 alnum chars) **or** `DOCSORT_OCR_MODE=all` → **Tesseract** via `pdftoppm` (Docker: `tesseract` + `poppler-utils` + eng/deu).
3. Default mode: **`auto`** (text layer first, OCR fallback only).
4. Images: OCR when tesseract available.
5. Output labeled `--- Page N ---`; store up to `DOCSORT_EXTRACT_MAX_CHARS` (~100k).
6. Classifier prompt window: `DOCSORT_CLASSIFY_MAX_CHARS` (~12k, head+tail sample).

### 4.2 Classify — `DocumentClassifier`

Order:

1. **ClassificationRule** (active, by priority) on filename+text  
2. Else **Ollama** JSON chat if `/api/tags` reachable  
3. Else **keyword** scores on category keywords  

Plus:

- **IssuerDetector** (heuristics)  
- Model may return `issuer` / `issuer_confidence`  
- **IssuerCategoryResolver** may promote weak/unsorted → `issuers/<slug>/` category  

Ollama client caps `num_predict` (short JSON) — avoid hanging Pi models.

### 4.3 Job — `ClassifyDocumentJob`

Always (re)runs; sets `processing` → extract → classify → organize → `classified` / `unsorted` / `failed`.

### 4.4 Organize — `DocumentOrganizer`

Uses `SafeStoragePath` under `user.sorted_root` + category path; nests under issuer slug when useful; unique filename if collision; sets `relative_path`.

---

## 5. HTTP surface

| Route | Auth | Notes |
|-------|------|--------|
| `/login` session | public | Session cookie |
| `/` dashboard | login | Stats, Ollama status, WebDAV help |
| `/documents` | login | Scoped to current user |
| `/documents/autocomplete` | login | Typeahead Turbo |
| `/documents/:uuid` | login | Show; **full** `extracted_text` (scrollable; do not re-truncate hard) |
| `/categories` | login | Shared categories |
| `/users` | **admin** | CRUD users (avatar cards UI) |
| `/webdav`, `/webdav/*` | Basic auth User | Explicit verbs in routes + Puma |
| `/up` | public | Health (deploy probe) |

**Document IDs in URLs are UUIDs**, e.g. `/documents/019f8b2e-…`.

Production users should hit **HTTPS**. Dev may use plain HTTP with insecure auth allowed by default.

---

## 6. Key files (edit map)

| Concern | Path |
|---------|------|
| Routes | `config/routes.rb` |
| App config / env knobs | `config/application.rb` (`config.x.*`) |
| Deploy config | `config/deploy.yml` |
| Deploy for agents | **`DEPLOY-AGENTS.md`** |
| Deploy human guide | `DEPLOY.md` |
| Dockerfile | `Dockerfile` (OCR packages) |
| Auth session | `app/controllers/sessions_controller.rb`, `application_controller.rb` |
| WebDAV | `app/controllers/webdav_controller.rb`, `config/puma.rb` |
| Documents | `app/controllers/documents_controller.rb` |
| Users admin | `app/controllers/users_controller.rb` |
| Models | `app/models/{user,document,category,classification_rule}.rb` |
| Path safety | `app/services/safe_storage_path.rb`, `sorted_copy.rb` |
| Pipeline services | `document_{ingestor,classifier,organizer}.rb`, `text_extractor.rb`, `ollama_client.rb`, `issuer_*` |
| Job | `app/jobs/classify_document_job.rb` |
| UI tokens / layout | `app/assets/stylesheets/application.css`, `app/views/layouts/application.html.erb` |
| Flash auto-dismiss | `app/javascript/controllers/flash_controller.js` (5s) |
| Typeahead | `app/javascript/controllers/typeahead_controller.js` |
| Logo / favicon | `public/icon.svg`, `favicon.svg`, `icon-app.svg`, `logo.svg` + PNG/ICO |
| Seeds | `db/seeds.rb` |
| Schema | `db/schema.rb` (documents `id: :string`) |

---

## 7. Config / environment

| Variable | Meaning |
|----------|---------|
| `OLLAMA_HOST` | Dev `http://localhost:11434`; prod `http://docsort-ollama:11434` |
| `OLLAMA_MODEL` | **Prod: `qwen2.5:3b`** (deploy.yml). Dev default still `llama3.2` unless set |
| `OLLAMA_TIMEOUT` | Seconds; Pi **600** |
| `DOCSORT_ADMIN_USERNAME` / `DOCSORT_ADMIN_PASSWORD` | Bootstrap admin (bcrypt ≤72 bytes) |
| `DOCSORT_SORTED_ROOT` / `DOCSORT_INBOX_ROOT` | Absolute paths in container |
| `DOCSORT_AUTO_SEED` | Seed categories/admin if empty |
| `DOCSORT_AUTO_ISSUER_CATEGORIES` | Auto-create issuer categories |
| `DOCSORT_OCR_MODE` | `auto` \| `all` \| `off` |
| `DOCSORT_OCR_LANGS` | e.g. `eng+deu` |
| `DOCSORT_CLASSIFY_MAX_CHARS` | Prompt cap for Ollama |
| `DOCSORT_MAX_UPLOAD_BYTES` | Per-file cap; default `104857600` (100 MB) |
| `DOCSORT_ALLOW_INSECURE_AUTH` | Prod **false**; dev default true |
| `DOCSORT_ALLOW_INSECURE_WEBDAV` | Prod **false**; dev default true |
| `ASSUME_SSL` / `FORCE_SSL` | Prod **true** (behind TLS kamal-proxy) |

### Production TLS (LAN)

- Kamal proxy: custom cert via secrets `DOCSORT_TLS_CERTIFICATE` / `DOCSORT_TLS_PRIVATE_KEY` (gitignored mkcert output).  
- Helper: `bin/setup-lan-tls` (if present) generates cert for hosts.  
- `proxy.ssl_redirect: true` in `config/deploy.yml`.  
- Secrets load: `.kamal/secrets` → `RAILS_MASTER_KEY`, `DOCSORT_ADMIN_PASSWORD`, TLS files.

---

## 8. UI / brand (current)

**buzz.xyz-inspired** (not old copper “Archive Ink”):

- Chartreuse `#d7d72e`, ink `#231e1e`, paper `#eeeeeb` / white cards  
- Logo: **dimensional / integrated header logo** — black document mark, chartreuse cutouts, app tile; assets under `public/`  
- Header: nav-pills, chartreuse Upload, user chip as nav-pills  
- Categories: card grid · Users: avatar cards · flashes auto-hide **5s**  
- Theme-color meta: `#d7d72e`

---

## 9. Dev loop (this machine)

```bash
export PATH="/opt/homebrew/opt/ruby/bin:/opt/homebrew/lib/ruby/gems/4.0.0/bin:$PATH"
cd /Users/tr/Projects/docsort   # or workspace root
# gems: vendor/bundle
bin/rails db:prepare
bin/rails db:seed
bin/rails server -p 3000 -b 127.0.0.1
# or: bin/dev  # rails + tailwind watch
```

| | |
|--|--|
| UI | http://127.0.0.1:3000 |
| Local admin (typical seed) | `admin` / `changeme` if env unset |
| Ollama | http://127.0.0.1:11434 |
| Tests | `bin/rails test` |

Ruby must be Homebrew 4.x, not system `/usr/bin/ruby`.

---

## 10. Production (Raspberry Pi)

| | |
|--|--|
| Host | `192.168.178.158` |
| SSH | user `pi`, port **2222**, key `~/.ssh/id_ed25519` |
| App | Kamal web + `kamal-proxy` (TLS) |
| Names | mDNS **`docsort.local`** (`docsort-mdns.service` + avahi-publish) |
| Proxy hosts | IP, `docsort.local`, bare `docsort` |
| Volumes | `docsort_storage` → `/rails/storage`; `ollama_data` |
| Accessory | `docsort-ollama` |
| Model | **`qwen2.5:3b`** |
| Image arch | **arm64** |
| Registry pattern | Mac `localhost:5555` → **`docker save \| ssh docker load`** → **`bin/kamal deploy --skip-push`** |

**Full agent deploy runbook:** [`DEPLOY-AGENTS.md`](./DEPLOY-AGENTS.md)

Rules of thumb:

- Deploy **only when the user asks**  
- Probe SSH first; abort if Pi offline  
- **Commit first** (image tag = `git rev-parse HEAD`)  
- Never wipe `RAILS_MASTER_KEY` when rewriting Pi `web.env`  
- Prefer `https://docsort.local` after TLS is live  

Dockerfile ships **tesseract** + **poppler-utils** + eng/deu.

---

## 11. Seeded categories

| Name | `directory_path` |
|------|------------------|
| Invoices | finance/invoices |
| Receipts | finance/receipts |
| Contracts | legal/contracts |
| Resumes | hr/resumes |
| Reports | work/reports |
| Technical | work/technical |
| Correspondence | personal/correspondence |
| Unsorted | unsorted |

Plus runtime `issuers/<brand-slug>/` when auto-created.

---

## 12. Gotchas (read before changing)

1. **Puma + WebDAV:** non-standard verbs in `config/puma.rb` and routes — not only `via: :all`.  
2. **UUID documents:** fixtures need string ids; AS `record_id` is string.  
3. **Classifier hang:** keep Ollama `num_predict` capped; job must not early-return on `processing`.  
4. **Admin password:** bcrypt 72-byte limit.  
5. **Docker build:** never copy host `vendor/bundle` into the image.  
6. **Kamal tags = git HEAD** — uncommitted code does not ship.  
7. **Pi offline:** SSH timeouts; build may succeed while transfer fails.  
8. **Favicons cache hard** after logo changes.  
9. **Extracted text UI:** full multi-page text; do not reintroduce hard 6k truncate on show.  
10. **No follow/unfollow** (reverted).  
11. Agent-spawned `rails server` may hit max runtime.  
12. WebDAV re-PUT → **new** Document (no dedupe).  
13. **Path safety:** always `SafeStoragePath`, never raw `File.join` into user-controlled paths.  
14. **TLS secrets** are gitignored; deploy needs cert/key present for Kamal ssl config.  
15. Production **FORCE_SSL** — local HTTP testing against prod host will redirect.

---

## 13. How agents should work here

**Do**

- Scope document queries by `current_user`  
- Match chartreuse/ink design tokens for UI work  
- Run `bin/rails test` for classifier/extractor/storage safety changes  
- After schema changes, migrate and plan Pi deploy  
- Keep services pure; use `SafeStoragePath` / `SortedCopy`  
- Follow **`DEPLOY-AGENTS.md`** for any production ship  

**Don’t**

- Assume integer document ids  
- Call cloud LLMs — **Ollama only**  
- Break multi-user isolation  
- Rewrite the design system without a product ask  
- Commit secrets, TLS private keys, or `master.key`  
- Invent a plain `kamal deploy` that pulls from the Mac registry on the Pi  

**Deploy policy:** only when asked; confirm host reachable; report SHA + URL + `/up` status.

---

## 14. Related files

| File | Role |
|------|------|
| `LLM-WIKI.md` | **This** — stable agent orientation |
| `DEPLOY-AGENTS.md` | **How agents deploy** to the Pi |
| `AGENTS.md` | Entry pointer |
| `MEMORY.md` | Session handoff (may lag) |
| `README.md` | Human quickstart |
| `DEPLOY.md` | Kamal walkthrough / first-time |
| `config/deploy.yml` | Live prod topology (TLS, qwen, OCR, upload caps) |

When MEMORY conflicts with this wiki on **architecture facts**, trust **code** first, then this wiki, then MEMORY.

---

*End of LLM wiki.*
