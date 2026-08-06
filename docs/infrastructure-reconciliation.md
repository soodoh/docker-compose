# Infrastructure reconciliation

The desired-state boundary is `infrastructure/contract/home-lab.yml`. OpenTofu roots under `infrastructure/tofu/` own separate failure domains; Ansible owns host configuration; Compose owns application convergence.

Use only the canonical entry point:

```sh
scripts/reconcile-infrastructure validate
scripts/reconcile-infrastructure plan --phase steady
scripts/reconcile-infrastructure apply --phase steady
```

`bootstrap` and `adopt` are plan-only compatibility commands. Adoption deliberately stops after generating policy-inspected plans. Apply consumes saved plans rather than replanning, serializes OpenTofu operations with `-parallelism=1`, acquires the DynamoDB mutation lease, and requires post-apply no-op checks.

Plan credentials must be read-only. Apply credentials are loaded only after the plan boundary has passed. Never pass provider secrets as command arguments, artifacts, manifests, or logs. The CT confirmation is supplied only as the environment-scoped `PROXMOX_CT_DECOMMISSION_CONFIRMATION` GitHub secret. The reconciler verifies it without printing it, then exports it only as the sensitive, ephemeral `TF_VAR_decommission_confirmation` environment variable; it is never a CLI argument or manifest field and OpenTofu does not persist it in plan or state. OpenTofu independently validates its SHA-256 identity and fails planning when it is missing or invalid for an unprotected or retired durable stage, including steady operation `none`. The apply environment must supply it again so the independent hard gate remains active when consuming a saved plan.

Special modes (`recovery`, network migration, CT retirement, and Omada qualification) have narrower policy allowlists and dedicated gates. They cannot be combined. A successful static plan is not proof that a provider can perform a live operation.

## CT 101 retirement lifecycle

The durable desired state is `proxmox.legacy_container.retirement_stage`:

- `protected`: the resource exists with protection enabled.
- `unprotected`: the resource exists with protection disabled.
- `retired`: resource count and import are disabled; the empty `proxmox-legacy` root and state remain as a tombstone.

Change this contract stage in a reviewed PR before dispatching an operation. PR validation permits only `protected -> unprotected`, `unprotected -> retired`, and `unprotected -> protected`; stage skips and transitions out of `retired` are rejected.

After the stage change is on `main`, dispatch the workflow with exactly one matching `ct_retirement` operation. The reconciler equivalent is:

```sh
scripts/reconcile-infrastructure plan --phase steady --ct-operation unprotect
scripts/reconcile-infrastructure apply --phase steady --ct-operation unprotect

scripts/reconcile-infrastructure plan --phase steady --ct-operation delete
scripts/reconcile-infrastructure apply --phase steady --ct-operation delete
```

The operation selects only the gate and plan policy; it never controls resource count or protection. Saved-plan manifests bind the exact operation and contract stage alongside commit, Compose artifact identity, and plan hashes. A special operation requires every non-legacy OpenTofu root and all Ansible checks to be no-op. Immediately before applying the legacy root last, a read-only Ansible playbook recomputes the active artifact at `/srv/docker-compose/current` with its own `scripts/compose-artifact.py --no-git hash` and requires exact equality with the already repository-verified manifest hash. A missing, unreadable, or mismatched active artifact stops retirement; this prerequisite never stages or deploys Compose. Post-apply no-op verification remains mandatory. Repeating the special operation is rejected because its policy requires exactly one target action. Use normal operation `none` for subsequent reconciliation.
