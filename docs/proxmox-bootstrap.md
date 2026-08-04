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

The apply mode reruns check mode before mutation. The wrapper requires a clean checkout and root-owned protected inputs and installs the hash-locked Ansible controller only in `/run`. The play creates separated API tokens and leaves them only in root-readable files under `/root/.config/home-lab/`.

After success, copy each token through a protected channel into its matching GitHub environment secret. Do not print it, paste it into shell history, or reuse the apply token for plans. Prove `tofu-plan` audit access and `tofu-apply` mutation access over Tailscale before allowing the later steady play to disable password authentication.