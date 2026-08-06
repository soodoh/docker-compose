# Proxmox adoption and qualification

Adoption imports existing resources into isolated state; it must not mutate them. Populate protected inputs outside Git, then run:

```sh
scripts/reconcile-infrastructure adopt
```

Review every saved plan and policy report. Do not continue to steady apply until adoption plans are no-op and the live provider has been qualified against a disposable VM.

Qualification must cover VM create/update/delete, raw-disk attachment, PCI and USB passthrough, hardware mappings, token ACLs, and the configured cloud image. Record command output without host IDs, MAC addresses, serials, tokens, or state contents.

CT 101 stays in its isolated `proxmox-legacy` root. Its contract `retirement_stage` moves through `protected`, `unprotected`, and `retired`; do not skip a stage. Unprotection and deletion use separate exact policy modes and the environment-scoped confirmation secret. They are permitted only after direct Tailscale routing and all non-legacy roots and Ansible checks are no-op, run last, and must be followed by normal operation `none`. The empty legacy root and state remain as a durable tombstone after retirement.

The Proxmox bootstrap play requires local console and LAN rollback gates. The steady play requires proven SSH access before changing password-authentication policy.