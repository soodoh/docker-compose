# Infrastructure CI boundary

`.github/workflows/infrastructure-reconcile.yml` validates pull requests and creates saved plans through `infrastructure-plan`. Apply runs only from explicit `workflow_dispatch` of `main` in the protected `infrastructure-apply` environment; dispatches of branches or tags are rejected.

A dispatch is split across environments. `dispatch-plan` assumes only the AWS/provider plan identities in `infrastructure-plan`, creates the policy-inspected saved-plan bundle, encrypts it to the apply-only age recipient, and uploads only ciphertext for one day. The dependent apply job enters `infrastructure-apply`, decrypts and safely extracts that exact bundle, verifies its commit and per-plan hashes, and uses only apply-bound identities. An apply-environment OIDC token is never exchanged against a plan-environment trust subject.

Configure environment-scoped values with distinct capabilities:

- `AWS_PLAN_ROLE_ARN` and `AWS_APPLY_ROLE_ARN`
- `PROXMOX_PLAN_API_TOKEN` and `PROXMOX_APPLY_API_TOKEN`
- `OMADA_PLAN_USERNAME` / `OMADA_PLAN_PASSWORD` and apply equivalents
- `INFRASTRUCTURE_GITHUB_PLAN_TOKEN` and `INFRASTRUCTURE_GITHUB_APPLY_TOKEN`
- separate Tailscale enrollment and provider OIDC client IDs/audiences for plan and apply
- the same environment-scoped `PROXMOX_CT_DECOMMISSION_CONFIRMATION` secret in `infrastructure-plan` and `infrastructure-apply`

The Tailscale client IDs and audiences are OpenTofu-managed environment variables read from the Tailscale root's remote state. GitHub exchanges short-lived OIDC tokens directly with Tailscale; no reusable Tailscale provider secret belongs in SOPS or GitHub. See [`tailscale-adoption.md`](./tailscale-adoption.md).

The apply role needs backend/state access, the DynamoDB lease, and only the mutation permissions modeled by the roots. The plan role must not have mutation permissions. Provider credentials are supplied through provider environment variables, not OpenTofu input variables.

Protected environment variables carry explicit gates for SSH proof, ZFS migration review, image-lock bootstrap, Proxmox apply/passthrough, console access, LAN rollback, and Arch network restart. Missing or false gates must stop the job. Provision the CT confirmation out of band; do not record its acknowledgement value in Git, workflow inputs, CLI arguments, manifests, or logs. The reconciler verifies the environment secret without printing it and exports it only as the sensitive OpenTofu input environment variable. It is required for special CT operations and for ordinary converged plans whenever the committed stage is `unprotected` or `retired`; protected operation `none` remains valid without it.

Pull requests compare the exact base and head contract stages in the universal `Hash and copy exact Compose artifact` check. The check rejects skipped or reversed retirement transitions without causing unrelated pull requests to enter the credentialed infrastructure planning workflow. For infrastructure pull requests, the preview plan selects the exact matching CT policy. Dispatch plan and apply both receive the operator-selected operation, and the encrypted manifest binds that operation and the committed stage before apply.

The CT confirmation is an ephemeral OpenTofu input, so it is required again at apply and is not persisted in the saved plan or state. Saved OpenTofu plans can still embed other sensitive provider inputs even when raw-byte scans do not find them. The residual boundary is therefore an age-encrypted apply-only archive retained for one day: upload only that ciphertext, and never upload plaintext plans, state, `.env` files, exports, inventory with protected values, recovery keys, or provider credentials. Temporary policy JSON is created mode `0600` and removed after inspection.
