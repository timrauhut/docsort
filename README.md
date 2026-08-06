# DocSort

Local-first **Ruby on Rails** document management with:

- **WebDAV uploads** (Finder, Cyberduck, scanners, curl)
- **Automatic classification** via a **local LLM** ([Ollama](https://ollama.com))
- **Keyword + regex rules** when the model is offline
- **Auto-generated category directories** under `storage/sorted/`
- Web UI for browsing, searching, reclassifying, and manual moves

## Quick start (macOS)

### 1. Ruby

```bash
# Homebrew Ruby 3.4+/4.x
brew install ruby
export PATH="/opt/homebrew/opt/ruby/bin:/opt/homebrew/lib/ruby/gems/4.0.0/bin:$PATH"
```

### 2. App setup

```bash
cd Projects/docsort
bundle config set --local path 'vendor/bundle'
bundle install
bin/rails db:prepare
bin/rails db:seed
bin/dev   # or: bin/rails server
```

Open [http://localhost:3000](http://localhost:3000).

### 3. Local model (recommended)

```bash
# Install from https://ollama.com then:
ollama pull llama3.2
ollama serve   # usually already running as a service
```

DocSort talks to `http://localhost:11434` by default.  
Override with env vars:

| Variable | Default | Purpose |
|----------|---------|---------|
| `OLLAMA_HOST` | `http://localhost:11434` | Ollama API |
| `OLLAMA_MODEL` | `llama3.2` | Chat model |
| `OLLAMA_TIMEOUT` | `120` | Seconds |
| `WEBDAV_USERNAME` | `docsort` | WebDAV auth |
| `WEBDAV_PASSWORD` | `upload123` | WebDAV auth |
| `DOCSORT_SORTED_ROOT` | `storage/sorted` | Sorted tree |
| `DOCSORT_INBOX_ROOT` | `storage/inbox` | WebDAV store |
| `DOCSORT_MAX_UPLOAD_BYTES` | `104857600` | Per-file upload limit |

Without Ollama, classification still works using **category keywords** and **ClassificationRules**.

## WebDAV

Authenticated web sessions and WebDAV require HTTPS in production. Development
allows loopback HTTP for convenience. Keep `DOCSORT_ALLOW_INSECURE_AUTH` and
`DOCSORT_ALLOW_INSECURE_WEBDAV` disabled in production; they exist only for
emergency recovery on a trusted LAN.

Generate the gitignored LAN certificate before deployment:

```bash
bin/setup-lan-tls
```

Run `mkcert -install` once in an interactive terminal so macOS trusts the local
CA, then install the printed `rootCA.pem` on other phones or computers that
should trust `docsort.local`.

| | |
|--|--|
| URL | `http://localhost:3000/webdav` |
| User | `docsort` |
| Password | `upload123` |

```bash
curl -T ./invoice.pdf -u docsort:upload123 \
  http://localhost:3000/webdav/invoice.pdf
```

**macOS Finder:** Go → Connect to Server (`⌘K`) → `http://localhost:3000/webdav`

Uploaded files are ingested as documents, classified in a background job, and copied into:

```text
storage/sorted/<category directory>/<filename>
```

Example seeded paths:

```text
storage/sorted/finance/invoices/
storage/sorted/finance/receipts/
storage/sorted/legal/contracts/
storage/sorted/hr/resumes/
storage/sorted/work/reports/
storage/sorted/personal/correspondence/
storage/sorted/work/technical/
storage/sorted/unsorted/
```

## How classification works

1. **Text extraction** — PDF: embedded text on **all pages** first; **Tesseract OCR** only as fallback when a page has no usable text layer; plain text / images; filename cues  
2. **Rules** — active `ClassificationRule` regexes (highest priority first)  
3. **Ollama** — JSON classification against the category catalog  
4. **Keywords** — fallback scoring on category keyword lists  
5. **Organize** — ensure directory exists, copy file into sorted tree  

You can always **Reclassify** or **manually assign** a category in the UI.

## Docker (app + Ollama, local)

```bash
docker compose up --build
# in another terminal, pull a model into the ollama service:
docker compose exec ollama ollama pull llama3.2
```

## Production deploy with Kamal (DHH’s tool)

Full guide: **[DEPLOY.md](./DEPLOY.md)**

```bash
# Edit config/deploy.yml (server IP, arch, registry)
export WEBDAV_PASSWORD='your-strong-password'
bin/kamal-doctor
bin/kamal-setup      # first time: Docker + proxy + app + Ollama model
bin/kamal-deploy     # later releases
bin/kamal-ollama list
```

| Script | Role |
|--------|------|
| `bin/kamal-setup` | First bootstrap |
| `bin/kamal-deploy` | Ship new builds |
| `bin/kamal-ollama` | Pull/list/logs for the LLM accessory |
| `bin/kamal-doctor` | Preflight checks |

Rails + Ollama accessory share Kamal’s Docker network (`OLLAMA_HOST=http://docsort-ollama:11434`).

## Project layout

```text
app/
  controllers/     # dashboard, documents, categories, webdav
  jobs/            # ClassifyDocumentJob
  models/          # Document, Category, ClassificationRule
  services/        # extractor, ollama client, classifier, organizer, ingestor
storage/
  inbox/           # WebDAV filesystem root
  sorted/          # auto-sorted category tree
```

## Development notes

- Active Job uses the **async** adapter in development (no separate worker needed).
- Active Storage holds the canonical blob; sorted copies are filesystem mirrors for browsing/tools.
- Seed data: `bin/rails db:seed`
- Puma is configured with WebDAV HTTP methods (`PROPFIND`, `MKCOL`, …) in `config/puma.rb`.
- Prefer `bin/dev` so Tailwind CSS rebuilds while you work.

## License

MIT — use and adapt freely.
