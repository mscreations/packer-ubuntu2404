packer {
  required_version = ">= 1.7.0"
  required_plugins {
    hyperv = {
      version = ">= 1.1.1"
      source  = "github.com/hashicorp/hyperv"
    }
    vagrant = {
      version = ">= 1"
      source  = "github.com/hashicorp/vagrant"
    }
  }
}

locals {
  version = formatdate("YYYY.MM.DD", timestamp())
}

variable "name" {
  type    = string
  default = "ubuntu2404"
}

variable "cpus" {
  type    = string
  default = "2"
}

variable "memory" {
  type    = string
  default = "2048"
}

variable "disk_size" {
  type    = string
  default = "40960"
}

variable "http_proxy" {
  type    = string
  default = "${env("http_proxy")}"
}

variable "https_proxy" {
  type    = string
  default = "${env("https_proxy")}"
}

variable "no_proxy" {
  type    = string
  default = "${env("no_proxy")}"
}

variable "iso_urls" {
  type    = list(string)
}

variable "iso_checksum" {
  type    = string
}

variable "build_description" {
  type    = string
}

variable "hcp_client_id" {
  type    = string
  default = "${env("HCP_CLIENT_ID")}"
}

variable "hcp_client_secret" {
  type    = string
  default = "${env("HCP_CLIENT_SECRET")}"
}

source "hyperv-iso" "efi" {
  boot_command = [
    "c",
    "linux /casper/vmlinuz autoinstall quiet net.ifnames=0 biosdevname=0 ",
    "ds='nocloud-net;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/' --- <enter><wait>",
    "initrd /casper/initrd<enter><wait>",
    "boot<enter>"
  ]
  boot_wait             = "5s"
  communicator          = "ssh"
  vm_name               = "${var.name}"
  cpus                  = "${var.cpus}"
  memory                = "${var.memory}"
  disk_size             = "${var.disk_size}"
  iso_urls              = "${var.iso_urls}"
  iso_checksum          = "${var.iso_checksum}"
  headless              = true
  http_directory        = "http"
  ssh_username          = "vagrant"
  ssh_password          = "vagrant"
  ssh_port              = 22
  ssh_timeout           = "3600s"
  enable_dynamic_memory = false
  enable_secure_boot    = true
  guest_additions_mode  = "disable"
  switch_name           = "LAN"
  generation            = "2"
  secure_boot_template  = "MicrosoftUEFICertificateAuthority"
  configuration_version = "9.0"
  keep_registered       = false
  output_directory      = "builds/${var.name}-${source.name}-${source.type}"
  iso_target_path       = element(var.iso_urls, 0)
  shutdown_command      = "echo 'vagrant' | sudo -S shutdown -P now"
}

build {
  name = "ubuntu2404"
  sources = ["hyperv-iso.efi"]

  provisioner "shell" {
    environment_vars  = ["HOME_DIR=/home/vagrant", "http_proxy=${var.http_proxy}", "https_proxy=${var.https_proxy}", "no_proxy=${var.no_proxy}"]
    execute_command   = "echo 'vagrant' | {{ .Vars }} sudo -S -E sh -eux '{{ .Path }}'"
    scripts           = ["scripts/stage1.sh"]
    expect_disconnect = true
  }
  provisioner "shell" {
    environment_vars  = ["HOME_DIR=/home/vagrant", "http_proxy=${var.http_proxy}", "https_proxy=${var.https_proxy}", "no_proxy=${var.no_proxy}"]
    execute_command   = "echo 'vagrant' | {{ .Vars }} sudo -S -E sh -eux '{{ .Path }}'"
    scripts           = ["scripts/setup.sh", "scripts/vagrant.sh", "scripts/cleanup.sh"]
    expect_disconnect = true
  }
  post-processors {
    post-processor "vagrant" {
      output = "builds/${var.name}-{{.Provider}}.box"
    }

    post-processor "vagrant-registry" {
      client_id     = "${var.hcp_client_id}"
      client_secret = "${var.hcp_client_secret}"
      box_tag       = "mscreations/${var.name}"
      version       = "${local.version}"
      version_description = "${var.build_description}"
    }
  }
}