variable "github_enable_management" {
  type    = bool
  default = false
}

variable "github_owner" {
  type = string
}


variable "state_bucket_name" {
  type = string
}


variable "plan_artifact_age_recipient" {
  type = string

  validation {
    condition     = can(regex("^age1[0-9a-z]+$", var.plan_artifact_age_recipient))
    error_message = "Use a valid age X25519 recipient for saved-plan artifact encryption."
  }
}


variable "tailscale_environment_variables_adopt_existing" {
  type        = bool
  default     = false
  description = "Import pre-staged Tailscale environment variables during the one-time GitHub adoption."
}

variable "aws_region" {
  type = string
}

variable "aws_plan_role_arn" {
  type = string
}

variable "aws_apply_role_arn" {
  type = string
}

variable "arch_ssh_host_key_fingerprint" {
  type = string

  validation {
    condition     = can(regex("^SHA256:", var.arch_ssh_host_key_fingerprint))
    error_message = "Use a verified SHA256 SSH host-key fingerprint."
  }
}

variable "proxmox_ssh_host_key_fingerprint" {
  type = string

  validation {
    condition     = can(regex("^SHA256:", var.proxmox_ssh_host_key_fingerprint))
    error_message = "Use a verified SHA256 SSH host-key fingerprint."
  }
}

variable "required_status_checks" {
  type    = set(string)
  default = ["Validate infrastructure"]
}

variable "apply_reviewer_user_ids" {
  type    = set(number)
  default = []
}

variable "apply_reviewer_team_ids" {
  type    = set(number)
  default = []
}

variable "ruleset_import_id" {
  type        = string
  default     = ""
  description = "Existing ruleset ID. Leave empty only when a reviewed migration will create it."
}
