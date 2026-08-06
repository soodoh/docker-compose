# Tailscale OpenTofu adoption

Tailscale is a bootstrap dependency for the infrastructure pipeline, but its steady-state provider access is secretless. Do not commit a reusable Tailscale API token or OAuth client secret to SOPS or GitHub.

## Trust boundary

The one unavoidable manual root of trust is a temporary OAuth client created by a tailnet owner or administrator. Store its client ID, client secret, and `TAILSCALE_TAILNET=-` only in ignored `.local/tailscale/bootstrap.env`, owned by the operator and mode `0600`. The bootstrap client needs `policy_file`, `devices:core:read`, `devices:posture_attributes`, `federated_keys`, and `auth_keys` restricted to `tag:ci-plan` and `tag:ci-apply`. The delegated auth-key scope is required to adopt and reconcile federated identities that themselves mint those exact ephemeral tags. Revoke the client after adoption and protected pipeline qualification.

The OpenTofu Tailscale root then owns:

- the complete tailnet policy, including tag owners, route auto-approvers, grants, SSH rules, policy tests, and SSH tests;
- separate GitHub OIDC identities that may create ephemeral `tag:ci-plan` and `tag:ci-apply` enrollment keys; and
- separate GitHub OIDC provider identities for read-only plans and protected applies.

Tailscale canonicalizes GitHub trust subjects with stable numeric owner and repository IDs. The bootstrap resolves those public IDs from GitHub, stages them as protected-environment variables, and uses the canonical subject form for all four identities to prevent perpetual provider diffs.

The provider-plan identity has only `policy_file:read`, `devices:core:read`, `devices:posture_attributes:read`, and `federated_keys:read`. The provider-apply identity has the corresponding policy, posture-attribute, and federated-key write scopes while retaining read-only device-core access. It also has `auth_keys` delegation restricted to `tag:ci-plan` and `tag:ci-apply` so OpenTofu can manage the two enrollment identities; it cannot mutate device lifecycle, routes, DNS, or users.

## Adoption sequence

1. Fetch and retain the current policy and its `ETag` under `.local/tailscale/`.
2. Render and validate the repository policy through the Tailscale validation API. Validation must report no errors or warnings.
3. Bootstrap and migrate the AWS state foundation before creating Tailscale state.
4. Authenticate the reviewed AWS bootstrap profile, export the protected backend coordinates, and set `TAILSCALE_BOOTSTRAP_CONFIRMED=apply-reviewed-tailscale-bootstrap`.

Before importing a legacy plan-enrollment identity whose description is unset, set its description to the reviewed `infrastructure-plan` value in the tailnet admin console. Provider `0.29.2` normalizes an unset description to an empty string only in saved plans, causing a metadata-only perpetual update; the non-empty declarative description removes that provider ambiguity while keeping subject, scopes, and tags fully managed.
5. Run `scripts/bootstrap-tailscale-state`. It acquires the global mutation lease, imports both existing CI enrollment identities, permits only the two new provider identities and the declarative `terraform_data.tailscale_policy` state record, binds the saved plan to the live policy hash and `ETag`, atomically submits any policy change with `If-Match`, applies the exact OpenTofu plan serially, proves a no-op, compares live policy to state, and stages the resulting client IDs and audiences in the protected GitHub environments.

A failed partial apply retains its evidence and remote state. After correcting the reviewed credential scope, set `TAILSCALE_BOOTSTRAP_RESUME_CONFIRMED=resume-reviewed-partial-tailscale-bootstrap`; resume permits only in-place updates to the five already adopted resources and still forbids creates, replacements, and deletes.
6. Create a fresh GitHub-root saved plan only after the Tailscale state and outputs exist. During the one-time adoption set `TF_VAR_tailscale_environment_variables_adopt_existing=true` so the staged values are imported rather than recreated. Never reuse a GitHub plan created before Tailscale adoption.
7. Prove both protected OIDC paths and direct Docker/Proxmox connectivity, then revoke the temporary OAuth client and remove `.local/tailscale/bootstrap.env`.

The pinned Tailscale provider does not expose conditional policy updates. The repository therefore keeps the complete desired policy inside OpenTofu state while the guarded reconciler performs the policy API mutation from the saved plan using the captured `ETag`. The API update is validated first and uses `If-Match`; OpenTofu then records the exact same policy. Every steady plan compares live policy to the planned declaration, and every apply verifies live policy against state afterward.

The durable gateway-policy lifecycle is now `active -> detached -> retired`. The contract currently selects `detached`: the guarded detach operation removes the legacy `tag:ci` owner and all of its uses, route auto-approvers, and both routed LAN grants while retaining only the `tag:infra-router` owner/admin grant needed to manage the still-live node. This desired-state change is non-live until the exact saved-plan workflow is dispatched on `main`. Final `retired` policy is implemented but may be selected only after CT 101 is durably retired and device absence is separately approved.

## Recovery

If both managed provider identities become unusable, create a new temporary client with the same bootstrap scopes, inspect the current policy and state before changing anything, and use a saved OpenTofu recovery plan. Never bypass state, overwrite without the current policy identity, or leave the bootstrap client active after recovery.
