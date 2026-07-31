# Ansible migration plan

## Current scope and stop point

Phases 1 and 2 are complete. Phase 3 desired-state roles and the apply guard are implemented for check-mode
validation only. No normal Ansible apply or host convergence has been authorized or run. Stop after presenting the
complete Phase 3 `--check --diff` result.

The target execution path remains:

```text
protected main
  -> ephemeral GitHub-hosted runner
  -> Tailscale workload identity
  -> SSH to Docker VM
  -> Ansible
  -> existing Docker Compose project
```

Tailscale will be a host-level `tailscaled.service`. Tailscale, SSH, firewall, mount, upgrade, and reboot work is a
separate management plane and must be excluded from routine application deployments.

## Re-inspected baseline

Read-only inspection on 2026-07-30 confirmed:

- Arch Linux is running `7.1.3-arch1-3`; `linux` and `linux-headers` `7.1.5.arch1-2` are installed.
- Docker package/client is `29.6.2`; the running daemon reports `29.6.1`.
- Docker Compose is `5.3.1` and `docker compose config --quiet` succeeds.
- Docker, cronie, and sshd are enabled and active. Tailscale is absent.
- All 41 declared Compose services are running; Gluetun and Seerr remain unhealthy.
- Compose declares 30 volumes. The Docker project owns 33 named volumes when the three legacy volumes are
  included.
- `happier-data`, `nzbget-data`, and `nzbhydra2-data` exist under their `docker-compose_` engine names.
- All 29 unique bind sources and all 8 unique device sources used by running containers exist.
- `/mnt/storage` is mounted as NFSv4 and `/mnt/games` is mounted as ext4. Their exact current fstab lines were
  read and are represented as assertions only.
- uinput, uhid, gasket, and apex are loaded. Coral, AMD GPU, serial, TUN, and virtual-input device paths exist.
- Gasket DKMS is installed for the deferred `7.1.5-arch1-2` kernel.
- All seven tracked Wolf host-file pairs still match byte for byte.
- `.env` remains mode `0644`, owned by `docker:docker`, within the mode `0700` `/home/docker` directory. Its
  contents were not read or printed.
- Five encrypted local backup files were observed; the newest had an mtime of 2026-07-30T06:38:34-07:00.
  Restore testing and remote-backup verification remain outstanding.
- Root's crontab exists as a mode `0600` root-owned file, but its contents remain uninspected without privilege.
- All eleven services sharing Gluetun's network namespace still have config-hash differences while their current
  containers remain running against the current Gluetun namespace.
- `docker compose --dry-run create --no-build` completed successfully and proposed no creates or recreates.

The only newly explicit discrepancy from the supplied baseline is the running Docker daemon at `29.6.1` while
the installed package and client are `29.6.2`. This is consistent with a package update whose daemon has not been
restarted. It is non-blocking for Phase 3 check mode, but blocks Docker apply until investigated. No Docker restart
is authorized.

## Safety invariants

Until an approved later phase changes them:

- Never run an ordinary Ansible apply.
- Never run `docker compose up`, `down`, `pull`, `restart`, or recreate operations.
- Never use `docker compose down -v` or `--remove-orphans`.
- Never delete, rename, prune, or recreate Docker volumes.
- Never read, copy, template, or print `.env` values.
- Never run `pacman -Syu`, upgrade packages, reboot, or restart Docker.
- Never manage fstab, mounts, root cron, SSH, firewall, Tailscale, or filesystems from a routine deployment.
- Never expose SSH publicly or put the future deployment user in the `docker` group.
- Never automatically roll back a stateful service.
- Never commit secrets, host facts containing secrets, unredacted diffs, or CI artifacts containing secrets.

The `site.yml` playbook imports `apply_guard` with the `always` tag before any role. Check mode needs no confirmation.
Every normal run is refused unless it supplies both:

```sh
-e iac_apply_confirmed=true -e iac_apply_tag=<approved-tag>
```

The value of `iac_apply_tag` must match the single tag selected with `--tags`. Broad or untagged normal runs are
refused. This is an additional safeguard; it does not itself authorize an apply.

Routine roles contain no Tailscale, SSH, firewall, mount, filesystem, upgrade, or reboot management. The Tailscale
and deployment-user roles remain absent until Phase 4. There is no `management_plane` task in `site.yml`.

## Phase 1 audit scaffold

The audit uses only ansible-core built-ins. It gathers ordinary facts, performs metadata/stat inspections, runs
read-only CLI probes, and makes assertions. Every `command` task declares `changed_when: false`. Read-only command
probes execute during `--check`, so both ordinary audit and check-mode audit must finish with `changed=0`. There are
no handlers or Docker mutations.

