#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run this installer as root." >&2
  exit 1
fi

readonly SOPS_VERSION=3.13.3
readonly AGE_VERSION=1.3.1
readonly SOPS_SHA256=e5bec3346a873ae91d871550f3e698c1aad962aff462a080e40f25fde17fef6b
readonly AGE_ARCHIVE_SHA256=bdc69c09cbdd6cf8b1f333d372a1f58247b3a33146406333e30c0f26e8f51377
readonly AGE_SHA256=2e305637f2a0555305e21c17fb74446acbb39b53135d43d4b744e50c287133a5
readonly AGE_KEYGEN_SHA256=c56ef69834e18ca4d3b953117f4481522c35fb6862a5d2871685aa4685893664
readonly SOPS_URL="https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/sops-v${SOPS_VERSION}.linux.amd64"
readonly AGE_URL="https://github.com/FiloSottile/age/releases/download/v${AGE_VERSION}/age-v${AGE_VERSION}-linux-amd64.tar.gz"

tmpdir=$(mktemp -d /tmp/sops-age-install.XXXXXX)
trap 'rm -rf -- "$tmpdir"' EXIT

curl --fail --location --silent --show-error --output "$tmpdir/sops" "$SOPS_URL"
curl --fail --location --silent --show-error --output "$tmpdir/age.tar.gz" "$AGE_URL"
printf '%s  %s\n' \
  "$SOPS_SHA256" "$tmpdir/sops" \
  "$AGE_ARCHIVE_SHA256" "$tmpdir/age.tar.gz" \
  | sha256sum --check --status

mapfile -t archive_entries < <(tar -tzf "$tmpdir/age.tar.gz" | LC_ALL=C sort)
expected_entries=(
  age/
  age/LICENSE
  age/age
  age/age-inspect
  age/age-keygen
  age/age-plugin-batchpass
)
mapfile -t expected_entries < <(printf '%s\n' "${expected_entries[@]}" | LC_ALL=C sort)
if [[ ${archive_entries[*]} != "${expected_entries[*]}" ]]; then
  echo "The age archive contains unexpected entries." >&2
  exit 1
fi

tar -xzf "$tmpdir/age.tar.gz" -C "$tmpdir"
printf '%s  %s\n' \
  "$AGE_SHA256" "$tmpdir/age/age" \
  "$AGE_KEYGEN_SHA256" "$tmpdir/age/age-keygen" \
  | sha256sum --check --status

install_binary() {
  local source=$1
  local destination=$2
  local expected_sha256=$3

  if [[ -f $destination ]] && [[ $(sha256sum "$destination" | awk '{print $1}') == "$expected_sha256" ]]; then
    return
  fi
  install -o root -g root -m 0755 "$source" "$destination"
  [[ $(sha256sum "$destination" | awk '{print $1}') == "$expected_sha256" ]]
}

install_binary "$tmpdir/sops" /usr/local/bin/sops "$SOPS_SHA256"
install_binary "$tmpdir/age/age" /usr/local/bin/age "$AGE_SHA256"
install_binary "$tmpdir/age/age-keygen" /usr/local/bin/age-keygen "$AGE_KEYGEN_SHA256"

echo "sops_age_install=pass"
echo "sops_version=$SOPS_VERSION"
echo "age_version=$AGE_VERSION"
