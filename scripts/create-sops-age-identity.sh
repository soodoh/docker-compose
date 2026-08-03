#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run this identity bootstrap as root." >&2
  exit 1
fi

readonly IDENTITY_DIR=/etc/sops/age
readonly IDENTITY_FILE="$IDENTITY_DIR/keys.txt"
readonly RECOVERY_CIPHERTEXT=/home/docker/sops-age-recovery.txt.gpg
readonly RECOVERY_PUBLIC_KEY=/home/docker/Projects/docker-compose/services/data/backup-gpg-public.asc
readonly RECOVERY_GPG_FINGERPRINT=5B14A67EC89DBA1F4C0FEE7CA678E17443DBD7A4

for tool in /usr/local/bin/age-keygen /usr/bin/gpg /usr/bin/install; do
  if [[ ! -x $tool ]]; then
    echo "Required tool is unavailable: $tool" >&2
    exit 1
  fi
done
if [[ ! -r $RECOVERY_PUBLIC_KEY ]]; then
  echo "The recovery public key is unavailable." >&2
  exit 1
fi

install -d -o root -g root -m 0700 "$IDENTITY_DIR"
if [[ ! -e $IDENTITY_FILE ]]; then
  old_umask=$(umask)
  umask 077
  /usr/local/bin/age-keygen -o "$IDENTITY_FILE" >/dev/null 2>&1
  umask "$old_umask"
fi
chown root:root "$IDENTITY_FILE"
chmod 0600 "$IDENTITY_FILE"

recipient=$(/usr/local/bin/age-keygen -y "$IDENTITY_FILE")
if [[ ! $recipient =~ ^age1[0-9a-z]+$ ]]; then
  echo "The generated age recipient is invalid." >&2
  exit 1
fi

tmpdir=$(mktemp -d /tmp/sops-age-recovery.XXXXXX)
trap 'rm -rf -- "$tmpdir"' EXIT
chmod 0700 "$tmpdir"
export GNUPGHOME="$tmpdir/gnupg"
install -d -o root -g root -m 0700 "$GNUPGHOME"
gpg --batch --quiet --import "$RECOVERY_PUBLIC_KEY" >/dev/null 2>&1
imported_fingerprint=$(gpg --batch --with-colons --list-keys "$RECOVERY_GPG_FINGERPRINT" 2>/dev/null \
  | awk -F: '$1 == "fpr" { print $10; exit }')
if [[ $imported_fingerprint != "$RECOVERY_GPG_FINGERPRINT" ]]; then
  echo "The recovery public-key fingerprint does not match." >&2
  exit 1
fi

gpg --batch --yes --quiet --trust-model always \
  --recipient "$RECOVERY_GPG_FINGERPRINT" \
  --output "$tmpdir/recovery.gpg" \
  --encrypt "$IDENTITY_FILE" >/dev/null 2>&1
install -o docker -g docker -m 0600 "$tmpdir/recovery.gpg" "$RECOVERY_CIPHERTEXT"

printf 'sops_age_identity=pass\n'
printf 'age_recipient=%s\n' "$recipient"
printf 'recovery_ciphertext=%s\n' "$RECOVERY_CIPHERTEXT"
printf 'recovery_ciphertext_sha256=%s\n' "$(sha256sum "$RECOVERY_CIPHERTEXT" | awk '{print $1}')"
