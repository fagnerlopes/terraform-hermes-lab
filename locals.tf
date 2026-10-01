locals {
  # Platform ID for Locaweb Cloud, zone ZP01. Same value the
  # tf-cloud-starter-kit uses; change here to move zone.
  zone_id = "513e3380-a60d-4ef7-9e1a-02b039fb15c7"

  # The OS image is NOT pinned by UUID. Locaweb rotates it: the previously
  # hardcoded 92afac85 vanished from every template filter mid-workshop and
  # took `make up` down with it. Resolved by name below instead.
  template_ubuntu_2404_name = "Ubuntu Server 24.04 LTS"
}
