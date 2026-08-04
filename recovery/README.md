# Home lab disaster recovery

The recovery boundary is deliberately split: OpenTofu recreates control-plane resources and VM 100; Ansible reconciles Proxmox and Arch; the protected Compose pipeline restores workloads. ZFS import and critical-data restore are assertion-oriented and never create, format, or overwrite storage.

## Required offline inputs

- recovery age identity and the future CI age **public** recipient
- AWS recovery credentials, region, state bucket, recovery bucket, and KMS access
- separate read-only plan and mutation-capable apply Proxmox API tokens, account-specific bootstrap SSH public keys, and verified SSH host-key fingerprints
- `PROXMOX_HARDWARE_MAPPINGS_ENABLED=true` after adoption qualification or recovery, so later steady plans retain token-compatible mappings
- Tailscale workload identity, GitHub token, and Omada credentials
- SOPS-protected `/dev/disk/by-id` identities and USB serial mappings
- ignored Omada export matching `infrastructure/tofu/omada/EXPORT_SCHEMA.md`
- exact off-site backup ID and a short-lived HTTPS URL for that object
- GPG recovery private key and, when applicable, a passphrase file

Never place these values in Git, a plan artifact, command-line history, or recovery evidence.

## Recovery order

1. Install Proxmox manually and retain console access. Do not create/import pools in the installer.
2. Copy `ansible/inventory/proxmox-local.yml` and the repository to the host. Run `playbooks/proxmox-bootstrap.yml` locally only with console, LAN rollback, and storage identity gates satisfied. This stage intentionally leaves SSH password policy unchanged. Escrow the separated tokens, prove a `tofu-apply` connection over Tailscale from the recovery controller, and only then set `proxmox_ssh_access_proven=true` for the later steady-site play.
3. Configure the existing encrypted S3 backend. Copy `recovery/extra-vars.example.yml` to an ignored, root-only file and review every false gate. Select one exact `daily-remote-backup-YYYY-MM-DDTHH-MM-SS.tar.gz.gpg` object and a short-lived HTTPS URL. Record its ID, URL, GPG key paths, `/srv/home-lab-recovery/<id>` target, empty-target approval, restore approval, and surviving-bind choice there. Recovery forces creation and use of token-compatible Proxmox hardware mappings; retain both mapping variables as `true` for later steady plans.
4. Run `scripts/reconcile-infrastructure plan --phase recovery` from a trusted controller. Review every policy result and saved-plan hash. The plan operation is read-only and does not download or decrypt the backup.
5. Run the matching `apply --phase recovery` only after the DynamoDB mutation lease is available. It applies the exact saved plans, bootstraps Arch, stages the exact Compose artifact, downloads and verifies only the selected backup, activates data only into inventoried fresh targets, starts Compose, removes decrypted staging after health passes, and performs no-op checks and the full audit.
6. Record secret-free evidence: commit, plan hashes, backup object ID hash, archive checks, service health, and elapsed recovery time.

The restore target is an approved empty staging root. The extractor rejects traversal, device nodes, hard links, unsafe symlinks, duplicate writes, and archives missing critical classes. Recovery creates and inventories a fresh Compose volume set before activation, refuses existing Docker volumes, and refuses nonempty bind targets. When ZFS-backed Home Assistant or Wolf data intentionally survived, `recovery_retain_existing_bind_data=true` may retain only those modeled nonempty binds; it never permits overwriting them or a nonempty recovered SSH target.

## Encrypted recovery bundle

After every qualified change, fetch the root-only current/previous image locks, refresh the secret-free recovery proof, and run:

```sh
scripts/build-recovery-bundle \
  --output .local/recovery/home-lab.tar.gz.age \
  --omada-export .local/omada/export.json \
  --current-image-lock .local/recovery/current-images.json \
  --previous-image-lock .local/recovery/previous-images.json \
  --wolf-image-lock .local/recovery/wolf-images.json \
  --recovery-evidence .local/recovery/recovery-proof.json
```

The builder requires a clean commit, fresh commit-bound evidence, the ignored Omada export, both Compose image locks, the immutable Wolf child-image lock, two age recipients, and recorded Coral hashes. It creates a deterministic inner archive and checksum manifest, then encrypts the entire bundle to both recipients. Upload only the encrypted `.age` file to the versioned KMS-protected recovery bucket.

Before bundle creation, publish reviewed local Wolf child images to repository-scoped GHCR names and capture their immutable digests with `scripts/publish-wolf-images --manifest <ignored-input> --output .local/recovery/wolf-images.json`. Publication requires the exact `WOLF_IMAGE_PUBLICATION_CONFIRMED=publish-reviewed-wolf-images-to-ghcr` gate and protected GHCR credentials. The input records each real local `sha256:` image ID and uses the matching `image-<64-hex>` tag; no placeholder manifest is tracked.

## Operational blockers

Recovery intentionally stops while contract values are `null` or qualification gates are false. At minimum, publish the Coral OCI artifact and record its digest/package checksum; supply AWS bucket names; migrate SOPS after receiving the CI public recipient; and keep Omada management disabled until the ignored export and three consecutive qualified no-op plans exist.

CT 101 is adopted in its separate protected state. It is neither rebuilt nor decommissioned by recovery mode. Only after direct Tailscale paths and every other OpenTofu/Ansible/Compose check are no-ops, set the exact `TF_VAR_decommission_confirmation` documented by the root. Run `--phase steady --ct-unprotect`, require a no-op follow-up, then run `--phase steady --ct-decommission`. The policy permits only CT 101 unprotection or deletion, and the orchestrator applies either operation last.
