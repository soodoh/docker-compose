# Protected Ansible deployment pipeline

## Current status

[`.github/workflows/ansible-deploy.yml`](../.github/workflows/ansible-deploy.yml) stages an automatic, single-tag
plan-to-apply pipeline on a feature branch. Neither automatic production plans nor production applies are active yet.
No normal Ansible run is authorized.

Both repository activation variables are deliberately set to `false`:

```text
ANSIBLE_AUTO_PLAN_ENABLED=false
ANSIBLE_APPLY_ENABLED=false
```

The plan and apply jobs check these variables before targeting their environments. No automatic remote plan, deployment
approval request, or normal Ansible run can start while the corresponding gate is disabled.

## Separate trust paths

Ansible check mode is not a security boundary: repository-controlled tasks can disable check mode or execute arbitrary
commands. Automatic plans therefore must not use the passwordless-root `ansible-deploy` identity.

| Purpose | GitHub environment | Tailscale tag | Host user | Privilege |
|---|---|---|---|---|
| Manual audit | `infrastructure-plan` | `tag:ci` | `ansible-deploy` | Existing passwordless sudo; manual dispatch only |
| Automatic plan | `infrastructure-auto-plan` | `tag:ci-plan` | `ansible-plan` | No general sudo and no supplementary groups |
| Approved apply | `infrastructure-apply` | `tag:ci-apply` | `ansible-deploy` | Existing passwordless sudo after environment approval |

The plan account's only sudo rule is the exact no-argument helper below:

```text
/usr/local/sbin/iac-read-docker-version
```

The root-owned helper accepts no arguments and runs one fixed read-only Docker version query. The plan account is never
added to the Docker group. [`ansible/playbooks/plan-controller.yml`](../ansible/playbooks/plan-controller.yml) stages
creation of that account, helper, and validated sudoers file behind the existing `management_plane` apply guard. Its
normal bootstrap has not been approved or run.

The local check-mode bootstrap completed with `ok=6 changed=1 unreachable=0 failed=0`. The single reported change is
creation of `ansible-plan`; check-mode messages separately identify the normal-run writes to
`/etc/sudoers.d/ansible-plan` and `/usr/local/sbin/iac-read-docker-version`. Both paths and the account remain absent.

[`.github/workflows/plan-controller-bootstrap.yml`](../.github/workflows/plan-controller-bootstrap.yml) is manual-only.
Its privileged check and optional apply are separate `infrastructure-apply` jobs, so each waits for environment approval
and uses `tag:ci-apply`. The apply job revalidates the complete check-output hash before mutation, then independently
runs a zero-change post-check, the full privilege-boundary audit, and an unprivileged `ansible-plan` ping even when an
earlier verification step fails.

## Trigger and intent

After the trust path is proven and the workflow reaches `main`, a remote check-mode plan starts automatically for
relevant changes. A manual `workflow_dispatch` remains available for plan-only stability runs; manually dispatched runs
can never enter the apply job.

[`ansible/deploy-intent.yml`](../ansible/deploy-intent.yml) must contain exactly one allowlisted automation tag:

```yaml
tag: host_files
```

The automation allowlist is `host_files`, `base`, `maintenance`, `storage`, and `docker`. `compose`, `hardware`, `health`,
and `management_plane` are excluded. Compose adoption remains blocked by restore, remote-backup, and health gates.
Management-plane work remains a separate bootstrap procedure.

## Automatic plan

The plan job uses `infrastructure-auto-plan`, its exact GitHub OIDC subject, `tag:ci-plan`, and
[`inventory/production-plan.yml`](../ansible/inventory/production-plan.yml). It:

1. Checks out the triggering commit without persisted Git credentials.
2. Validates the single reviewed intent tag.
3. Installs pinned Python 3.13.14 and `ansible-core==2.21.2`.
4. Creates an ephemeral `tag:ci-plan` Tailscale node without reusable credentials.
5. Verifies DNS and Tailscale SSH are disabled and only the two approved `/32` subnet routes are installed.
6. Requires the recorded Docker ED25519 host-key fingerprint.
7. Connects only as unprivileged `ansible-plan` and validates inventory, connectivity, and `site.yml` syntax.
8. Runs `site.yml --check --diff` for the selected tag.
9. Parses the one-host recap, records the changed count, and hashes the complete plan output.

The `host_files` role suppresses content diffs so unexpected host file contents cannot enter this public repository's
workflow logs. Reviewers use the task/item paths in the plan together with the reviewed source changes. No role may add
a secret-bearing path or unsuppressed sensitive diff to the automation allowlist.

A zero-change plan skips apply. GitHub concurrency keeps one production workflow active, but GitHub may replace an older
pending plan with a newer commit; the apply job separately refuses a commit that is no longer the tip of `main`.

## Protected apply

A changed plan can reach the apply job only when all of these conditions hold:

