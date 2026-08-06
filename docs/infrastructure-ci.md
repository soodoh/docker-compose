# Infrastructure CI boundary

`.github/workflows/infrastructure-reconcile.yml` validates pull requests and creates saved plans through `infrastructure-plan`. Apply runs only from explicit `workflow_dispatch` in the protected `infrastructure-apply` environment.

A dispatch is split across environments. `dispatch-plan` assumes only the AWS/provider plan identities in `infrastructure-plan`, creates the policy-inspected saved-plan bundle, encrypts it to the apply-only age recipient, and uploads only ciphertext for one day. The dependent apply job enters `infrastructure-apply`, decrypts and safely extracts that exact bundle, verifies its commit and per-plan hashes, and uses only apply-bound identities. An apply-environment OIDC token is never exchanged against a plan-environment trust subject.

Configure environment-scoped values with distinct capabilities:

- `AWS_PLAN_ROLE_ARN` and `AWS_APPLY_ROLE_ARN`
- `PROXMOX_PLAN_API_TOKEN` and `PROXMOX_APPLY_API_TOKEN`
- `OMADA_PLAN_USERNAME` / `OMADA_PLAN_PASSWORD` and apply equivalents
- `INFRASTRUCTURE_GITHUB_PLAN_TOKEN` and `INFRASTRUCTURE_GITHUB_APPLY_TOKEN`
- separate Tailscale enrollment and provider OIDC client IDs/audiences for plan and apply

The Tailscale client IDs and audiences are OpenTofu-managed environment variables read from the Tailscale root's remote state. GitHub exchanges short-lived OIDC tokens directly with Tailscale; no reusable Tailscale provider secret belongs in SOPS or GitHub. See [`tailscale-adoption.md`](./tailscale-adoption.md).

The apply role needs backend/state access, the DynamoDB lease, and only the mutation permissions modeled by the roots. The plan role must not have mutation permissions. Provider credentials are supplied through provider environment variables, not OpenTofu input variables.

Protected environment variables carry explicit gates for SSH proof, ZFS migration review, image-lock bootstrap, Proxmox apply/passthrough, console access, LAN rollback, and Arch network restart. Missing or false gates must stop the job.

The transferred artifact is age-encrypted because saved OpenTofu plans can embed sensitive provider inputs even when raw-byte scans do not find them. Upload only the encrypted plan archive. Never upload plaintext plans, state, `.env` files, exports, inventory with protected values, recovery keys, or provider credentials.