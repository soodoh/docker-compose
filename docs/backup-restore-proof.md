# Backup and restore proof

## Status

Phase 1 is complete. Local encrypted-backup freshness, external recovery-key use, archive integrity, isolated application-level restore, cleanup, remote-object metadata, retention behavior, and post-restore server baselines are verified.

Observed on 2026-08-01:

- `daily-local-backup` and `weekly-remote-backup` are running `ghcr.io/offen/docker-volume-backup:v2.48.2`.
- Both jobs use GPG public-key encryption. The public recipient fingerprint is `5B14A67EC89DBA1F4C0FEE7CA678E17443DBD7A4`.
- The server's default GPG keyring contains zero secret keys, and Git tracks no private-key candidate.
- The external recovery copy was used successfully on `Paul's MacBook`; the private key and passphrase never entered the server, repository, command arguments, or logs.
- Seven local `.gpg` archives exist under `/mnt/storage/backups`.
- The newest archive is `daily-backup-2026-08-01T06-00-00.tar.gz.gpg`, 46,229,834,775 bytes, with mtime `2026-08-01T06:38:29-07:00`.
- The daily job retains five days under the current `daily-backup-` prefix. Older files using the previous `backup-` prefix still exist and were not removed.
- The weekly job runs Sunday at 06:00 local time and retains 14 days under the current `weekly-backup-` prefix.
- The first scheduled run uploaded `weekly-backup-2026-08-02T06-00-00.tar.gz.gpg` and completed its remote prune step without a logged error.
- The credential-safe inventory helper at [`scripts/inventory-s3-backups.py`](../scripts/inventory-s3-backups.py) independently verified one current encrypted object in `us-west-2`: 46,308,530,007 bytes, last modified `2026-08-02T13:35:54Z`, with multipart ETag metadata.
- `ListObjectVersions` independently reported the same object as the sole current version with no delete marker. Its observed age was approximately 29 hours, within the configured 14-day retention window.
- No manual backup, upload, prune, container lifecycle, volume, or production-path mutation was performed during verification.

## Backup-job inventory commands

These commands inspect only service metadata, configured variable names, mount paths, and ciphertext metadata. They must never print container environment values or use `backup print-config`.

```sh
docker inspect --format 'status={{.State.Status}} image={{.Config.Image}} started={{.State.StartedAt}}' daily-local-backup weekly-remote-backup
find /mnt/storage/backups -maxdepth 1 -type f -name '*.gpg' -printf '%f\t%s\t%T@\t%TY-%Tm-%TdT%TH:%TM:%TS%Tz\n'
gpg --show-keys --with-colons services/data/backup-gpg-public.asc
gpg --batch --with-colons --list-secret-keys
```

The S3 checks used credentials already present inside `weekly-remote-backup`, loaded through `docker inspect` into process memory. The helper emitted only region, object count, filename, size, last-modified time, ETag, version-ID hash, and truncation state. It never emitted the bucket name, access key, secret key, session token, signed request, headers, or response body.

## Selected restore candidate

Use the newest local ciphertext:

```text
/mnt/storage/backups/daily-backup-2026-08-01T06-00-00.tar.gz.gpg
```

The application-level target is Vaultwarden's SQLite database. Production metadata, inspected without reading database content, is:

```text
/data/db.sqlite3 uid=0 gid=0 mode=0644 bytes=1933312
```

The restore verifier at [`scripts/verify-backup-archive.py`](../scripts/verify-backup-archive.py):

1. accepts a GPG-decrypted gzip/tar stream on standard input;
2. validates every archive path and reads the complete stream;
3. restores only `vaultwarden-data/db.sqlite3` and its SQLite sidecars into a new isolated directory;
4. checks archive-recorded UID `0`, GID `0`, and mode `0644`;
5. checks restored byte size; and
6. runs SQLite `PRAGMA integrity_check`, emitting only pass/fail and non-secret metadata.

A synthetic archive test passed and its disposable destination was removed. A second synthetic test proved that the verifier safely normalizes the backup tool's leading `/` archive paths while continuing to reject `..` traversal.

## External-workstation restore result

The Fish runner at [`scripts/run-backup-restore-proof.fish`](../scripts/run-backup-restore-proof.fish) was fetched over the already trusted SSH path and executed locally on `Paul's MacBook`. The GPG passphrase was collected through hidden terminal input and passed to GPG through a temporary FIFO; it was never persisted or placed in process arguments.

The selected 46,229,834,775-byte ciphertext streamed from the server to the workstation. The verification completed in 679 seconds and reported:

```text
archive integrity: pass
archive path safety: pass
archive members: 140125
regular files: 112201
total uncompressed bytes: 50666388771
Vaultwarden db.sqlite3: uid 0, gid 0, mode 0644, 1933312 bytes
Vaultwarden SQLite integrity: pass
restored SQLite sidecars: db.sqlite3-shm, db.sqlite3-wal
```

The isolated destination was created under the workstation's private temporary directory and then removed with an exact-path guard. No decrypted archive or private key was written to the server, and no production path, container, volume, or service was changed.

## Cleanup and post-check

After the verifier result has been recorded, remove only the exact external-workstation restore destination and its evidence file:

```sh
rm -rf -- "$restore_root"
rm -f -- "${restore_root}.evidence.json" ./verify-backup-archive.py
[ ! -e "$restore_root" ]
```

The post-cleanup server checks passed:

```text
local audit: ok=45 changed=0 unreachable=0 failed=0
local site check: ok=35 changed=0 unreachable=0 failed=0
41 running project containers
30 declared volumes
33 project volumes
29 unique bind sources
8 unique device sources
0 missing runtime sources
Gluetun healthy
Seerr healthy
Tailscale health empty
zero CI peers
host apply lock absent
```

## Recovery limitations

- The newly initialized remote destination has only one weekly object, so the configured 14-day prune behavior cannot be observed across a full expiration cycle yet. The successful prune step, current/version metadata, and in-window object prove the active retention path without proving future expiration timing.
- The restore verifier extracts one stateful service subset rather than every archived volume. It validates the complete compressed archive stream and Vaultwarden application readability but does not prove every application can start from the snapshot.
- The drill does not restore over a production bind or Docker volume and does not test database migrations.
- The backup includes state captured through the backup job's stop-during-backup mechanism; no new manual backup was triggered because doing so would read the mounted plaintext `.env` and restart labeled services.
