locals {
  config  = yamldecode(file(var.config_file))
  subnets = local.config.network.subnets
  nodes = {
    for name, service in local.config.services : name => {
      network           = service.server.network
      plan              = service.server.plan
      data_gb           = service.server.data_gb
      private_ip        = service.server.private_ip
      public_ip         = try(service.server.public_ip, false)
      postgresql_access = try(service.postgresql.enabled, false)
    }
  }
}
moved {
  from = upcloud_network.sdn["app"]
  to   = upcloud_network.private
}
moved {
  from = upcloud_network.private
  to   = upcloud_network.sdn["internal"]
}
resource "upcloud_router" "private" {
  name = "hacklab-private"
}
resource "upcloud_gateway" "egress" {
  name     = "hacklab-egress"
  zone     = local.config.zone
  features = ["nat"]
  plan     = local.config.network.nat_plan
  router {
    id = upcloud_router.private.id
  }
}
resource "upcloud_network" "sdn" {
  for_each = local.subnets
  name     = "hacklab-${each.key}"
  zone     = local.config.zone
  router   = upcloud_router.private.id
  lifecycle {
    precondition {
      condition = length(distinct([for n in values(local.nodes) : n.private_ip])) == length(local.nodes) && alltrue([
        for n in values(local.nodes) : try(
          cidrcontains(local.subnets[n.network].cidr, n.private_ip) &&
          !contains([cidrhost(local.subnets[n.network].cidr, 0), local.subnets[n.network].gateway, cidrhost(local.subnets[n.network].cidr, -1)], n.private_ip) &&
        n.data_gb >= 10 && (n.public_ip != local.subnets[n.network].default_route), false)
      ])
      error_message = "Use unique service addresses within the selected subnet and data volumes >=10 GiB. Public hosts need public default routes; private hosts need NAT default routes."
    }
    precondition {
      condition = alltrue(flatten([
        for name, subnet in local.subnets : [for other_name, other in local.subnets :
          name == other_name || (!cidrcontains(subnet.cidr, cidrhost(other.cidr, 0)) && !cidrcontains(other.cidr, cidrhost(subnet.cidr, 0)))
        ]
      ]))
      error_message = "SDN subnet address ranges must not overlap."
    }
  }
  ip_network {
    address            = each.value.cidr
    dhcp               = true
    dhcp_default_route = each.value.default_route
    dhcp_dns           = local.config.network.dns_servers
    dhcp_routes        = [for name, subnet in local.subnets : "${subnet.cidr}-nexthop=${each.value.gateway}" if name != each.key]
    gateway            = each.value.gateway
    family             = "IPv4"
  }
}
resource "upcloud_storage" "data" {
  for_each = local.nodes
  title    = "hacklab-${each.key}-data"
  zone     = local.config.zone
  size     = each.value.data_gb
  tier     = "maxiops"
  lifecycle { prevent_destroy = true }
}
resource "upcloud_server" "service" {
  for_each = local.nodes
  hostname = "hacklab-${each.key}"
  zone     = local.config.zone
  plan     = each.value.plan
  metadata = true
  firewall = false
  user_data = each.value.public_ip ? "#cloud-config\n${yamlencode({
    bootcmd = [["cloud-init-per", "instance", "initial-firewall", "sh", "-ec", templatefile("${path.module}/templates/bootstrap-firewall.sh.tftpl", {
      private_ip    = each.value.private_ip
      private_cidrs = [for subnet in values(local.subnets) : subnet.cidr]
    })]]
  })}" : null
  depends_on = [upcloud_gateway.egress, upcloud_managed_database_postgresql.apps]
  labels     = { service = each.key }
  lifecycle {
    # Login credentials are for server creation; later deployments use normal access.
    ignore_changes = [login]
  }
  template {
    storage = local.config.debian_template
    size    = 25
  }
  storage_devices { storage = upcloud_storage.data[each.key].id }
  login {
    user              = "bootstrap"
    keys              = [var.bootstrap_key]
    create_password   = false
    password_delivery = "none"
  }
  dynamic "network_interface" {
    for_each = each.value.public_ip ? [true] : []
    content {
      type              = "public"
      ip_address_family = "IPv4"
    }
  }
  network_interface {
    type       = "private"
    network    = upcloud_network.sdn[each.value.network].id
    ip_address = each.value.private_ip
  }
}
resource "upcloud_managed_database_postgresql" "apps" {
  name                   = "hacklab-postgres"
  title                  = "Hacklab PostgreSQL"
  plan                   = local.config.postgresql.plan
  zone                   = local.config.zone
  termination_protection = true
  dynamic "network" {
    for_each = toset([for node in values(local.nodes) : node.network if node.postgresql_access])
    content {
      family = "IPv4"
      name   = network.value
      type   = "private"
      uuid   = upcloud_network.sdn[network.value].id
    }
  }
  properties {
    public_access                       = false
    automatic_utility_network_ip_filter = false
    ip_filter                           = [for node in values(local.nodes) : "${node.private_ip}/32" if node.postgresql_access]
  }
  lifecycle { prevent_destroy = true }
}

moved {
  from = upcloud_server.service["authentik"]
  to   = upcloud_server.service["keycloak"]
}
moved {
  from = upcloud_storage.data["authentik"]
  to   = upcloud_storage.data["keycloak"]
}
moved {
  from = upcloud_server.service["monitoring"]
  to   = upcloud_server.service["gatus"]
}
moved {
  from = upcloud_storage.data["monitoring"]
  to   = upcloud_storage.data["gatus"]
}
