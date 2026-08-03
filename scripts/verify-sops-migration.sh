#!/usr/bin/env bash
set -euo pipefail

stage=initialization
trap 'printf "sops_migration_verification=failed stage=%s\n" "$stage" >&2' ERR

if [[ $EUID -ne 0 ]]; then
  echo "Run this migration verification as root." >&2
  exit 1
fi

readonly REPOSITORY=/home/docker/Projects/docker-compose
readonly SOURCE_ENV="$REPOSITORY/.env"
readonly CIPHERTEXT="$REPOSITORY/secrets/production.sops.env"
readonly KEY_MANIFEST="$REPOSITORY/secrets/production.env.keys"
readonly LAYOUT_MANIFEST="$REPOSITORY/secrets/production.env.layout.json"
readonly IDENTITY_FILE=/etc/sops/age/keys.txt
readonly RECIPIENT=age1vvzm5pczjum52v5alall8euucjen9q4v9xa5g0xmswhna5vare9qwv9rq6

stage=input_validation
printf 'verification_stage=input_validation\n'
for path in "$SOURCE_ENV" "$CIPHERTEXT" "$KEY_MANIFEST" "$LAYOUT_MANIFEST" "$IDENTITY_FILE"; do
  if [[ ! -r $path ]]; then
    echo "Required migration input is unavailable." >&2
    exit 1
  fi
done

tmpdir=$(mktemp -d /tmp/sops-migration-verify.XXXXXX)
trap 'rm -rf -- "$tmpdir"' EXIT
chmod 0700 "$tmpdir"

stage=decryption
SOPS_AGE_KEY_FILE="$IDENTITY_FILE" /usr/local/bin/sops decrypt \
  --input-type dotenv \
  --output-type dotenv \
  --output "$tmpdir/canonical.env" \
  "$CIPHERTEXT" >/dev/null 2>&1
chmod 0600 "$tmpdir/canonical.env"
python "$REPOSITORY/scripts/restore-dotenv-layout.py" \
  "$tmpdir/canonical.env" "$LAYOUT_MANIFEST" "$tmpdir/decrypted.env" >/dev/null
chmod 0600 "$tmpdir/decrypted.env"
printf 'verification_stage=decryption_passed\n'

stage=byte_comparison
if ! cmp --silent "$SOURCE_ENV" "$tmpdir/decrypted.env"; then
  python "$REPOSITORY/scripts/diagnose-sops-byte-mismatch.py" \
    "$SOURCE_ENV" "$tmpdir/decrypted.env"
  false
fi
printf 'verification_stage=byte_comparison_passed\n'

stage=variable_name_comparison
python "$REPOSITORY/scripts/extract-dotenv-keys.py" \
  "$SOURCE_ENV" "$tmpdir/source.keys" >/dev/null
python "$REPOSITORY/scripts/extract-dotenv-keys.py" \
  "$tmpdir/decrypted.env" "$tmpdir/decrypted.keys" >/dev/null
cmp --silent "$tmpdir/source.keys" "$tmpdir/decrypted.keys"
cmp --silent "$tmpdir/source.keys" "$KEY_MANIFEST"
printf 'verification_stage=variable_names_passed\n'

stage=ciphertext_structure
python "$REPOSITORY/scripts/check-sops-env.py" \
  "$CIPHERTEXT" "$KEY_MANIFEST" "$LAYOUT_MANIFEST" "$RECIPIENT" >/dev/null
printf 'verification_stage=ciphertext_structure_passed\n'

trap - ERR
printf 'server_sops_decryption=pass\n'
printf 'source_byte_match=pass\n'
printf 'variable_name_sets=pass count=%s\n' "$(wc -l <"$KEY_MANIFEST")"
