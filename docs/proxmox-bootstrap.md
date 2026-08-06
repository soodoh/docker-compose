# Proxmox local bootstrap

This is the only host bootstrap that must be launched locally. Keep physical console access and a tested LAN root session open throughout it. Do not run the playbook remotely.

On the Proxmox host, after the reviewed commit is merged:

```sh
git clone https://github.com/soodoh/home-lab.git /root/home-lab
cd /root/home-lab
git checkout <reviewed-commit>
scripts/collect-proxmox-protected-inputs /root/home-lab-hardware.env
install -m 0600 recovery/proxmox-bootstrap-extra-vars.example.yml /root/proxmox-bootstrap-extra-vars.yml
```

Edit only `/root/proxmox-bootstrap-extra-vars.yml`. Confirm the console and LAN rollback gates, leave all mutation gates false, and run the check-only phase:

```sh
scripts/bootstrap-proxmox-host --mode check \
  --extra-vars /root/proxmox-bootstrap-extra-vars.yml \
  --hardware-env /root/home-lab-hardware.env
```

If check mode reports a ZFS userspace/kernel mismatch, align only the reviewed signed Proxmox kernel and ZFS packages before bootstrap:

```sh
scripts/migrate-proxmox-zfs-stack --check
export PROXMOX_CONSOLE_CONFIRMED=true
export PROXMOX_ZFS_MIGRATION_CONFIRMED=install-reviewed-zfs-and-kernel-packages
scripts/migrate-proxmox-zfs-stack --apply
systemctl reboot
```

After reconnecting through the console or trusted LAN, run `scripts/migrate-proxmox-zfs-stack --verify`, then rerun bootstrap check mode. The migration script pins the reviewed package versions and refuses degraded storage or stopped protected guests.

Review the complete result. Set only the reviewed mutation gates true, then supply a short-lived, preauthorized, one-use Tailscale key tagged for `tag:proxmox` and two distinct SSH public keys:

```sh
export TAILSCALE_AUTH_KEY='<protected one-use key>'
export PROXMOX_PLAN_SSH_PUBLIC_KEYS='<plan public key>'
export PROXMOX_APPLY_SSH_PUBLIC_KEYS='<apply public key>'
export PROXMOX_BOOTSTRAP_EXECUTION_CONFIRMED=run-reviewed-proxmox-bootstrap-with-console
scripts/bootstrap-proxmox-host --mode apply \
  --extra-vars /root/proxmox-bootstrap-extra-vars.yml \
  --hardware-env /root/home-lab-hardware.env
```

The apply mode reruns check mode before mutation. The wrapper requires a clean checkout and root-owned protected inputs, installs the hash-locked Ansible controller in a temporary root-only executable cache, and removes it on exit. The play creates separated API tokens and leaves them only in root-readable files under `/root/.config/home-lab/`.

A failed apply intentionally retains `/var/lib/iac-ansible-production.lock`. Inspect its root-owned owner record before retrying. The wrapper will clear only a structurally valid lock whose owner records `operation=proxmox-bootstrap`, and only when the operator sets `PROXMOX_BOOTSTRAP_RESUME_CONFIRMED=resume-matching-failed-proxmox-bootstrap`. Never remove an unknown or mismatched lock manually.

After success, copy each token through a protected channel into its matching GitHub environment secret. Do not print it, paste it into shell history, or reuse the apply token for plans. Prove `tofu-plan` audit access and `tofu-apply` mutation access over Tailscale before allowing the later steady play to disable password authentication.

## Qualification record

The guarded bootstrap completed on the reviewed feature branch after the pinned Proxmox kernel/ZFS migration and a console-backed reboot. The apply created the separated SSH users and root-only API-token escrow, enrolled the host with `tag:proxmox`, preserved no-DNS/no-route Tailscale preferences, and installed the reviewed VFIO boot configuration. A second reboot verified the active IOMMU/VFIO modules, aligned ZFS userspace and kernel-module versions, an `ONLINE` pool, VM 100 running, and protected CT 101 running.

Both escrowed tokens authenticated to the local Proxmox API, both account-specific SSH keys authenticated only as their intended service users, the production lock was absent, and the final bootstrap check reported `ok=57 changed=0 unreachable=0 failed=0 skipped=37`. Network, firewall, storage/NFS migration, and CT decommission gates remained false.

Tailscale enrollment and the expected device tag are proven, but peer visibility from the existing Docker tailnet node remains absent under the current ACL grants. Do not treat direct Proxmox Tailscale SSH as a recovery path or enable the later password-authentication restriction until a separately reviewed tailnet grant makes that path visible and the SSH proof succeeds.