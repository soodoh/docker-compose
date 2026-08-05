variable "aws_region" {
  type = string
}


variable "recovery_bucket_region" {
  type = string
}

variable "state_bucket_name" {
  type = string
}

variable "recovery_bucket_name" {
  type = string
}

variable "github_owner" {
  type = string
}

variable "github_repository" {
  type = string
}

variable "github_owner_id" {
  type        = string
  description = "Stable numeric GitHub owner ID used by OIDC trust subjects."

  validation {
    condition     = can(regex("^[0-9]+$", var.github_owner_id))
    error_message = "github_owner_id must be a numeric GitHub owner ID."
  }
}

variable "github_repository_id" {
  type        = string
  description = "Stable numeric GitHub repository ID used by OIDC trust subjects."

  validation {
    condition     = can(regex("^[0-9]+$", var.github_repository_id))
    error_message = "github_repository_id must be a numeric GitHub repository ID."
  }
}

variable "github_plan_environment" {
  type    = string
  default = "infrastructure-plan"
}

variable "github_apply_environment" {
  type    = string
  default = "infrastructure-apply"
}

variable "mutation_lease_table_name" {
  type    = string
  default = "home-lab-infrastructure-lease"
}
