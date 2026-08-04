# Infrastructure reconciliation

The desired-state boundary is `infrastructure/contract/home-lab.yml`. OpenTofu roots under `infrastructure/tofu/` own separate failure domains; Ansible owns host configuration; Compose owns application convergence.

Use only the canonical entry point:

```sh
scripts/reconcile-infrastructure validate
scripts/reconcile-infrastructure plan --phase steady
scripts/reconcile-infrastructure apply --phase steady
```

`bootstrap` and `adopt` are plan-only compatibility commands. Adoption deliberately stops after generating policy-inspected plans. Apply consumes saved plans rather than replanning, serializes OpenTofu operations with `-parallelism=1`, acquires the DynamoDB mutation lease, and requires post-apply no-op checks.

Plan credentials must be read-only. Apply credentials are loaded only after the plan boundary has passed. Never pass provider secrets as `TF_VAR_*`, command arguments, artifacts, manifests, or logs.

Special modes (`recovery`, network migration, CT unprotect, and CT decommission) have narrower policy allowlists and dedicated confirmation gates. A successful static plan is not proof that a provider can perform a live Proxmox operation.