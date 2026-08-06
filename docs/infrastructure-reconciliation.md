# Infrastructure reconciliation

The desired-state boundary is `infrastructure/contract/home-lab.yml`. OpenTofu roots under `infrastructure/tofu/` own separate failure domains; Ansible owns host configuration; Compose owns application convergence.

Use only the canonical entry point:

```sh
scripts/reconcile-infrastructure validate
scripts/reconcile-infrastructure plan --phase steady
scripts/reconcile-infrastructure apply --phase steady
```

`bootstrap` and `adopt` are plan-only compatibility commands. Adoption deliberately stops after generating policy-inspected plans. Apply consumes saved plans rather than replanning, serializes OpenTofu operations with `-parallelism=1`, relies on GitHub concurrency, host apply locks, and each root's native OpenTofu S3 lock, and requires post-apply no-op checks. CT and Tailscale gateway lifecycle applies are main-only: GitHub requires exact `refs/heads/main` at `GITHUB_SHA`; local execution requires an attached `main` checkout at the existing `origin/main` commit. Plans and PR previews remain branch-safe.

Plan credentials must be read-only. Apply credentials are loaded only after the plan boundary has passed. Never pass provider secrets as command arguments, artifacts, manifests, or logs. The CT confirmation is supplied only as the environment-scoped `PROXMOX_CT_DECOMMISSION_CONFIRMATION` GitHub secret. The reconciler verifies it without printing it, then exports it only as the sensitive, ephemeral `TF_VAR_decommission_confirmation` environment variable; it is never a CLI argument or manifest field and OpenTofu does not persist it in plan or state. OpenTofu independently validates its SHA-256 identity and fails planning when it is missing or invalid for an unprotected or retired durable stage, including steady operation `none`. The apply environment must supply it again so the independent hard gate remains active when consuming a saved plan.

Special modes (`recovery`, network migration, VM 100 root-disk growth, CT retirement, Tailscale gateway-policy lifecycle, and Omada qualification) have narrower policy allowlists and dedicated gates. They cannot be combined. Disk-growth mode permits only `scsi0` growth from 400 to 550 GiB. It acquires the Docker-host mutation lock before the Proxmox apply, verifies the exact 550 GiB virtual disk and single `/dev/sda1` ext4 root geometry, performs guarded online partition/filesystem expansion, proves a fresh Proxmox and guest no-op, and releases the lock only after success. A separately reviewed pending AWS retirement plan is left unapplied. A successful static plan is not proof that a provider can perform a live operation.

## Tailscale gateway-policy lifecycle

The durable `tailscale.gateway_policy_stage` is `active`, `detached`, or `retired`. `active` renders the historical complete policy. `detached` removes every legacy `tag:ci` use, route auto-approvers, and the two routed LAN grants while retaining the infra-router owner/admin grant for the live node. `retired` additionally removes that final owner and grant, and is allowed only after the CT contract stage is already `retired` and device absence has separate operator approval.

PR comparison permits steady states, `active -> detached`, pre-CT-retirement `detached -> active` rollback, and `detached -> retired` only with an already retired CT. It rejects skips, transitions out of retired, and simultaneous CT/gateway transitions. The universally required Compose validation and infrastructure preview both run this comparison.

After merging a stage transition to `main`, dispatch exactly the matching `tailscale_gateway` operation, or use:

```sh
scripts/reconcile-infrastructure plan --phase steady --tailscale-gateway-operation detach
scripts/reconcile-infrastructure apply --phase steady --tailscale-gateway-operation detach
```

The saved-plan manifest binds operation, stage, the exact saved plan's canonical before/after policy SHA-256 values, and the live plan-time ETag. Planning fails unless the saved plan's canonical before SHA equals the live policy SHA captured with that ETag. Missing, duplicate-key, or otherwise noncanonicalizable before policy JSON fails closed. The dedicated plan policy permits only `terraform_data.tailscale_policy[0]` to update and requires all other roots, including all four federated identities, to be no-op. Apply re-extracts both policy identities from the hash-bound saved plan, validates through the single complete-policy endpoint, rechecks live SHA and ETag against that exact saved-plan before identity immediately before an `If-Match` POST, applies the exact state plan, proves live policy equals state, and finishes with a normal no-op. Exact-after partial recovery remains idempotent; unrelated live drift is never overwritten. Repeating a lifecycle operation is rejected at planning.

Retirement additionally fails closed unless `TAILSCALE_GATEWAY_DEVICE_ABSENCE_APPROVED` is exactly `true` in both protected plan and apply environments. Set this temporary variable only after explicit device-deletion approval and read-only verification that the device is absent; it does not authorize device deletion. Remove it from both environments immediately after the retired no-op proof. Detach does not use this approval.

## Proxmox LXC provider qualification gate

Before any CT 101 unprotection, complete the isolated, main-only saved-plan lifecycle in [`proxmox-lxc-qualification.md`](./proxmox-lxc-qualification.md). The dedicated root has its own backend/state and can own only the fixed-marker disposable LXC. Its protected VMID and exact template file ID stay only in protected environments, encrypted plans, and backend state. Static implementation is not qualification evidence.

The durable `proxmox.legacy_container.lxc_provider_qualified` gate remains `false` until a separate evidence-only PR records the completed create, rejected protected-delete probe, independent protected no-op, unprotect, delete, volume/API absence, empty state, no-lock, and verify-empty sequence. While false, the real evidence path stays absent and only `infrastructure/evidence/proxmox-lxc-qualification.example.json` is tracked. A `false -> true` PR must add the exact schema-valid `infrastructure/evidence/proxmox-lxc-qualification.json`; universal transition validation binds its six run IDs, tooling commit, provider lock, and final proof. CT `unprotect` and `delete` are rejected while the gate is false.

## CT 101 retirement lifecycle

The durable desired state is `proxmox.legacy_container.retirement_stage`:

- `protected`: the resource exists with protection enabled.
- `unprotected`: the resource exists with protection disabled.
- `retired`: resource count and import are disabled; the empty `proxmox-legacy` root and state remain as a tombstone.

Change this contract stage in a reviewed PR before dispatching an operation. PR validation permits only `protected -> unprotected`, `unprotected -> retired`, and `unprotected -> protected`; stage skips and transitions out of `retired` are rejected. Unprotection and deletion additionally require `lxc_provider_qualified: true`, which must come from the earlier evidence-only PR rather than the stage-transition PR.

After the stage change is on `main`, dispatch the workflow with exactly one matching `ct_retirement` operation. The reconciler equivalent is:

```sh
scripts/reconcile-infrastructure plan --phase steady --ct-operation unprotect
scripts/reconcile-infrastructure apply --phase steady --ct-operation unprotect

scripts/reconcile-infrastructure plan --phase steady --ct-operation delete
scripts/reconcile-infrastructure apply --phase steady --ct-operation delete
```

The operation selects only the gate and plan policy; it never controls resource count or protection. Saved-plan manifests bind the exact operation and contract stage alongside commit, Compose artifact identity, and plan hashes. A special operation requires every non-legacy OpenTofu root and all Ansible checks to be no-op. Immediately before applying the legacy root last, a read-only Ansible playbook recomputes the active artifact at `/srv/docker-compose/current` with its own `scripts/compose-artifact.py --no-git hash` and requires exact equality with the already repository-verified manifest hash. A missing, unreadable, or mismatched active artifact stops retirement; this prerequisite never stages or deploys Compose. Post-apply no-op verification remains mandatory. Repeating the special operation is rejected because its policy requires exactly one target action. Use normal operation `none` for subsequent reconciliation.
