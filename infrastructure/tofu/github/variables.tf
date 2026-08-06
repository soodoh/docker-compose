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

variable "github_repository_variables_adopt_existing" {
  type        = bool
  default     = false
  description = "Import only the pre-existing repository variables during one-time GitHub adoption."
}

variable "github_repository_variable_names_adopt_existing" {
  type = set(string)
  default = [
    "AWS_RECOVERY_REGION",
    "INFRASTRUCTURE_APPLY_ENABLED",
    "INFRASTRUCTURE_AUTO_PLAN_ENABLED",
    "PLAN_ARTIFACT_AGE_RECIPIENT",
  ]
}

variable "apply_deployment_branches" {
  type = set(string)
  default = [
    "main",
  ]
}

variable "apply_deployment_policy_import_ids" {
  type        = map(number)
  default     = {}
  description = "Existing apply-environment deployment policy IDs keyed by exact branch pattern."
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
  default = ["Hash and copy exact Compose artifact"]
}


variable "ruleset_import_id" {
  type        = string
  default     = ""
  description = "Existing ruleset ID. Leave empty only when a reviewed migration will create it."
}
