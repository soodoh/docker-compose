
variable "omada_export_path" {
  type    = string
  default = ""
}

variable "omada_enable_management" {
  type    = bool
  default = false
}

variable "adoption_complete" {
  type    = bool
  default = false
}

variable "adoption_mode" {
  type    = bool
  default = false
}

variable "enable_qualification" {
  type    = bool
  default = false
}

variable "qualification_mode" {
  type    = bool
  default = false
}

check "adoption_mode_boundary" {
  assert {
    condition     = !(var.adoption_mode && var.adoption_complete)
    error_message = "Omada adoption mode must be disabled before adoption_complete is asserted."
  }
}

check "qualification_mode_boundary" {
  assert {
    condition     = !(var.adoption_mode && var.qualification_mode)
    error_message = "Omada qualification must run outside adoption mode."
  }
}

variable "qualification_network_id" {
  type      = string
  default   = ""
  sensitive = true
}

variable "qualification_mac" {
  type      = string
  default   = ""
  sensitive = true
}

variable "qualification_ip" {
  type      = string
  default   = ""
  sensitive = true
}
