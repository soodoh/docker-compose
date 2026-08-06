variable "proxmox_endpoint" {
  type = string
}

variable "retirement_operation" {
  type    = string
  default = "none"

  validation {
    condition     = contains(["none", "unprotect", "delete"], var.retirement_operation)
    error_message = "retirement_operation must be none, unprotect, or delete."
  }
}

variable "decommission_confirmation" {
  type      = string
  sensitive = true
  ephemeral = true
  default   = ""

  validation {
    condition = (
      local.operation_matches_stage &&
      !local.legacy.recreate_after_decommission &&
      (
        (local.retirement_stage == "protected" && var.retirement_operation == "none") ||
        sha256(var.decommission_confirmation) == "6aef61a66bc191b96d854e1c34be3a8c79178bd1ae864a2cdc5bc8700c5eff8c"
      )
    )
    error_message = "CT retirement requires a matching durable stage, disabled recreation, and the exact confirmation when gated."
  }
}

locals {
  contract          = yamldecode(file("${path.module}/../../contract/home-lab.yml"))
  legacy            = local.contract.proxmox.legacy_container
  retirement_stage  = local.legacy.retirement_stage
  legacy_enabled    = local.retirement_stage != "retired"
  legacy_protection = local.retirement_stage == "protected"
  operation_matches_stage = (
    var.retirement_operation == "none" ||
    (var.retirement_operation == "unprotect" && local.retirement_stage == "unprotected") ||
    (var.retirement_operation == "delete" && local.retirement_stage == "retired")
  )
}

provider "proxmox" {
  endpoint = var.proxmox_endpoint
  insecure = false
}

resource "proxmox_virtual_environment_container" "tailscale_gateway" {
  count       = local.legacy_enabled ? 1 : 0
  node_name   = local.contract.proxmox.node
  vm_id       = local.legacy.vmid
  description = "Legacy recovery gateway; adopted only for controlled decommission"

  protection    = local.legacy_protection
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
  for_each = local.legacy_enabled ? toset(["${local.contract.proxmox.node}/${local.legacy.vmid}"]) : toset([])
  to       = proxmox_virtual_environment_container.tailscale_gateway[0]
  id       = each.value
}
