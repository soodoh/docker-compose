variable "proxmox_endpoint" {
  type = string
}


variable "games_disk_by_id" {
  type      = string
  sensitive = true

  validation {
    condition     = startswith(var.games_disk_by_id, "/dev/disk/by-id/")
    error_message = "games_disk_by_id must be an absolute /dev/disk/by-id path."
  }
}

variable "phase" {
  type    = string
  default = "adoption"

  validation {
    condition     = contains(["adoption", "steady", "recovery"], var.phase)
    error_message = "phase must be adoption, steady, or recovery."
  }
}

variable "use_hardware_mappings" {
  type    = bool
  default = false
}

variable "manage_hardware_mappings" {
  type        = bool
  default     = false
  description = "Root-PAM-only migration gate. Never enable during adoption."
}

variable "enable_qualification" {
  type    = bool
  default = false
}

variable "qualification_vm_id" {
  type    = number
  default = 9900
}

variable "qualification_ssh_public_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "recovery_ssh_public_key" {
  type      = string
  sensitive = true
  default   = ""
}
