locals {
  contract = yamldecode(file("${path.module}/../../contract/home-lab.yml"))
}

provider "proxmox" {
  endpoint = var.proxmox_endpoint
  insecure = false
}
