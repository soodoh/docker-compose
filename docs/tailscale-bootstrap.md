# Tailscale management-plane bootstrap plan

## Status

This is a **plan-only Phase 4 artifact**. It does not authorize a normal Ansible run. No Tailscale package, service,
network interface, user, sudo policy, SSH setting, firewall rule, or inventory endpoint has been changed.

Selected design:

- Enroll with a short-lived, preauthorized, one-use auth key supplied through the controller-only
  `TAILSCALE_AUTH_KEY` environment variable.
- Advertise the persistent host as `docker-host` with `tag:docker-host`.
- Do not accept Tailscale DNS or advertised routes during initial bootstrap.
- Enable Tailscale SSH while leaving the existing OpenSSH service and LAN path untouched.
- Create the locked-password `ansible-deploy` user with no supplementary groups and specifically no `docker` group.
- Grant `ansible-deploy` passwordless sudo for unattended Ansible. Restrict who can reach that account through the
  tailnet SSH policy, protected GitHub environments, and later CI concurrency controls.

`tailscaled` can manage its own networking rules when started. The playbook contains no firewall module or firewall
command, but its effective networking changes must still be inspected after bootstrap.

## Current read-only baseline

- `tailscale` is not installed and `tailscaled.service` does not exist.
- `tailscale0` does not exist.
- `ansible-deploy` does not exist.
- sudo and OpenSSH are installed.
- sshd is enabled, active, and listening on port 22.
- The LAN default route remains available.
- Proxmox console recovery has not been verified from inside the guest and requires a manual test.

## Tailnet prerequisites

Complete these in the Tailscale admin console before authorizing bootstrap:

1. Create or confirm `tag:docker-host` and reserve `tag:ci` for the future GitHub workload identity.
2. Create a short-lived, preauthorized, **one-use** auth key authorized for `tag:docker-host`.
3. Add network access permitting the approved administrator identities and future `tag:ci` clients to reach TCP/22
   on `tag:docker-host`.
4. Add a Tailscale SSH rule allowing only approved sources to connect as `ansible-deploy`. Automation requires an
   `accept` rule rather than an interactive check rule.
5. Validate the policy in the Tailscale policy editor before setting `tailscale_ssh_policy_confirmed=true`.

Conceptual policy fragment—merge it into the existing policy rather than replacing the policy wholesale:

```json
{
  "tagOwners": {
    "tag:docker-host": ["autogroup:admin"],
    "tag:ci": ["autogroup:admin"]
  },
  "grants": [
    {
      "src": ["tag:ci"],
      "dst": ["tag:docker-host"],
      "ip": ["tcp:22"]
    }
  ],
  "ssh": [
    {
      "action": "accept",
      "src": ["tag:ci"],
      "dst": ["tag:docker-host"],
      "users": ["ansible-deploy"]
    }
  ]
}
```

Add a separately reviewed human-administrator rule for initial testing and recovery. Do not grant `tag:ci` root SSH
or access to unrelated tailnet nodes.

Official references:

- <https://tailscale.com/docs/install/arch>
- <https://tailscale.com/docs/features/tailscale-ssh>
- <https://tailscale.com/docs/how-to/connect-ssh-linux-vm>
- <https://tailscale.com/docs/features/workload-identity-federation>

## Check-mode plan

This command is read-only and does not require an auth key:

```sh
cd /home/docker/Projects/docker-compose/ansible
ansible-playbook --syntax-check playbooks/bootstrap.yml
ansible-playbook playbooks/bootstrap.yml --check --diff --tags management_plane
```

The check completed with `ok=10 changed=2 failed=0 skipped=14`. It proposed only creating
`ansible-deploy` and installing `tailscale` `1.98.10-1`. It intentionally skipped starting tailscaled, installing
the root-only sudoers file, consuming an auth key, enrolling, and enabling Tailscale SSH because those operations
cannot be safely simulated unprivileged.

## Apply gate—not authorized

A future normal bootstrap requires all of the following:

- Explicit approval of the exact check-mode output.
- A successful second LAN SSH login while the original session remains open.
- A tested Proxmox console login to this VM.
- A validated tailnet network/SSH policy.
- The one-use auth key available only in the local shell environment.
- Confirmation that no package upgrade or unrelated package transaction is proposed.

The guarded invocation will be:

```sh
cd /home/docker/Projects/docker-compose/ansible
read -rsp 'One-use Tailscale auth key: ' TAILSCALE_AUTH_KEY
printf '\n'
export TAILSCALE_AUTH_KEY
ansible-playbook playbooks/bootstrap.yml \
  --tags management_plane \
  -e iac_apply_confirmed=true \
  -e iac_apply_tag=management_plane \
  -e lan_ssh_recovery_confirmed=true \
  -e proxmox_console_recovery_confirmed=true \
  -e tailscale_ssh_policy_confirmed=true
unset TAILSCALE_AUTH_KEY
```

Do not run this command until separately authorized. The auth-key assertion and enrollment task use `no_log`; the
key is not stored in inventory, group variables, facts, diffs, or repository files.

## Mandatory post-bootstrap verification

Keep the original LAN SSH session open throughout verification:

1. Confirm `tailscaled.service` is enabled and active.
2. Confirm `tailscale status` reports Running and record only redacted evidence.
3. Confirm the host has the expected tailnet tag and stable MagicDNS name/IP.
4. From an existing approved tailnet device, connect with Tailscale SSH as `ansible-deploy`.
5. Confirm `id -nG ansible-deploy` does not contain `docker`.
6. As `ansible-deploy`, confirm `sudo -n true` succeeds.
7. Open a fresh LAN OpenSSH session through the existing LAN address.
8. Reconfirm Proxmox console login.
9. Recheck 41 running Compose services, 33 project volumes, mounts, devices, health, Docker, cronie, and sshd.
10. Run `audit.yml --check --diff` locally and require `changed=0`.
11. Run `site.yml --check --diff` locally and require `changed=0`.
12. Only then replace the `.invalid` production inventory endpoint and test a remote read-only audit.

## Failure and rollback policy

There is no automatic rollback:

- If Tailscale enrollment or SSH verification fails, retain the LAN SSH session and use the Proxmox console.
- Do not stop or reconfigure OpenSSH.
- Do not change firewall policy automatically.
- Do not remove `ansible-deploy` or its sudoers file until another recovery path is confirmed.
- `tailscale down`, disabling tailscaled, package removal, user removal, and sudoers removal each require explicit
  approval and a fresh plan.
- Never restart Docker, recreate containers, prune volumes, or touch `.env` while diagnosing management-plane
  bootstrap failures.
