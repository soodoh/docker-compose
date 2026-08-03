# Protected Ansible deployment pipeline

## Current status

[`.github/workflows/ansible-deploy.yml`](../.github/workflows/ansible-deploy.yml) automatically plans eligible
same-repository pull requests and pushes to `main`. Merging the required pull request is the explicit approval for a
changed merged-commit plan to continue through guarded apply; there is no second environment-review click.

The live repository gates after this workflow change is merged and activated are:

```text
ANSIBLE_AUTO_PLAN_ENABLED=true
ANSIBLE_APPLY_ENABLED=true
```

During rollout, `ANSIBLE_APPLY_ENABLED` stays `false` until the workflow change reaches protected `main`; changing the
variable afterward does not itself dispatch a run or mutate the host.

Three manual plan-only stability runs (`30688128628`, `30688167935`, and `30688201566`) produced identical normalized
plan output for `host_files`, each with `ok=3 changed=0 unreachable=0 failed=0`. Each ephemeral controller cleaned up,
and no `tag:ci-plan` or `tag:ci-apply` peer remained.

The first protected bootstrap check ([`30676568592`](https://github.com/soodoh/docker-compose/actions/runs/30676568592))
proved the `infrastructure-apply` OIDC exchange and ephemeral `tag:ci-apply` enrollment, then stopped before ping, SSH,
or Ansible because the shared route assertion saw only `192.168.0.123/32`. Cleanup succeeded. Deployment controllers
now disable accepted subnet routes immediately after enrollment and require zero non-tailnet IPv4 or IPv6 routes before host contact;
the manual audit retains its separately approved two-route behavior.

The approved bootstrap apply ([`30677520382`](https://github.com/soodoh/docker-compose/actions/runs/30677520382))
completed with `ok=16 changed=3 unreachable=0 failed=0`. Its immediate check reported `changed=0`, and unprivileged
`ansible-plan` connectivity succeeded. The job was marked failed only because the boundary audit used sudo's runas-user
option instead of the other-user option when listing effective policy. The audit command was corrected; no rollback or
repeat host change is required.

Final protected verification run `30686478000` then reported zero changes in its initial check, guarded convergence,
immediate post-check, and privilege-boundary audit. The audit completed with `ok=10 changed=0 unreachable=0 failed=0`,
and unprivileged `ansible-plan` connectivity succeeded.

## Separate trust paths

Ansible check mode is not a security boundary: repository-controlled tasks can disable check mode or execute arbitrary
commands. Automatic plans therefore must not use the passwordless-root `ansible-deploy` identity.

| Purpose | GitHub environment | Tailscale tag | Host user | Privilege |
|---|---|---|---|---|
| Manual audit | `infrastructure-plan` | `tag:ci` | `ansible-deploy` | Existing passwordless sudo; manual dispatch only |
| Automatic plan | `infrastructure-auto-plan` | `tag:ci-plan` | `ansible-plan` | No general sudo and no supplementary groups |
| Merge-approved apply | `infrastructure-apply` | `tag:ci-apply` | `ansible-deploy` | Existing passwordless sudo after a required PR merge |

The plan account's only sudo rule is the exact no-argument helper below:

```text
/usr/local/sbin/iac-read-docker-version
```

The root-owned helper accepts no arguments and runs one fixed read-only Docker version query. The plan account is not in
the Docker group. [`ansible/playbooks/plan-controller.yml`](../ansible/playbooks/plan-controller.yml) created the locked
account, validated sudoers file, and helper through the approved `management_plane` apply.

The pre-apply check reported `ok=6 changed=1 unreachable=0 failed=0`; the apply converged three changes, and the immediate
post-check reported `changed=0`. The user now has only its private primary group, and the tracked helper checksum matches
the installed root-owned file.

The completed one-time `plan-controller-bootstrap.yml` workflow was retired after final zero-change verification. The
tracked `plan-controller.yml`, privilege-boundary audit, roles, and rollback record remain available for a future reviewed
management-plane procedure, but no standing GitHub workflow can invoke that bootstrap apply.

## Trigger and intent

An eligible same-repository pull request to `main` automatically runs the unprivileged plan; draft and fork pull requests
cannot contact the host. The pull-request plan is a preview and can never apply. Merging through the protected branch
creates a `main` push, which replans the exact merged commit and may apply if that merged-commit plan reports changes. A
manual `workflow_dispatch` remains plan-only.

[`ansible/deploy-intent.yml`](../ansible/deploy-intent.yml) must contain exactly one allowlisted automation tag:

```yaml
tag: host_files
```

The automation allowlist is `host_files`, `base`, `maintenance`, `storage`, and `docker`. `compose`, `hardware`, `health`,
and `management_plane` are excluded. Compose adoption remains blocked by restore, remote-backup, and separately approved cutover gates.
Management-plane work remains a separate bootstrap procedure.

## Automatic plan

The plan job uses `infrastructure-auto-plan`, its exact GitHub OIDC subject, `tag:ci-plan`, and
[`inventory/production-plan.yml`](../ansible/inventory/production-plan.yml). It:

1. Checks out the triggering commit without persisted Git credentials.
2. Validates the single reviewed intent tag.
3. Installs pinned Python 3.13.14 and the complete hash-locked controller environment from `.github/requirements-ansible-controller.lock`.
4. Creates an ephemeral `tag:ci-plan` Tailscale node without reusable credentials.
5. Disables accepted subnet routes, tailnet DNS, and Tailscale SSH before host contact, then requires no non-tailnet IPv4 or IPv6 routes.
6. Requires the recorded Docker ED25519 host-key fingerprint.
7. Connects only as unprivileged `ansible-plan` and validates inventory, connectivity, and `site.yml` syntax.
8. Runs `site.yml --check --diff` for the selected tag.
9. Parses the one-host recap, records the changed count, and hashes the complete plan output.

The pull-request preview hash is not reused after merge. The protected `main` push independently plans and hashes the
exact merged commit; branch protection makes the merge action the approval for that resulting plan.

The `host_files` role suppresses content diffs so unexpected host file contents cannot enter this public repository's
workflow logs. Reviewers use the task/item paths in the plan together with the reviewed source changes. No role may add
a secret-bearing path or unsuppressed sensitive diff to the automation allowlist.

A zero-change plan skips apply. GitHub concurrency keeps one production workflow active, but GitHub may replace an older
pending plan with a newer commit; the apply job separately refuses a commit that is no longer the tip of `main`.

## Protected apply

A changed plan can reach the apply job only when all of these conditions hold:

- The event is a push to `main` created through the required pull-request merge path, not a pull request or manual dispatch.
- `ANSIBLE_APPLY_ENABLED` is exactly `true`.
- The merged-commit plan completed successfully and reported at least one change.
- GitHub allows the exact `main` commit to deploy to `infrastructure-apply`.

`infrastructure-apply` is restricted to `main`, has no deployment reviewer, and disallows administrator bypass. The
repository's no-bypass pull-request rule is the human gate. With one collaborator, the author can merge their own pull
request; this is an explicitly accepted single-operator trust model.

After the merge-triggered plan, the apply job:

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
7. Acquires persistent `/var/lib/iac-ansible-production.lock` before any normal `site.yml` convergence and releases it
   only after successful role completion. A concurrent, failed, or abandoned apply fails closed across reboot; a stale
   lock requires manual inspection and separately approved removal.

The workflow never performs an automatic rollback.

## GitHub protections

The default-branch ruleset requires every change to reach `main` through a pull request. It has no bypass actors and
retains deletion and non-fast-forward protection. Because `soodoh` is the only collaborator, the rule requires zero
review approvals; deliberately merging the pull request is the apply approval. The `infrastructure-apply` environment
adds main-only deployment restriction and disabled administrator bypass, but no second reviewer gate.

The manual audit and deployment workflow share the `ansible-production` concurrency group with cancellation disabled.
Normal `site.yml` runs also use the persistent host-side `/var/lib/iac-ansible-production.lock` advisory lock,
coordinating repository applies across GitHub and non-GitHub operators. Check mode never creates the lock. Successful
convergence removes it; failure or cancellation intentionally leaves the root-owned lock directory for manual
investigation. The owner record is best-effort because interruption can occur between atomic directory creation and
metadata recording.

## Activation status

The plan identity, route restrictions, OIDC identities, environment-bound tags, zero-change bootstrap verification,
three stable plans, hash-locked controller, host lock, and zero-change full remote audit are complete. Automatic PR plans
and merge-triggered applies are enabled.

A pull request is allowed to contact the unprivileged plan identity only when its head branch belongs to this repository.
Fork and draft pull requests skip the job. A merge never bypasses the current-main check, merged-commit replan/hash,
one-tag guard, persistent host lock, zero-change post-check, or complete audit.

`compose`, `hardware`, `health`, and `management_plane` remain outside automatic apply regardless of activation. Set
`ANSIBLE_APPLY_ENABLED=false` as the emergency stop for future merge-triggered convergence.
