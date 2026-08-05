variable "proxmox_endpoint" {
  type = string
}


variable "decommission_legacy_ct" {
  type    = bool
  default = false
}

variable "decommission_unprotect" {
  type    = bool
  default = false
}

variable "decommission_confirmation" {
  type      = string
  sensitive = true
  default   = ""
}

check "decommission_gate" {
  assert {
    condition = (
      !(var.decommission_legacy_ct || var.decommission_unprotect) || (
        var.decommission_confirmation == "decommission-ct-101-after-direct-tailscale-qualified" &&
        !local.legacy.recreate_after_decommission &&
        !(var.decommission_legacy_ct && var.decommission_unprotect)
    ))
    error_message = "CT 101 decommission requires the exact post-qualification confirmation."
  }
}
locals {
  contract = yamldecode(file("${path.module}/../../contract/home-lab.yml"))
  legacy   = local.contract.proxmox.legacy_container
}

provider "proxmox" {
  endpoint = var.proxmox_endpoint
  insecure = false
}

resource "proxmox_virtual_environment_container" "tailscale_gateway" {
  count       = var.decommission_legacy_ct ? 0 : 1
  node_name   = local.contract.proxmox.node
  vm_id       = local.legacy.vmid
  description = "Legacy recovery gateway; adopted only for controlled decommission"

  protection    = var.decommission_unprotect ? false : local.legacy.protected
  started       = true
  start_on_boot = local.legacy.on_boot
  unprivileged  = local.legacy.unprivileged

  cpu {
    cores = local.legacy.cores
  }

  memory {
    dedicated = local.legacy.memory_mb
    swap      = local.legacy.swap_mb
  }

  disk {
    datastore_id = local.legacy.root_datastore
    size         = local.legacy.root_size_gb
  }

  features {
    nesting = true
  }

  initialization {
    hostname = local.legacy.name

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
  }

  network_interface {
    bridge      = local.contract.network.bridge
    firewall    = false
    mac_address = local.legacy.mac
    name        = "eth0"
  }

  operating_system {
    template_file_id = "local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst"
    type             = "debian"
  }

  startup {
    order      = "1"
    up_delay   = "30"
    down_delay = "60"
  }

  lifecycle {
    ignore_changes = [
      console,
      cpu,
      description,
      device_passthrough,
      disk,
      features,
      initialization,
      memory,
      network_interface,
      operating_system,
      start_on_boot,
      started,
      startup,
      tags,
      timeout_clone,
      timeout_create,
      timeout_delete,
      timeout_start,
      timeout_update,
      unprivileged,
      vm_id,
    ]
  }

}

import {
  for_each = var.decommission_legacy_ct ? toset([]) : toset(["${local.contract.proxmox.node}/${local.legacy.vmid}"])
  to       = proxmox_virtual_environment_container.tailscale_gateway[0]
  id       = each.value
}
