variable "proxmox_endpoint" {
  type = string

  validation {
    condition     = startswith(var.proxmox_endpoint, "https://")
    error_message = "proxmox_endpoint must use HTTPS."
  }
}

variable "qualification_operation" {
  type = string

  validation {
    condition = contains([
      "create",
      "probe-protected-delete",
      "verify-protected",
      "unprotect",
      "reprotect",
      "delete",
      "verify-empty",
    ], var.qualification_operation)
    error_message = "qualification_operation is invalid."
  }
}

variable "qualification_vm_id" {
  type      = number
  sensitive = true

  validation {
    condition = (
      floor(var.qualification_vm_id) == var.qualification_vm_id &&
      var.qualification_vm_id >= 102 &&
      var.qualification_vm_id <= 999999999 &&
      !contains([100, 101], var.qualification_vm_id)
    )
    error_message = "qualification_vm_id must be an integer in the Proxmox range and must not be 100 or 101."
  }
}

variable "qualification_template_file_id" {
  type      = string
  sensitive = true

  validation {
    condition = can(regex(
      "^local:vztmpl/[A-Za-z0-9][A-Za-z0-9._+-]*\\.tar\\.(gz|xz|zst)$",
      var.qualification_template_file_id,
    ))
    error_message = "qualification_template_file_id must be an exact local:vztmpl template archive file ID."
  }
}

locals {
  marker  = "home-lab-lxc-provider-qualification-v1"
  enabled = contains(["create", "verify-protected", "unprotect", "reprotect"], var.qualification_operation)
  protected = contains([
    "create",
    "verify-protected",
    "reprotect",
  ], var.qualification_operation)
}

provider "proxmox" {
  endpoint = var.proxmox_endpoint
  insecure = false
}

resource "proxmox_virtual_environment_container" "qualification" {
  count = local.enabled ? 1 : 0

  node_name   = "proxmox"
  vm_id       = var.qualification_vm_id
  description = local.marker

  protection    = local.protected
  started       = false
  start_on_boot = false
  unprivileged  = true

  console {
    enabled   = false
    tty_count = 0
  }

  cpu {
    cores = 1
    units = 100
  }

  memory {
    dedicated = 128
    swap      = 0
  }

  disk {
    datastore_id = "local-lvm"
    size         = 1
  }

  initialization {
    hostname = local.marker
  }

  operating_system {
    template_file_id = var.qualification_template_file_id
  }
}
