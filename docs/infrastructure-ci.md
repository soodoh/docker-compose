# Infrastructure CI boundary

`.github/workflows/infrastructure-reconcile.yml` validates pull requests and creates saved plans. Apply runs only from explicit `workflow_dispatch` in the protected `infrastructure-production` environment.

Configure environment-scoped values with distinct capabilities:

- `AWS_PLAN_ROLE_ARN` and `AWS_APPLY_ROLE_ARN`
- `PROXMOX_PLAN_API_TOKEN` and `PROXMOX_APPLY_API_TOKEN`
- `OMADA_PLAN_USERNAME` / `OMADA_PLAN_PASSWORD` and apply equivalents
- `INFRASTRUCTURE_GITHUB_PLAN_TOKEN` and `INFRASTRUCTURE_GITHUB_APPLY_TOKEN`
- `TS_PROVIDER_PLAN_CLIENT_ID` and `TS_PROVIDER_APPLY_CLIENT_ID`, with matching audiences

The apply role needs backend/state access, the DynamoDB lease, and only the mutation permissions modeled by the roots. The plan role must not have mutation permissions. Provider credentials are supplied through provider environment variables, not OpenTofu input variables.

Protected environment variables carry explicit gates for SSH proof, ZFS migration review, image-lock bootstrap, Proxmox apply/passthrough, console access, LAN rollback, and Arch network restart. Missing or false gates must stop the job.

Artifacts must contain only saved plans, policy reports, hashes, and the secret-free manifest. Never upload state, `.env` files, exports, inventory with protected values, recovery keys, or provider credentials.