- The event is a push to `main`, not a manual dispatch.
- `ANSIBLE_APPLY_ENABLED` is exactly `true`.
- The plan completed successfully and reported at least one change.
- GitHub allows the exact `main` commit to deploy to `infrastructure-apply`.
- The required reviewer approves the waiting environment deployment.

`infrastructure-apply` is restricted to `main` and requires `soodoh` as reviewer. Self-approval is allowed because the
repository currently has only one collaborator. This is weaker than independent review. GitHub currently reports that
administrators may manually bypass the environment; do not use that bypass, and disable it before activation if the
repository settings permit.

After approval, the apply job:

1. Checks out the exact planned commit, confirms it is still the tip of `main`, and revalidates its intent tag.
2. Connects as ephemeral `tag:ci-apply`; policy permits plan revalidation as `ansible-plan` and apply as
   `ansible-deploy` only.
3. Re-runs the unprivileged check-mode plan and refuses to continue unless the full output hash matches the approved
   plan.
4. Rechecks the `main` tip immediately before running one normal `site.yml` tag with both guard variables:

   ```text
   -e iac_apply_confirmed=true -e iac_apply_tag=<tag> --tags <tag>
   ```

5. After any apply attempt, including a failed one, runs the same unprivileged tag check and requires `changed=0`,
   `unreachable=0`, and `failed=0`.
6. Runs the complete privileged read-only audit and requires `changed=0`, `unreachable=0`, and `failed=0`.

The workflow never performs an automatic rollback.

## GitHub protections

The default-branch ruleset requires changes to reach `main` through a pull request. It requires zero approving PR reviews
because `soodoh` is the only collaborator, but it has no bypass actors and retains deletion and non-fast-forward
protection. The separate environment review remains the human apply gate.

The manual audit and deployment workflow share the `ansible-production` concurrency group with cancellation disabled.
This serializes participating GitHub jobs but does not coordinate local operators, so it does not replace a host lock.

## Activation blockers

Do not enable either activation variable until the applicable gates are complete:

1. Review and explicitly approve the `plan-controller.yml --check --diff` bootstrap result.
2. Apply that one `management_plane` bootstrap, then prove `ansible-plan` has a locked password, only its private group,
   no Docker access, only the exact helper sudo rule, and no broad passwordless sudo.
3. Add `tag:ci-plan` and `tag:ci-apply` to tailnet policy. Grant both only Docker TCP/22. Permit Tailscale SSH from
   `tag:ci-plan` only as `ansible-plan`; permit `tag:ci-apply` only as `ansible-plan` and `ansible-deploy`.

   Merge this conceptual fragment into the existing policy; never replace unrelated rules:

   ```json
   {
     "tagOwners": {
       "tag:ci-plan": ["autogroup:admin"],
       "tag:ci-apply": ["autogroup:admin"]
     },
     "grants": [
       {
         "src": ["tag:ci-plan", "tag:ci-apply"],
         "dst": ["tag:docker-host"],
         "ip": ["tcp:22"]
       }
     ],
     "ssh": [
       {
         "action": "accept",
         "src": ["tag:ci-plan"],
         "dst": ["tag:docker-host"],
         "users": ["ansible-plan"]
       },
       {
         "action": "accept",
         "src": ["tag:ci-apply"],
         "dst": ["tag:docker-host"],
         "users": ["ansible-plan", "ansible-deploy"]
       }
     ]
   }
   ```
4. Create exact hosted Tailscale federated identities:

   ```text
   infrastructure-auto-plan:
     Issuer:  https://token.actions.githubusercontent.com
     Subject: repo:soodoh/docker-compose:environment:infrastructure-auto-plan
     Scope:   auth_keys
     Tag:     tag:ci-plan

   infrastructure-apply:
     Issuer:  https://token.actions.githubusercontent.com
     Subject: repo:soodoh/docker-compose:environment:infrastructure-apply
     Scope:   auth_keys
     Tag:     tag:ci-apply
   ```

5. Set each environment's non-secret `TS_OAUTH_CLIENT_ID` and `TS_AUDIENCE` variables.
6. Obtain explicit approval before setting `ANSIBLE_AUTO_PLAN_ENABLED=true`; keep apply disabled.
7. Merge through a pull request and review three successful, stable plan-only runs.
8. Confirm repeated plans produce the same recap and hash and expose no sensitive host data.
9. Design and validate a host-side advisory lock honored by GitHub and non-GitHub Ansible operators.
10. Pin or hash-lock the Ansible controller's transitive Python dependencies.
11. Disable administrator environment bypass before apply activation if the repository settings permit.
12. Add an independent reviewer and enable prevent-self-review when another trusted collaborator is available.
13. Obtain fresh explicit approval before setting `ANSIBLE_APPLY_ENABLED=true`.

Until then, the existing manual audit is the only enabled GitHub-hosted operation.
