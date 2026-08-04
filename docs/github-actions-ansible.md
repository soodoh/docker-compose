# Retired GitHub Actions remote Ansible audit

## Status

This document is the historical activation and verification record for the retired privileged manual-audit path. The
standalone `ansible-audit.yml` workflow and its `tag:ci` identity are no longer active. Manual plan-only dispatch remains
available through the unprivileged deployment workflow documented in
[`github-actions-deploy.md`](./github-actions-deploy.md).

## Trust boundaries

During activation, the public repository used its former `soodoh/docker-compose` name and the default mutable-name
GitHub OIDC subject format. The now-retired Tailscale federated identity trusted exactly:

```text
Issuer:  https://token.actions.githubusercontent.com
Subject: repo:soodoh/docker-compose:environment:infrastructure-plan
Scope:   auth_keys
Tag:     tag:ci
```

The former GitHub environment `infrastructure-plan` had a custom deployment-branch policy allowing only `main` and
contained two non-secret environment variables:

```text
TS_OAUTH_CLIENT_ID
TS_AUDIENCE
```

There was no OAuth secret or reusable auth key. The workflow was `workflow_dispatch` only, used a GitHub-hosted runner,
and requested only `contents: read` and `id-token: write`. The Tailscale action exchanged the GitHub OIDC token for a
short-lived credential and created an ephemeral `tag:ci` node that was removed after the job.

Tailnet policy limited `tag:ci` to direct Docker TCP/22, the two approved routed destinations (Docker TCP/22 and Proxmox
TCP/8006), and Tailscale SSH to Docker as `ansible-deploy`. The deployment user was outside the Docker group and reached
privileged read-only audit commands only through its separately validated passwordless sudo policy.

## Workflow behavior

The retired workflow performed these steps:

1. Checks out the repository with an action pinned to a full commit SHA.
2. Installs pinned Python 3.13 and the complete hash-locked Ansible controller environment.
3. Connects with `tailscale/github-action` pinned to the audited v4 commit and Tailscale 1.98.10 tarball checksum.
4. Disables tailnet DNS and Tailscale SSH on the runner. The upstream action requires route acceptance, so the next step
   fails closed unless routing table 52 contains exactly the two approved subnet routes, `192.168.0.100/32` and
   `192.168.0.123/32`, plus only normal IPv4 and IPv6 tailnet routes.
5. Waits for direct or authenticated DERP connectivity to Docker's stable Tailscale IP `100.111.210.72`.
6. Scans the Docker SSH host key only after joining the authenticated tailnet path, then leaves Ansible host-key
   checking enabled.
7. Validates production inventory and audit syntax.
8. Runs an Ansible ping and `audit.yml --check --diff` only.

The production inventory uses the stable Tailscale IP and `ansible-deploy`; it contains no password, private key,
auth key, OAuth secret, or Tailscale API token.

## Activation result

The first approved dispatch (`30669410045`) failed during binary verification before OIDC exchange or tailnet
connection because the pinned checksum contained one extra trailing character. The action's post step completed; no CI
node was created and the Docker host was not contacted. The corrected value is the official 64-character checksum.

The second approved dispatch (`30670221912`) verified the checksum and reached the pinned action, but `tailscale up`
rejected duplicate route flags: v4 always adds `--accept-routes`, while this workflow also requested
`--accept-routes=false`. Argument parsing failed before the runner joined the tailnet or contacted Docker, and the post
step completed successfully.

The approved resolution keeps the pinned upstream action. The ephemeral runner may accept only the two tailnet-approved
`/32` subnet routes. An immediate fail-closed check verifies those exact non-tailnet routes, tailnet DNS disabled, and
Tailscale SSH disabled before host-key scanning, SSH, or Ansible can run. Tailnet policy authorizes `tag:ci` only for the
two scoped routed services and direct Docker SSH required by this manual audit path.

The third approved dispatch (`30670878456`) joined the tailnet, passed the exact route and runner-preference assertions,
and received authenticated pongs from Docker through `DERP(lax)`. The custom probe nevertheless failed because
`tailscale ping` defaults to requiring a direct path. No host-key scan, SSH, or Ansible command ran. The action's post
step logged out successfully and stopped Tailscale. The corrected probe explicitly accepts either a direct path or DERP,
matching the pinned action's connectivity semantics.

The fourth approved dispatch ([`30671079353`](https://github.com/soodoh/home-lab/actions/runs/30671079353))
completed successfully from commit `72c9317`:

- The ephemeral OIDC-authenticated `tag:ci` runner joined the tailnet.
- Tailnet DNS and Tailscale SSH were disabled on the runner.
- Routing table 52 contained exactly `192.168.0.100/32` and `192.168.0.123/32` outside `100.64.0.0/10`.
- Docker answered through authenticated `DERP(lax)` connectivity.
- The scanned Docker ED25519 fingerprint was
  `SHA256:2wHl3xsBkNYprqP99usjZdwj2Rytcc+MtJVErhowVYw`.
- Remote Ansible connectivity succeeded.
- The read-only check-mode audit reported `ok=45 changed=0 unreachable=0 failed=0`.
- The post step logged out and stopped Tailscale successfully; a subsequent live tailnet view from Docker showed zero
  `tag:ci` peers.

The restored manual-audit identity and current access policy were reverified by run
[`30708870726`](https://github.com/soodoh/home-lab/actions/runs/30708870726), again reporting
`ok=45 changed=0 unreachable=0 failed=0` with exact routes, verified host key, and successful cleanup.

The manual read-only activation gate completed successfully. The standalone workflow was later retired when the plan
identity was consolidated under `infrastructure-plan`; normal protected applies continue to run the complete privileged
audit after convergence.

## Failure policy

If OIDC exchange, Tailscale connectivity, host-key scan, SSH, become, or audit fails, stop. Do not disable host-key
checking, broaden the OIDC subject, widen the `tag:ci` grant, add a static secret, or run a normal Ansible playbook as a
workaround. The Docker host remains managed through the already verified Mac, LAN, gateway, and serial paths.
