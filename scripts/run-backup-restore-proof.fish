#!/usr/bin/env fish

function docker_compose_restore_proof
    set -l SERVER docker@100.111.210.72
    set -l EXPECTED_SHA256 3b9aa766409aac86017080a11d17e8e7178aa4cedae9a75a0801c2afd8eb4568
    set -l BACKUP /mnt/storage/backups/daily-backup-2026-08-01T06-00-00.tar.gz.gpg

    for tool in gpg python3 ssh shasum
        command -q $tool; or begin
            echo "missing_tool=$tool" >&2
            return 1
        end
    end

    set -l WORKDIR (mktemp -d); or return 1
    set -l VERIFIER "$WORKDIR"/verify-backup-archive.py
    set -l RESTORE_ROOT "$WORKDIR"/restored
    set -l EVIDENCE "$WORKDIR"/restore-evidence.json
    set -l SCRIPT_DIR (path resolve (dirname (status filename)))

    cp "$SCRIPT_DIR"/verify-backup-archive.py "$VERIFIER"; or return 1

    chmod 0755 "$VERIFIER"; or return 1
    python3 -m py_compile "$VERIFIER"; or return 1

    set -l ACTUAL_SHA256 (shasum -a 256 "$VERIFIER" | awk '{print $1}')
    test "$ACTUAL_SHA256" = "$EXPECTED_SHA256"; or begin
        echo verifier_checksum=failed >&2
        return 1
    end

    ssh "$SERVER" "test -r '$BACKUP'"; or return 1

    read --silent --prompt-str 'GPG passphrase (input hidden): ' GPG_PASSPHRASE </dev/tty; or return 1
    echo >/dev/tty
    test -n "$GPG_PASSPHRASE"; or begin
        echo gpg_passphrase=empty >&2
        return 1
    end

    echo verifier_checksum=pass
    echo restore_stream=starting
    set -l STARTED (date +%s)

    ssh "$SERVER" "exec cat -- '$BACKUP'" \
        | gpg --batch --yes --quiet --pinentry-mode loopback \
            --passphrase-file (printf '%s\n' "$GPG_PASSPHRASE" | psub -f) \
            --decrypt 2>/dev/null \
        | python3 "$VERIFIER" --restore-root "$RESTORE_ROOT" \
        | tee "$EVIDENCE"

    set -l PIPE_RESULTS $pipestatus
    set --erase GPG_PASSPHRASE

    for RESULT in $PIPE_RESULTS
        test "$RESULT" -eq 0; or begin
            echo restore_pipeline=failed >&2
            return 1
        end
    end

    set -l FINISHED (date +%s)
    echo restore_pipeline=pass
    echo restore_elapsed_seconds=(math "$FINISHED" - "$STARTED")
    echo restore_root="$RESTORE_ROOT"
    echo evidence_file="$EVIDENCE"
end

docker_compose_restore_proof
exit $status
