# DocSort backups

Production backups use two independent encrypted Restic repositories:

- Local: `/var/backups/docsort/restic` on the Pi's current main SSD.
- Off-site: Cloudflare R2 through its S3-compatible endpoint (enabled after credentials are configured).

The backup pre-copies documents while DocSort stays online, pauses the web container for a short final sync and SQLite `.backup`, verifies every database with `PRAGMA integrity_check`, restarts the app, and then sends the staged snapshot to Restic.

## Install on the Pi

```bash
# Set your host once (do not commit real values):
#   export DOCSORT_HOST=192.168.0.1 DOCSORT_SSH_PORT=22 DOCSORT_SSH_USER=pi

scp -P "${DOCSORT_SSH_PORT:-22}" -r ops/backup "${DOCSORT_SSH_USER:-pi}@${DOCSORT_HOST:?set DOCSORT_HOST}:/tmp/docsort-backup"
ssh -p "${DOCSORT_SSH_PORT:-22}" "${DOCSORT_SSH_USER:-pi}@${DOCSORT_HOST}" 'sudo /tmp/docsort-backup/install'
ssh -p "${DOCSORT_SSH_PORT:-22}" "${DOCSORT_SSH_USER:-pi}@${DOCSORT_HOST}" 'sudo systemctl start docsort-backup.service'
```

The installer creates `/etc/docsort-backup-password`. Copy that password to an offline password manager. Losing it makes both repositories unrecoverable. Never commit or print it in logs.

## Enable R2

Create a token restricted to the backup bucket and edit `/etc/docsort-backup.env` on the Pi:

```bash
DOCSORT_R2_REPOSITORY=s3:https://ACCOUNT_ID.r2.cloudflarestorage.com/BUCKET/docsort
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
AWS_DEFAULT_REGION=auto
```

Then run a backup and inspect its status without displaying secrets:

```bash
sudo systemctl start docsort-backup.service
sudo systemctl status docsort-backup.service --no-pager
sudo cat /var/backups/docsort/status.env
```

## Schedule and retention

- Backup: nightly around 03:15, with up to 15 minutes randomized delay.
- Integrity check: Sunday around 05:15, with up to 30 minutes randomized delay.
- Retention per repository: 7 daily, 8 weekly, and 12 monthly snapshots.

The job aborts when the backup filesystem has less than 20% free space or when the DocSort web container cannot be identified.
