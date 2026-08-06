resource "proxmox_download_file" "arch_cloud_image" {
  count = var.enable_qualification ? 1 : 0

  content_type       = "import"
  datastore_id       = "local"
  node_name          = local.node
  url                = local.vm.cloud_image.url
  checksum           = local.vm.cloud_image.sha256
  checksum_algorithm = "sha256"
  file_name          = "Arch-Linux-x86_64-cloudimg-${local.vm.cloud_image.version}.qcow2"
}

resource "proxmox_virtual_environment_vm" "qualification" {
  count = var.enable_qualification ? 1 : 0

  node_name  = local.node
  vm_id      = var.qualification_vm_id
  name       = "tofu-provider-qualification"
  machine    = "q35"
  on_boot    = false
  started    = true
  protection = false

  agent {
    enabled = true
    wait_for_ip {
      ipv4 = true
    }
  }

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 2048
  }

  disk {
    datastore_id = "local-lvm"
    import_from  = proxmox_download_file.arch_cloud_image[0].id
    interface    = "scsi0"
    size         = 16
  }

  initialization {
    datastore_id = "local-lvm"
    upgrade      = false

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    user_account {
      keys     = [var.qualification_ssh_public_key]
      username = "arch"
    }
  }

  network_device {
    bridge = local.contract.network.bridge
    model  = "virtio"
  }

  serial_device {
    device = "socket"
  }

  operating_system {
    type = "l26"
  }

  lifecycle {
    precondition {
      condition     = var.qualification_ssh_public_key != ""
      error_message = "A qualification SSH public key is required."
    }
  }
}
