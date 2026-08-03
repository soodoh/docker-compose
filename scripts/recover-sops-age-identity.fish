#!/usr/bin/env fish

function recover_sops_age_identity
    set -l SERVER docker@100.111.210.72
    set -l PRIVILEGED_SERVER ansible-deploy@100.111.210.72
    set -l AGE_VERSION 1.3.1
    set -l EXPECTED_RECIPIENT age1vvzm5pczjum52v5alall8euucjen9q4v9xa5g0xmswhna5vare9qwv9rq6
    set -l EXPECTED_CIPHERTEXT_SHA256 88ab3cbdc4c79b78c3f0f8694e3d5829b2fea62c114a84ebaf99386eafaeb80e

    for tool in curl gpg scp shasum tar
        command -q $tool; or begin
            echo "missing_tool=$tool" >&2
            return 1
        end
    end

    switch (uname -m)
        case arm64
            set AGE_ASSET age-v$AGE_VERSION-darwin-arm64.tar.gz
            set AGE_ARCHIVE_SHA256 01120ea2cbf0463d4c6bd767f99f3271bbed1cdc8a9aa718a76ba1fe4f01998b
        case x86_64
            set AGE_ASSET age-v$AGE_VERSION-darwin-amd64.tar.gz
            set AGE_ARCHIVE_SHA256 2b233301ad21ab7b1eabd9ae1198a164005fa4928fcdd745d47c39f8593209d7
        case '*'
            echo unsupported_macos_architecture >&2
            return 1
    end

    set -l SERVER_RECIPIENT (ssh "$PRIVILEGED_SERVER" \
        'sudo /usr/local/bin/age-keygen -y /etc/sops/age/keys.txt'); or return 1
    test "$SERVER_RECIPIENT" = "$EXPECTED_RECIPIENT"; or begin
        echo server_recipient_mismatch >&2
        return 1
    end
    set -l IDENTITY_DIRECTORY_METADATA (ssh "$PRIVILEGED_SERVER" \
        "sudo stat -c '%U:%G:%a:%F' /etc/sops/age"); or return 1
    set -l IDENTITY_FILE_METADATA (ssh "$PRIVILEGED_SERVER" \
        "sudo stat -c '%U:%G:%a:%F' /etc/sops/age/keys.txt"); or return 1
    test "$IDENTITY_DIRECTORY_METADATA" = 'root:root:700:directory'; or return 1
    test "$IDENTITY_FILE_METADATA" = 'root:root:600:regular file'; or return 1

    set -l TMPDIR_RECOVERY (mktemp -d); or return 1
    set -l AGE_ARCHIVE "$TMPDIR_RECOVERY"/age.tar.gz
    set -l RECOVERY_CIPHERTEXT "$TMPDIR_RECOVERY"/recovery.gpg
    set -l DECRYPTED_TEMP "$TMPDIR_RECOVERY"/keys.txt
    set -l RECOVERY_DIR "$HOME"/.config/sops/age-recovery
    set -l RECOVERY_KEY "$RECOVERY_DIR"/docker-compose-production-keys.txt
    set -l RECOVERY_GPG "$RECOVERY_DIR"/docker-compose-production-keys.txt.gpg

    if test -e "$RECOVERY_KEY"; or test -e "$RECOVERY_GPG"
        echo recovery_destination_already_exists >&2
        rm -rf -- "$TMPDIR_RECOVERY"
        return 1
    end

    set -l AGE_URL https://github.com/FiloSottile/age/releases/download/v$AGE_VERSION/$AGE_ASSET
    curl --fail --location --silent --show-error --output "$AGE_ARCHIVE" "$AGE_URL"; or return 1
    set -l ACTUAL_ARCHIVE_SHA256 (shasum -a 256 "$AGE_ARCHIVE" | awk '{print $1}')
    test "$ACTUAL_ARCHIVE_SHA256" = "$AGE_ARCHIVE_SHA256"; or begin
        echo age_archive_checksum=failed >&2
        rm -rf -- "$TMPDIR_RECOVERY"
        return 1
    end
    tar -xzf "$AGE_ARCHIVE" -C "$TMPDIR_RECOVERY"; or return 1

    scp "$SERVER:/home/docker/sops-age-recovery.txt.gpg" "$RECOVERY_CIPHERTEXT"; or return 1
    set -l ACTUAL_CIPHERTEXT_SHA256 (shasum -a 256 "$RECOVERY_CIPHERTEXT" | awk '{print $1}')
    test "$ACTUAL_CIPHERTEXT_SHA256" = "$EXPECTED_CIPHERTEXT_SHA256"; or begin
        echo recovery_ciphertext_checksum=failed >&2
        rm -rf -- "$TMPDIR_RECOVERY"
        return 1
    end

    read --silent --prompt-str 'GPG passphrase (input hidden): ' GPG_PASSPHRASE </dev/tty; or return 1
    echo >/dev/tty
    test -n "$GPG_PASSPHRASE"; or return 1
    gpg --batch --yes --quiet --pinentry-mode loopback \
        --passphrase-file (printf '%s\n' "$GPG_PASSPHRASE" | psub -f) \
        --output "$DECRYPTED_TEMP" \
        --decrypt "$RECOVERY_CIPHERTEXT" 2>/dev/null
    set -l GPG_STATUS $status
    set --erase GPG_PASSPHRASE
    test "$GPG_STATUS" -eq 0; or begin
        echo recovery_decryption=failed >&2
        rm -rf -- "$TMPDIR_RECOVERY"
        return 1
    end

    chmod 0600 "$DECRYPTED_TEMP" "$RECOVERY_CIPHERTEXT"; or begin
        rm -rf -- "$TMPDIR_RECOVERY"
        return 1
    end
    mkdir -p "$RECOVERY_DIR"; or begin
        rm -rf -- "$TMPDIR_RECOVERY"
        return 1
    end
    chmod 0700 "$HOME"/.config/sops "$RECOVERY_DIR" 2>/dev/null; or begin
        rm -rf -- "$TMPDIR_RECOVERY"
        return 1
    end
    cp -p "$DECRYPTED_TEMP" "$RECOVERY_KEY"; or begin
        rm -rf -- "$TMPDIR_RECOVERY"
        return 1
    end
    cp -p "$RECOVERY_CIPHERTEXT" "$RECOVERY_GPG"; or begin
        rm -f -- "$RECOVERY_KEY"
        rm -rf -- "$TMPDIR_RECOVERY"
        return 1
    end
    chmod 0600 "$RECOVERY_KEY" "$RECOVERY_GPG"; or begin
        rm -f -- "$RECOVERY_KEY" "$RECOVERY_GPG"
        rm -rf -- "$TMPDIR_RECOVERY"
        return 1
    end

    set -l RECIPIENT ("$TMPDIR_RECOVERY"/age/age-keygen -y "$RECOVERY_KEY")
    test "$status" -eq 0; and test "$RECIPIENT" = "$EXPECTED_RECIPIENT"; or begin
        echo recovery_recipient_mismatch >&2
        rm -f -- "$RECOVERY_KEY" "$RECOVERY_GPG"
        rm -rf -- "$TMPDIR_RECOVERY"
        return 1
    end

    printf '%s\n' 'external age recovery proof' >"$TMPDIR_RECOVERY"/proof.txt
    "$TMPDIR_RECOVERY"/age/age \
        --recipient "$RECIPIENT" \
        --output "$TMPDIR_RECOVERY"/proof.txt.age \
        "$TMPDIR_RECOVERY"/proof.txt; or begin
        rm -f -- "$RECOVERY_KEY" "$RECOVERY_GPG"
        rm -rf -- "$TMPDIR_RECOVERY"
        return 1
    end
    "$TMPDIR_RECOVERY"/age/age \
        --decrypt \
        --identity "$RECOVERY_KEY" \
        --output "$TMPDIR_RECOVERY"/proof.decrypted.txt \
        "$TMPDIR_RECOVERY"/proof.txt.age; or begin
        rm -f -- "$RECOVERY_KEY" "$RECOVERY_GPG"
        rm -rf -- "$TMPDIR_RECOVERY"
        return 1
    end
    cmp --silent "$TMPDIR_RECOVERY"/proof.txt "$TMPDIR_RECOVERY"/proof.decrypted.txt; or begin
        rm -f -- "$RECOVERY_KEY" "$RECOVERY_GPG"
        rm -rf -- "$TMPDIR_RECOVERY"
        return 1
    end

    rm -rf -- "$TMPDIR_RECOVERY"
    echo server_identity_metadata=pass
    echo external_recovery_storage=pass
    echo external_recovery_decryption=pass
    echo age_recipient="$RECIPIENT"
    echo recovery_key_path="$RECOVERY_KEY"
    echo recovery_ciphertext_path="$RECOVERY_GPG"
end

recover_sops_age_identity
exit $status
