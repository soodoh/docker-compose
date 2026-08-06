# Proxmox LXC provider qualification

The disposable LXC qualification is isolated from both production Proxmox roots in `infrastructure/tofu/proxmox-lxc-qualification`. Its encrypted backend key and retained empty state are dedicated tombstones. Never import an existing container, reuse the `proxmox` or `proxmox-legacy` state, or move qualification state between roots.

The workflow **Qualify disposable Proxmox LXC lifecycle** is `workflow_dispatch` only and runs only for an exact `main` commit. Each dispatch selects one operation. Planning uses the protected `infrastructure-plan` environment and its read-only Proxmox identity. Apply uses `infrastructure-apply`, a distinct Proxmox mutation identity, the exact age-encrypted saved plan, and the global production mutation lease. Plaintext plans and their protected inputs are removed before artifact upload. The encrypted manifest binds the operation, commit, fixed public marker, exact plan hash, and SHA-256 identities of the backend bucket, normalized HTTPS Proxmox endpoint, fixed qualification backend key, pinned provider lockfile, and CA certificate. Apply recomputes every identity and rejects a mismatch before backend initialization, API access, or apply without printing plaintext identities.

**AWS foundation ordering:** merge and apply (or conclusively prove a no-op for) the `aws-foundation` policy change that adds `home-lab/proxmox-lxc-qualification/tofu.tfstate` to the exact allowed state keys before dispatching any qualification operation. The restricted plan/apply roles cannot access this root until that prerequisite is live.

## Protected prerequisites

Configure these values in both protected environments; do not put them in repository variables, workflow inputs, issue text, filenames, output, or summaries:

- `PROXMOX_LXC_QUALIFICATION_VMID`: an unused disposable VMID other than 100 or 101.
- `PROXMOX_LXC_QUALIFICATION_TEMPLATE_FILE_ID`: the exact verified `local:vztmpl/...tar.{gz,xz,zst}` file ID already present on `local`.
- existing strict-TLS endpoint and CA bundle values;
- existing separate plan and apply API tokens, AWS plan/apply roles, backend bucket and region, age recipient/key, and Tailscale controller values.

