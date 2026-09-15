# Locaweb Cloud lab VM running the Hermes Agent, installed on the host by the
# official Nous Research installer. Mirrors the CloudWeaver `hermes-host`
# recipe, minus the GitHub Actions/Kamal pipeline: everything happens in
# cloud-init so a participant only needs `make up`.
#
# Deliberately no web terminal and no HTTP port: SSH is the only way in.

resource "cloudstack_network" "lab" {
  name             = var.vm_name
  display_text     = "Rede do laboratório Hermes"
  cidr             = "10.20.1.0/24"
  network_offering = "Default Guest Network"
  zone             = local.zone_id
}

resource "cloudstack_ipaddress" "lab" {
  network_id = cloudstack_network.lab.id
  zone       = local.zone_id
}

# The API hands back the address before it is actually routable; without this
# the port forward below is created against an IP that is not ready yet.
resource "time_sleep" "ip_ready" {
  depends_on      = [cloudstack_ipaddress.lab]
  create_duration = "10s"
}

resource "random_password" "root" {
  length  = 20
  special = false
}

resource "cloudstack_ssh_keypair" "lab" {
  name       = var.vm_name
  public_key = file(var.ssh_public_key_path)
}

resource "cloudstack_instance" "lab" {
  name             = var.vm_name
  display_name     = "Hermes Lab — TDC"
  service_offering = var.service_offering
  template         = local.template_ubuntu_2404_id
  zone             = local.zone_id
  network_id       = cloudstack_network.lab.id
  keypair          = cloudstack_ssh_keypair.lab.name
  expunge          = true

  # Do NOT set root_disk_size. The Locaweb plans ship fixed disk offerings
  # ("large" -> d1.large.fixed, 160 GB): CloudStack ignores a requested size,
  # creates the offering's, and every refresh then reads back a value that
  # differs from the config. Since root_disk_size is ForceNew, that replaced
  # the VM on EVERY apply. Left unset, the attribute is Computed and simply
  # takes whatever the offering gives.

  user_data = base64encode(templatefile("${path.module}/cloud-init.yaml", {
    root_password     = random_password.root.result
    sandbox_cpu       = var.sandbox_cpu
    sandbox_memory_mb = var.sandbox_memory_mb
  }))
}

resource "cloudstack_port_forward" "ssh" {
  ip_address_id = cloudstack_ipaddress.lab.id
  depends_on    = [time_sleep.ip_ready]

  forward {
    protocol           = "tcp"
    private_port       = 22
    public_port        = 22
    virtual_machine_id = cloudstack_instance.lab.id
  }
}

resource "cloudstack_firewall" "ssh" {
  ip_address_id = cloudstack_ipaddress.lab.id

  # Must come after the instance: an isolated guest network stays in
  # "Allocated" state until the first VM is deployed, and only then does it get
  # the virtual router that applies firewall rules. Creating the rule earlier
  # fails with errorcode 530, "Failed to create firewall rule". Ordering after
  # the port forward (which already depends on the instance) keeps the whole
  # public-IP setup in one predictable sequence.
  depends_on = [time_sleep.ip_ready, cloudstack_port_forward.ssh]

  rule {
    cidr_list = ["0.0.0.0/0"]
    protocol  = "tcp"
    ports     = ["22"]
  }
}