Local inventory uses `ansible_connection: local`. The production inventory is deliberately pointed at a `.invalid`
placeholder until Tailscale and the deployment user are separately approved and verified.

The operator separately installed `ansible` `14.2.0-1` (`ansible-core` `2.21.2`) using the previously approved
bootstrap command and reported that the audit completed with `changed=0`.

## Phase 3 desired-state check

`playbooks/site.yml` now models only the approved current state:

- `host_files` uses `copy` for the seven matching Wolf files with adopted ownership and modes; it has no handlers.
- `base` keeps only cronie present, enabled, and started using `state: present`/`state: started` without upgrades or
  restarts.
- `maintenance` asserts the deferred kernel state and root-cron metadata. It cannot read or manage root cron.
- `storage` asserts exact fstab lines and active mounts. It contains no file or mount module.
- `hardware` audits required modules, devices, and Gasket DKMS. It does not automate the patched AUR package.
- `docker` keeps Docker packages present and the service started/enabled without restart, image pull, or upgrade.
  The recorded client/daemon mismatch remains an assertion and an apply blocker.
- `compose` performs only config, count, legacy-volume, and dry-run-create preflight checks. It never runs Compose
  up/down/pull/restart, removes orphans, or changes volumes.
- `health` verifies 41 services remain running and reports Gluetun and Seerr as unresolved blockers.

Package, service, and copy tasks elevate only during a separately guarded normal run; check mode is unprivileged.
Run the complete Phase 3 plan with:

```sh
cd /home/docker/Projects/docker-compose/ansible
ansible-playbook --syntax-check playbooks/site.yml
ansible-playbook playbooks/site.yml --check --diff
```

Validation completed with `ok=33 changed=0 failed=0`; the follow-up audit completed with `ok=45 changed=0 failed=0`. Do not run `site.yml` without `--check`; no apply is authorized.

## Phase 4 management-plane plan

`playbooks/bootstrap.yml` now models the separately tagged `management_plane` bootstrap without authorizing it.
The selected design uses a one-use preauthorized key, Tailscale SSH, and a locked `ansible-deploy` user with
passwordless sudo but no docker-group membership. Check mode never starts tailscaled, consumes the key, enrolls,
enables Tailscale SSH, or writes the root-only sudoers file.

The bootstrap requires local inventory, the existing apply confirmation, exactly the `management_plane` tag, and
explicit confirmations for LAN SSH, Proxmox console, and tailnet SSH policy recovery gates. `site.yml` contains no
management-plane tasks, so routine checks and future deployments exclude these changes by construction.

The complete plan, tailnet policy prerequisites, guarded command, verification procedure, and manual rollback gates
are in [`tailscale-bootstrap.md`](./tailscale-bootstrap.md). Check mode reported `changed=2` for only the absent deployment user and Tailscale package; routine `site.yml` and `audit.yml` remained `changed=0`. No Phase 4 apply is authorized.
## Recovery work still required

A manual restore drill is mandatory before any stateful Compose adoption or apply. It must be separately planned
and approved, and must not touch production volumes. At minimum:

1. Verify the decryption key is available from its recovery location outside Git and CI.
2. Select a recent local encrypted backup and independently verify the corresponding remote object exists.
3. Restore into an isolated disposable destination, never over a production volume or bind directory.
4. Verify archive integrity, expected ownership/modes, and application-level readability for at least one stateful
   service.
5. Record recovery time, commands, evidence, and cleanup steps; obtain approval before cleanup.
6. Verify Proxmox console access and the existing LAN SSH path remain available as recovery paths.

The audit proves only that encrypted local backup files exist. It does not prove decryptability, restorability,
remote retention, or application consistency.

## Deferred phase gates

1. **Phase 4 stop:** review `bootstrap.yml --check --diff`, tailnet policy, LAN SSH, and Proxmox recovery evidence;
   do not run the documented normal bootstrap without a new explicit approval.
2. **Phase 5:** after a verified Phase 4 bootstrap, add plan-only CI with SHA-pinned actions, workload identity,
   minimal permissions, redaction, and serialization. Require three stable plan-only runs.
4. **Phase 6:** converge one approved tag at a time in the order `host_files`, `base`, `maintenance`, `storage`,
   `docker`, with plan, approval, guarded apply, second zero-change check, and runtime re-audit for each.
5. **Phases 7-8:** retain this Compose directory and host-only `.env`; resolve or waive health blockers before a
   canary and stateful-last Compose adoption. Never pull automatically or remove orphans.
6. **Phase 9:** only then consider protected-main apply using GitHub Environment approval, exact-plan SHA,
   concurrency, a host lock, redacted evidence, and default management-plane exclusion.

OpenTofu and Proxmox VM import remain deferred until the Docker host has converged.