Before create, the plan preflight requires the protected VMID to be absent and the exact template to exist once; the apply preflight additionally uses the mutation identity for a read-only exact local-LVM residual-volume check before the saved plan may apply. Every later phase requires the canonical fixed marker (the provider/API's single trailing newline is accepted and removed only for comparison), stopped status, disabled console, no network, no mount points or additional disks, no passthrough, mappings, hooks, tags, startup behavior, or non-default features, the minimal local-LVM root disk, exact protection state, and agreement between protected inputs, API, and isolated state. Apply postconditions use the mutation identity only for read-only exact volume proofs, then return to the plan identity for the fresh no-op. The helper rejects any extra capability exposed in the pinned provider plan/state or Proxmox configuration. It never broadens ACLs and never discovers or chooses an identifier.

## Required live sequence

Dispatch one operation per completed run in this order:

1. `create` — create only the marked, protected, stopped, off-at-boot, unprivileged, no-network LXC and prove a fresh no-op.
2. `probe-protected-delete` — plan exact deletion, require apply to fail with a recognized protection-specific provider/API rejection, then prove through read-only API and state evidence that the exact LXC remains protected.
3. `verify-protected` — independently require the protected declaration to be a no-op before any unprotection.
4. `unprotect` — change only `protection = true` to `false`, then prove exact unprotected identity and a fresh no-op.
5. `delete` — delete only that already-unprotected LXC, then prove API absence, local-LVM volume absence, empty isolated state, absent backend lock, and a fresh `verify-empty` no-op.
6. `verify-empty` — independently repeat the absent API/volume, empty-state, no-lock, and no-op proof. Retain the empty backend state.

`reprotect` is emergency-only after `unprotect` and before `delete`; it permits only `false -> true` and requires the protected identity/no-op proof. After reprotection, repeat `verify-protected`, then explicitly dispatch `unprotect` again before deletion.

The protected-delete apply log is a mode-`0600` temporary file and is always destroyed without raw emission. Only a recognized Proxmox protection rejection passes. Authentication, authorization, TLS, provider startup, DNS, connection, transport, timeout, generic apply, and incomplete post-proof errors are inconclusive and fail closed. Once an apply holds the global mutation lease, an unexpected or partial failure retains that lease until expiry and directs operators to `inspect-recovery`; it never imports, removes state, retries, or mutates automatically. Only a completely proved success or the expected protected-delete rejection followed by its complete post-proof releases the lease normally.

## Read-only recovery inspection

Dispatch `inspect-recovery` from `main` after any ambiguous failure. This operation uses only the plan environment identities, acquires no global mutation lease, and performs no OpenTofu plan or apply. It reads the exact backend lock/state and Proxmox inventory/configuration, binds the root-volume identity through config and isolated state without broadening the plan token's VM-disk privileges, and prints only one sanitized classification: `aligned-empty`, `aligned-protected`, `aligned-unprotected`, `live-only-protected`, `live-only-unprotected`, `state-only`, `protection-mismatch`, `live-identity-mismatch`, `state-identity-mismatch`, `lock-present sha256=<fingerprint>`, `backend-init-failed`, `lock-query-failed`, `lock-read-failed`, `lock-count-invalid`, or `state-read-failed`. The fingerprint binds the exact current lock bytes without disclosing the lock ID or runner identity.

A split, mismatched, or locked result is evidence only. It requires a separate reviewed recovery plan. Do not automatically import, run `state rm`, unlock, retry, unprotect, delete, or otherwise mutate from the inspection result.

The narrowly scoped `recover-lock` operation is available only for a reviewed failed run that applied a protected create and then failed its postcondition while retaining both locks. Before dispatch, temporarily set `PROXMOX_LXC_QUALIFICATION_RECOVERY_RUN_ID` and `PROXMOX_LXC_QUALIFICATION_RECOVERY_LOCK_SHA256` only in `infrastructure-apply` to that exact completed failed run ID and the reviewed fingerprint from `inspect-recovery`. Recovery verifies through the GitHub API that the run is the completed failure of this workflow at the incident's pinned historical tooling commit; validates the exact S3 lock schema, UUID, apply operation, backend path, OpenTofu version, failed-step time window, runner identity shape, and incident log evidence; validates that the DynamoDB lease owner binds that run, commit, and qualification operation; force-unlocks only that exact backend lock; requires `aligned-protected`; and conditionally deletes only the matching mutation lease. Any mismatch fails closed. Remove both temporary recovery secrets immediately after the reviewed recovery run. This operation cannot import, change state, alter the LXC, unprotect, or delete it.

## CT 101 gate

`proxmox.legacy_container.lxc_provider_qualified` remains `false` in this static implementation. The CT retirement helper and the legacy root reject `unprotect` and `delete` while it is false. The real evidence path `infrastructure/evidence/proxmox-lxc-qualification.json` must remain absent while the gate is false; the adjacent schema and `.example.json` define its secret-free machine format without representing completed evidence.

After the complete live sequence has independent evidence, use a separate evidence-only reviewed PR to add that exact JSON file and set the gate to `true`. Do not combine it with a CT stage transition or retirement operation. The evidence must bind the exact qualification-tooling commit, the locked `registry.opentofu.org/bpg/proxmox` version and lockfile SHA-256, six distinct GitHub run IDs in the exact ordered sequence (`create`, `probe-protected-delete`, `verify-protected`, `unprotect`, `delete`, and `verify-empty`), and the final empty-state/API/volume/lock plus no-op proof. It must contain no protected identifiers. `scripts/validate-contract`, the universal PR transition check, and `.github/scripts/proxmox-lxc-qualification.py validate-run-evidence` all fail closed for absent, malformed, reordered, duplicate, wrong-commit, or wrong-provider evidence. Procedural statements are not qualification evidence.
