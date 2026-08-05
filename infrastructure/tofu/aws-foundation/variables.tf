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
