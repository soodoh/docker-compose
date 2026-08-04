# Qualification status

## Statically implemented

- contract and JSON-schema validation
- provider lock validation and policy-inspected saved plans
- isolated OpenTofu roots and serial apply orchestration
- Proxmox/Arch bootstrap and steady Ansible gates
- exact backup-ID, version, checksum, archive, and fresh-target recovery controls
- current/previous Compose image locks and immutable Wolf publication tooling
- CI plan/apply credential separation and protected confirmation gates
- static recovery fixtures and playbook syntax rehearsal

## Requires protected inputs

Backend coordinates, provider credentials, SSH fingerprints/keys, hardware identities, Omada export, backup object/version/checksum, GPG material, SOPS recipients, Coral artifact hashes, and recovery evidence are intentionally absent from Git.

## Requires live qualification

Disposable-VM Proxmox provider behavior, raw disks/passthrough/mappings, Omada import/no-op, ZFS import evidence, immutable Wolf image publication, Coral package publication/runtime, full restore, cold boot, service health, cleanup, recovery-time objective, and final no-op all remain operational proofs.

Static validation must not be represented as production readiness. Update this document only with evidence from the protected qualification process; never paste secrets or protected identifiers.