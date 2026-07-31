# GitHub Actions remote Ansible audit

## Status

This phase adds a **manual, read-only** GitHub-hosted controller. It does not authorize `site.yml`, a normal Ansible
run, package changes, Docker lifecycle operations, or infrastructure apply. The first workflow must only run
`audit.yml --check --diff` through direct Tailscale SSH.

## Trust boundaries

The public repository is `soodoh/docker-compose`, with default branch `main`. Its current GitHub OIDC configuration
uses the default mutable-name subject format. The Tailscale federated identity therefore trusts exactly:

```text
Issuer:  https://token.actions.githubusercontent.com
Subject: repo:soodoh/docker-compose:environment:infrastructure-plan
Scope:   auth_keys
Tag:     tag:ci
```

The GitHub environment `infrastructure-plan` has a custom deployment-branch policy allowing only `main`. It contains
two non-secret environment variables:

```text
TS_OAUTH_CLIENT_ID
TS_AUDIENCE
```

There is no OAuth secret and no reusable auth key. The workflow is `workflow_dispatch` only, uses a GitHub-hosted
runner, and requests only `contents: read` and `id-token: write`. The Tailscale action exchanges the GitHub OIDC token
for a short-lived credential and creates an ephemeral `tag:ci` node that is removed after the job.

Tailnet policy limits `tag:ci` to Docker TCP/22 and Tailscale SSH as `ansible-deploy`. The deployment user is outside
the Docker group and reaches privileged read-only audit commands only through its separately validated passwordless
sudo policy.

## Workflow behavior

[`.github/workflows/ansible-plan.yml`](../.github/workflows/ansible-plan.yml):

1. Checks out the repository with an action pinned to a full commit SHA.
2. Installs Python 3.13 and `ansible-core==2.21.2` on the ephemeral runner.
3. Connects with `tailscale/github-action` pinned to the audited v4 commit and Tailscale 1.98.10 tarball checksum.
4. Accepts no DNS or routes and does not enable Tailscale SSH on the runner.
5. Waits for connectivity to Docker's stable Tailscale IP `100.111.210.72`.
6. Scans the Docker SSH host key only after joining the authenticated tailnet path, then leaves Ansible host-key
   checking enabled.
7. Validates production inventory and audit syntax.
8. Runs an Ansible ping and `audit.yml --check --diff` only.

The production inventory uses the stable Tailscale IP and `ansible-deploy`; it contains no password, private key,
auth key, OAuth secret, or Tailscale API token.

## Activation gate

The first approved dispatch (`30669410045`) failed during binary verification before OIDC exchange or tailnet
connection because the pinned checksum contained one extra trailing character. The action's post step completed; no CI
node was created and the Docker host was not contacted. The corrected value is the official 64-character checksum.

Before a retry:

1. Review, commit, and push the one-character checksum correction.
2. Manually dispatch `Ansible remote audit` from `main` under a fresh approval.
3. Confirm the Tailscale admin console shows one ephemeral `tag:ci` node and no broader access.
4. Require the remote recap to report `changed=0`, `failed=0`, and `unreachable=0`.
5. Confirm the ephemeral node disappears after job cleanup.

Do not add push, pull-request, schedule, `workflow_call`, or apply triggers during this gate. Future apply automation must
use a separate protected environment, concurrency policy, explicit human approval, and a separately reviewed workflow.

## Failure policy

If OIDC exchange, Tailscale connectivity, host-key scan, SSH, become, or audit fails, stop. Do not disable host-key
checking, broaden the OIDC subject, widen the `tag:ci` grant, add a static secret, or run a normal Ansible playbook as a
workaround. The Docker host remains managed through the already verified Mac, LAN, gateway, and serial paths.
