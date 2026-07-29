# DocSort — LLM wiki (agent context)

**Audience:** coding agents and humans jumping into this repo.  
**Style:** dense, factual, navigational — not marketing.  
**Prefer this file** for architecture/invariants; use `MEMORY.md` for session handoff/history, `README.md` for quickstart, `DEPLOY.md` for Kamal details.

| | |
|--|--|
| **What** | Local-first multi-user document archive |
| **Where** | `/Users/tr/Projects/docsort` (macOS dev) · Pi LAN prod |
| **Stack** | Rails 8.1 · Ruby 4.0 · SQLite · Active Storage · Solid Queue · Tailwind · Stimulus · Turbo · Ollama · Kamal · Docker |
| **Prod URL** | `http://docsort.local` or `http://192.168.178.158` |

---

## 1. One-sentence purpose

Upload documents (web or WebDAV) → extract text (PDF layer + OCR fallback) → classify with rules / local LLM / keywords → detect issuer → copy into a sorted folder tree **per user**, all private on your hardware.

---

## 2. Mental model

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────────────┐
│ Web upload  │────▶│ DocumentIngestor │────▶│ Document (UUID PK)  │
│ WebDAV PUT  │     │ + ActiveStorage  │     │ status=pending      │
└─────────────┘     └──────────────────┘     └──────────┬──────────┘
                                                       │
                                            ClassifyDocumentJob
                                                       │
                        ┌──────────────────────────────┼──────────────────────────────┐
                        ▼                              ▼                              ▼
                 TextExtractor                  DocumentClassifier              DocumentOrganizer
                 all pages text                 1 rules 2 ollama 3 keywords     storage/sorted/
                 + OCR if sparse                + IssuerDetector/Resolver       <user>/<cat>/[issuer]/file
