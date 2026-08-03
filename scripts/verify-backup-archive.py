#!/usr/bin/env python3
"""Verify a decrypted backup stream and restore a Vaultwarden SQLite subset.

The encrypted archive must be decrypted by an external GPG identity and piped to
stdin. This script never handles the private key or passphrase and emits only
non-secret verification metadata.
"""

from argparse import ArgumentParser
import json
from pathlib import Path, PurePosixPath
import shutil
import sqlite3
import sys
import tarfile


def fail(message: str) -> None:
    print(f"backup_restore_verification=failed reason={message}", file=sys.stderr)
    raise SystemExit(1)


def safe_member_path(name: str) -> PurePosixPath:
    archive_path = PurePosixPath(name)
    parts = archive_path.parts[1:] if archive_path.is_absolute() else archive_path.parts
    if not parts or ".." in parts:
        fail("unsafe_archive_path")
    return PurePosixPath(*parts)


def main() -> None:
    parser = ArgumentParser()
    parser.add_argument("--restore-root", required=True, type=Path)
    parser.add_argument("--expected-db-uid", type=int, default=0)
    parser.add_argument("--expected-db-gid", type=int, default=0)
    parser.add_argument("--expected-db-mode", default="0644")
    args = parser.parse_args()

    restore_root = args.restore_root.expanduser().resolve()
    if restore_root.exists():
        fail("restore_root_already_exists")
    restore_root.mkdir(parents=True, mode=0o700)

    expected_mode = int(args.expected_db_mode, 8)
    target_names = {"db.sqlite3", "db.sqlite3-wal", "db.sqlite3-shm"}
    restored: dict[str, Path] = {}
    db_metadata: dict[str, int] | None = None
    member_count = 0
    regular_file_count = 0
    total_uncompressed_bytes = 0

    try:
        with tarfile.open(fileobj=sys.stdin.buffer, mode="r|gz") as archive:
            for member in archive:
                member_count += 1
                member_path = safe_member_path(member.name)
                if member.isfile():
                    regular_file_count += 1
                    total_uncompressed_bytes += member.size

                if (
                    not member.isfile()
                    or member_path.name not in target_names
                    or "vaultwarden-data" not in member_path.parts
                ):
                    continue

                if member_path.name in restored:
                    fail("duplicate_vaultwarden_database_member")
                source = archive.extractfile(member)
                if source is None:
                    fail("unreadable_vaultwarden_database_member")

                destination_dir = restore_root / "vaultwarden-data"
                destination_dir.mkdir(mode=0o700, exist_ok=True)
                destination = destination_dir / member_path.name
                with destination.open("xb") as output:
                    shutil.copyfileobj(source, output)
                destination.chmod(member.mode & 0o7777)
                restored[member_path.name] = destination

                if member_path.name == "db.sqlite3":
                    db_metadata = {
                        "uid": member.uid,
                        "gid": member.gid,
                        "mode": member.mode & 0o7777,
                        "bytes": member.size,
                    }
    except (tarfile.TarError, EOFError, OSError):
        fail("archive_integrity_error")

    database = restored.get("db.sqlite3")
    if database is None or db_metadata is None:
        fail("vaultwarden_database_missing")
    if db_metadata["uid"] != args.expected_db_uid:
        fail("vaultwarden_database_uid_mismatch")
    if db_metadata["gid"] != args.expected_db_gid:
        fail("vaultwarden_database_gid_mismatch")
    if db_metadata["mode"] != expected_mode:
        fail("vaultwarden_database_mode_mismatch")
    if database.stat().st_size != db_metadata["bytes"]:
        fail("vaultwarden_database_size_mismatch")

    try:
        connection = sqlite3.connect(database)
        integrity_rows = connection.execute("PRAGMA integrity_check").fetchall()
        connection.close()
    except sqlite3.DatabaseError:
        fail("vaultwarden_sqlite_unreadable")
    if integrity_rows != [("ok",)]:
        fail("vaultwarden_sqlite_integrity_error")

    print(
        json.dumps(
            {
                "archive_integrity": "pass",
                "safe_paths": "pass",
                "member_count": member_count,
                "regular_file_count": regular_file_count,
                "total_uncompressed_bytes": total_uncompressed_bytes,
                "vaultwarden_database": {
                    "archive_uid": db_metadata["uid"],
                    "archive_gid": db_metadata["gid"],
                    "archive_mode": f"{db_metadata['mode']:04o}",
                    "bytes": db_metadata["bytes"],
                    "sqlite_integrity": "pass",
                    "restored_sidecars": sorted(
                        name for name in restored if name != "db.sqlite3"
                    ),
                },
                "restore_root": str(restore_root),
            },
            separators=(",", ":"),
        )
    )


if __name__ == "__main__":
    main()
