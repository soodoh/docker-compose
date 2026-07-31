# Tailscale management-plane bootstrap plan

## Status

Phase 4a gateway routing is operational, but direct Docker Phase 4b remains **plan-only**. No Docker-host Tailscale
package, service, interface, user, sudo policy, SSH setting, firewall rule, or inventory endpoint has been changed.

Selected dual-path design:

- Use hosted Tailscale with a separate unprivileged Proxmox LXC subnet router as the provisioning/recovery path.
- Keep direct Tailscale SSH on this Docker VM as the normal Ansible path.
- Require the gateway to route only Proxmox `192.168.0.123/32` and Docker `192.168.0.100/32` before this bootstrap.
- Enroll with a short-lived, preauthorized, one-use auth key supplied through controller-only `TAILSCALE_AUTH_KEY`.
- Advertise the persistent Docker host as `docker-host` with `tag:docker-host`.
- Do not accept Tailscale DNS or advertised routes during initial Docker bootstrap.
- Enable Tailscale SSH while leaving the existing OpenSSH service and LAN path untouched.
- Create locked `ansible-deploy` with no supplementary groups and specifically no `docker` group.
- Grant `ansible-deploy` passwordless sudo for unattended Ansible, restricted by tailnet SSH policy, protected GitHub
  environments, and later CI concurrency controls.

`tailscaled` can manage its own networking rules when started. The playbook contains no firewall module or firewall
command, but its effective networking changes must still be inspected after bootstrap.

## Current read-only baseline

- `tailscale` is not installed and `tailscaled.service` does not exist.
- `tailscale0` does not exist.
- `ansible-deploy` does not exist.
- sudo and OpenSSH are installed.
- sshd is enabled, active, and listening on port 22.
- The LAN default route remains available.
- Proxmox-to-Docker LAN SSH is open and a fresh `qm terminal 100` serial login was verified.
- The gateway routes exactly `192.168.0.123/32` and `192.168.0.100/32`; PVE API and Docker SSH tests passed.

## Tailnet prerequisites

Completed prerequisites:

1. Protected unprivileged `tag:infra-router` CT 101 is healthy and independently recoverable.
2. Only `192.168.0.123/32` and `192.168.0.100/32` are advertised and approved.
3. Routed PVE TCP/8006 and Docker TCP/22 work; unapproved PVE TCP/22 is denied.
4. `tag:docker-host`, `tag:ci`, least-privilege grants, and Tailscale SSH rules are saved and validated.
5. Fresh LAN SSH and Proxmox serial-console recovery were reconfirmed after gateway activation.

The remaining external prerequisite is a short-lived, preauthorized, one-use, non-ephemeral auth key scoped only to
`tag:docker-host`. Create it immediately before an explicitly approved apply.

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

The refreshed hardened check completed with `ok=10 changed=2 failed=0 skipped=18`. It proposed only creating
`ansible-deploy` and installing `tailscale` `1.98.10-1`. Pacman simulation proposes that single 11.61 MiB package,
zero dependencies/upgrades/removals, and 48.42 MiB installed size. Check mode skips service start, sudoers, temporary
auth-key handling, enrollment, and Tailscale SSH.

## Apply gate—not authorized

A future normal Docker bootstrap requires all of the following:

- Explicit approval of the exact check-mode output.
- A successful fresh LAN SSH login and tested `qm terminal 100` serial login; both are complete.
- Healthy `tag:infra-router` routing with only the two approved `/32` routes; complete.
- Verified routed PVE API, Docker LAN SSH, and denied PVE SSH behavior; complete.
- Validated tailnet network/Tailscale SSH policy; complete.
- A newly created one-use Docker auth key available only in the local shell environment.
- Confirmation that the package transaction remains exactly `tailscale` `1.98.10-1`; complete.

The guarded invocation will be:

```sh
cd /home/docker/Projects/docker-compose/ansible
bash
read -rsp 'One-use Tailscale auth key: ' TAILSCALE_AUTH_KEY
printf '\n'
export TAILSCALE_AUTH_KEY
ansible-playbook playbooks/bootstrap.yml \
  --tags management_plane \
  -e iac_apply_confirmed=true \
  -e iac_apply_tag=management_plane \
  -e lan_ssh_recovery_confirmed=true \
  -e proxmox_console_recovery_confirmed=true \
  -e tailscale_gateway_recovery_confirmed=true \
  -e tailscale_ssh_policy_confirmed=true
unset TAILSCALE_AUTH_KEY
exit
```

Do not run this command until separately authorized. The role writes the key to a root-only temporary `/run` file,
uses Tailscale's `file:` auth-key syntax, guarantees cleanup, and marks all key-handling tasks `no_log`. The key is
never placed in command arguments, inventory, variables files, facts, diffs, or repository files.

## Mandatory post-bootstrap verification

Keep the original LAN SSH session open throughout verification:

1. Confirm `tailscaled.service` is enabled and active.
2. Confirm `tailscale status` reports Running and record only redacted evidence.
3. Confirm the host has the expected tailnet tag and stable MagicDNS name/IP.
4. From an existing approved tailnet device, connect with Tailscale SSH as `ansible-deploy`.
5. Confirm no `/run/tailscale-auth-*` file remains.
6. Confirm `id -nG ansible-deploy` does not contain `docker`.
7. As `ansible-deploy`, confirm `sudo -n true` succeeds.
8. Open a fresh LAN OpenSSH session through the existing LAN address.
9. Reconfirm Proxmox console login.
10. Reconfirm the gateway route reaches PVE API and Docker LAN SSH with documented restrictions.
11. Recheck 41 running Compose services, 33 project volumes, mounts, devices, health, Docker, cronie, and sshd.
12. Update the audit's management-plane baseline from Tailscale-absent to the verified installed/running state.
13. Run `audit.yml --check --diff` locally and require `changed=0`.
14. Run `site.yml --check --diff` locally and require `changed=0`.
15. Only then replace the `.invalid` production endpoint and test a remote read-only audit.

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