```

**Invariants agents must not break**

1. Documents are **scoped by `user_id`**. Controllers use `current_user.documents`. Never leak across users.
2. Document **primary keys are UUID strings** (v7 on create), not integers. Active Storage `record_id` is string for Document.
3. Classification is **async** (`ClassifyDocumentJob`). Reclassify must not no-op on `processing`.
4. Sorted tree is a **copy** of the file; original stays in Active Storage.
5. WebDAV auth = **same username/password as web login** (`User` + `has_secure_password`).
6. Prod jobs run **Solid Queue inside Puma** (`SOLID_QUEUE_IN_PUMA=true`). Dev jobs are **async**.

---

## 3. Domain objects

| Model | PK | Role |
|-------|-----|------|
| `User` | int | Session + WebDAV identity; `admin` flag; owns documents |
| `Document` | **string UUID** | One uploaded file + classification metadata |
| `Category` | int | Shared taxonomy → `directory_path` under sorted root |
| `ClassificationRule` | int | Regex/priority → category (offline-capable) |

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

---

## 4. Classification pipeline (detail)

### 4.1 Text extraction — `TextExtractor`

1. PDF: **embedded text all pages** (`pdf-reader`).
2. Per page: if sparse (< ~40 alnum chars) **or** `DOCSORT_OCR_MODE=all` → **Tesseract** via `pdftoppm` (needs `tesseract` + `poppler-utils` in Docker).
3. Default mode: **`auto`** (text layer first, OCR fallback).
4. Images: OCR when available.
5. Output labeled `--- Page N ---`; stored up to `DOCSORT_EXTRACT_MAX_CHARS` (~100k).
6. Classifier prompt window: `DOCSORT_CLASSIFY_MAX_CHARS` (~12k, head+tail).

### 4.2 Classify — `DocumentClassifier`

Order:

1. **ClassificationRule** (active, by priority) on filename+text  
2. Else **Ollama** JSON chat if `/api/tags` reachable  
3. Else **keyword** scores on category keywords  

Plus:

- **IssuerDetector** (heuristics)  
- Model may return `issuer` / `issuer_confidence`  
- **IssuerCategoryResolver** may promote weak/unsorted → `issuers/<slug>/` category  

### 4.3 Job — `ClassifyDocumentJob`

Always (re)runs; sets `processing` → extract → classify → organize → `classified` / `unsorted` / `failed`.

### 4.4 Organize — `DocumentOrganizer`

Copies blob into `user.sorted_root` + category path; nests under issuer slug when useful; unique filename if collision; sets `relative_path`.

---

## 5. HTTP surface

| Route | Auth | Notes |
|-------|------|--------|
| `/login` session | public | Session cookie |
| `/` dashboard | login | Stats, Ollama status, WebDAV help |
| `/documents` | login | Scoped to current user |
| `/documents/autocomplete` | login | Typeahead Turbo |
| `/documents/:uuid` | login | Show; full `extracted_text` (no 6k truncate) |
| `/categories` | login | Shared categories |
| `/users` | **admin** | CRUD users |
| `/webdav`, `/webdav/*` | Basic auth User | Explicit verbs in routes + Puma |
| `/up` | public | Health |

**Document IDs in URLs are UUIDs**, e.g. `/documents/019f8b2e-…`.

---

## 6. Key files (edit map)

| Concern | Path |
|---------|------|
| Routes | `config/routes.rb` |
| App config / env knobs | `config/application.rb` (`config.x.*`) |
| Deploy | `config/deploy.yml`, `DEPLOY.md`, `Dockerfile`, `bin/kamal-*` |
| Auth session | `app/controllers/sessions_controller.rb`, `application_controller.rb` |
| WebDAV | `app/controllers/webdav_controller.rb`, `config/puma.rb` |
| Documents API | `app/controllers/documents_controller.rb` |
| Users admin | `app/controllers/users_controller.rb` |
| Models | `app/models/{user,document,category,classification_rule}.rb` |
| Services | `app/services/*.rb` (see §4) |
| Job | `app/jobs/classify_document_job.rb` |
| UI tokens / layout | `app/assets/stylesheets/application.css`, `app/views/layouts/application.html.erb` |
| Flash auto-dismiss | `app/javascript/controllers/flash_controller.js` (5s) |
| Typeahead | `app/javascript/controllers/typeahead_controller.js` |
| Seeds | `db/seeds.rb` |
| Schema | `db/schema.rb` |

**Do not** invent a follow/social graph — that was added and **reverted**.

---

## 7. Config / environment

| Variable | Meaning |
|----------|---------|
| `OLLAMA_HOST` | Default dev `http://localhost:11434`; prod `http://docsort-ollama:11434` |
| `OLLAMA_MODEL` | e.g. `llama3.2:latest` (Pi) |
| `OLLAMA_TIMEOUT` | Seconds; Pi often 600 |
| `DOCSORT_ADMIN_USERNAME` / `DOCSORT_ADMIN_PASSWORD` | Bootstrap admin (bcrypt ≤72 bytes) |
| `DOCSORT_SORTED_ROOT` / `DOCSORT_INBOX_ROOT` | Absolute paths in container |
| `DOCSORT_AUTO_SEED` | Seed categories/admin if empty |
| `DOCSORT_AUTO_ISSUER_CATEGORIES` | Auto-create issuer categories |
| `DOCSORT_OCR_MODE` | `auto` \| `all` \| `off` |
| `DOCSORT_OCR_LANGS` | e.g. `eng+deu` |
| `DOCSORT_CLASSIFY_MAX_CHARS` | Prompt cap for Ollama |
| `ASSUME_SSL` / `FORCE_SSL` | false on plain LAN HTTP |

Secrets for Kamal: `.kamal/secrets` → `RAILS_MASTER_KEY`, `DOCSORT_ADMIN_PASSWORD`.

---

## 8. UI / brand (current)

Not the old “Archive Ink” copper theme. **buzz.xyz-inspired:**

- Chartreuse `#d7d72e`, ink `#231e1e`, paper `#eeeeeb` / white cards  
- Logo: **black document mark + chartreuse cutout lines** on chartreuse app tile  
- Assets: `public/icon.svg`, `favicon.svg`, `icon-app.svg`, `logo.svg` + PNG/ICO  
- Header: nav-pills, chartreuse Upload, user menu as nav-pills chip  
- Categories: card grid; Users: avatar cards; flashes auto-hide 5s  

Theme color meta: `#d7d72e`.

---

## 9. Dev loop (this machine)

```bash
export PATH="/opt/homebrew/opt/ruby/bin:/opt/homebrew/lib/ruby/gems/4.0.0/bin:$PATH"
cd /Users/tr/Projects/docsort
# gems already vendor/bundle
bin/rails db:prepare
bin/rails db:seed
bin/rails server -p 3000 -b 127.0.0.1
# or: bin/dev  # rails + tailwind
```

| | |
|--|--|
| UI | http://127.0.0.1:3000 |
| Local admin (typical seed) | `admin` / `changeme` (if env not set) |
| Ollama | http://127.0.0.1:11434 |
| Tests | `bin/rails test` |

Ruby must be Homebrew 4.x, not system `/usr/bin/ruby`.

---

## 10. Production (Raspberry Pi)

| | |
|--|--|
| Host | `192.168.178.158` SSH port **2222** user `pi` |
| App | Kamal web container + `kamal-proxy` |
| Name | mDNS **`docsort.local`** (`docsort-mdns.service` + avahi-publish) |
| Proxy hosts | IP, `docsort.local`, bare `docsort` (bare needs router/hosts) |
| Volumes | `docsort_storage` → `/rails/storage`; `ollama_data` for models |
| Accessory | `docsort-ollama` on Docker network |
| Image arch | **arm64** |
| Registry pattern | Build → local `localhost:5555` → `docker save \| ssh docker load` → `bin/kamal deploy --skip-push` |

Typical deploy from Mac (when Pi online):

```bash
export DOCSORT_ADMIN_PASSWORD="$(cat /tmp/docsort-admin-password.txt)"  # or set explicitly
bin/kamal build push
TAG=$(git rev-parse HEAD)
docker pull "localhost:5555/docsort:${TAG}"
docker save "localhost:5555/docsort:${TAG}" | ssh -p 2222 -i ~/.ssh/id_ed25519 pi@192.168.178.158 "docker load"
# tag latest + keep RAILS_MASTER_KEY on Pi web.env
bin/kamal deploy --skip-push
```

Admin password on Pi is **not** committed; historically stored in deploy env / `/tmp/docsort-admin-password.txt` on the operator machine.

Dockerfile includes **tesseract** + **poppler-utils** + eng/deu lang packs for OCR.

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

1. **Puma + WebDAV:** non-standard verbs listed in `config/puma.rb` and routes — do not collapse to `via: :all` only.  
2. **UUID documents:** fixtures/tests need string ids; AS attachments remap on migration.  
3. **Classifier hang:** Ollama `num_predict` capped; job must not early-return on `processing`.  
4. **Admin password:** bcrypt 72-byte limit; Kamal secrets nesting bugs once caused deploy health fail.  
5. **Docker build:** never copy host `vendor/bundle` into image.  
6. **Kamal needs git commit** for image tags = `git rev-parse HEAD`.  
7. **Pi offline:** SSH timeouts common; build may succeed while transfer fails.  
8. **Favicons cache hard** in browsers after logo changes.  
9. **Show page** used to truncate extract at 6k — fixed; keep full multi-page text.  
10. **No follow/unfollow** feature (reverted); don’t reintroduce unless asked.  
11. Agent-spawned `rails server` may hit max runtime and die.  
12. WebDAV re-PUT creates a **new** Document each time (no dedupe).

---

## 13. How agents should work here

**Do**

- Scope all document queries by `current_user`  
- Prefer small, targeted edits matching existing CSS tokens (chartreuse/ink)  
- Run `bin/rails test` for classifier/extractor changes  
- After schema changes, migrate **and** plan Pi deploy  
- Keep services pure (no controller logic in jobs beyond orchestration)

**Don’t**

- Assume integer document ids  
- Call external cloud LLMs — Ollama only  
- Break multi-user isolation for “convenience”  
- Rewrite the design system without a product ask  
- Store secrets in git  

**Deploy policy:** only deploy to Pi when the user asks; confirm host is reachable.

---

## 14. Related files

| File | Role |
|------|------|
| `LLM-WIKI.md` | **This** — stable agent orientation |
| `MEMORY.md` | Session handoff / chronological notes (may lag) |
| `README.md` | Human quickstart |
| `DEPLOY.md` | Kamal walkthrough |
| `config/deploy.yml` | Live prod topology |

When MEMORY conflicts with this wiki on **architecture facts**, trust **code** first, then this wiki, then MEMORY.

---

*End of LLM wiki.*
