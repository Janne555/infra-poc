mock_provider "upcloud" {}
variables {
  bootstrap_key    = "ssh-ed25519 test-generated-bootstrap-key"
  state_passphrase = "test-only-passphrase-not-a-real-state-key"
}
run "private_database_and_closed_ssh" {
  command = plan
  assert {
    condition     = upcloud_managed_database_postgresql.apps.properties[0].public_access == false
    error_message = "PostgreSQL must never be publicly accessible."
  }
  assert {
    condition     = toset(upcloud_managed_database_postgresql.apps.properties[0].ip_filter) == toset(["10.42.20.10/32", "10.42.10.12/32", "10.42.10.14/32"])
    error_message = "Only nodes configured for PostgreSQL access may reach it."
  }
  assert {
    condition     = alltrue([for server in values(upcloud_server.service) : server.firewall == false])
    error_message = "Filtering must use the host firewall."
  }
  assert {
    condition     = upcloud_network.sdn["internal"].ip_network[0].dhcp_default_route == true && upcloud_network.sdn["edge"].ip_network[0].dhcp_default_route == false
    error_message = "DHCP must give internal hosts a NAT default route while edge hosts retain their public default route."
  }
}
run "separate_internal_and_edge_networks" {
  command = plan
  assert {
    condition     = upcloud_network.sdn["internal"].ip_network[0].address == "10.42.10.0/24"
    error_message = "Internal services must use the internal subnet."
  }
  assert {
    condition     = alltrue([for name, server in upcloud_server.service : length(server.network_interface) == (local.nodes[name].public_ip ? 2 : 1) && length([for nic in server.network_interface : nic if nic.type == "private"]) == 1])
    error_message = "Each server needs a private interface; public interfaces must follow explicit configuration."
  }
}
run "database_access_follows_configuration" {
  command = plan
  variables {
    config_file = "tests/fixtures/custom.yml"
  }
  assert {
    condition     = toset(upcloud_managed_database_postgresql.apps.properties[0].ip_filter) == toset(["10.42.10.30/32"])
    error_message = "Database access must follow the node setting, regardless of service name; omitted or false means no access."
  }
}
run "private_services_use_nat" {
  command = plan
  assert {
    condition     = alltrue([for name in ["odoo", "vaultwarden", "gatus"] : length([for nic in upcloud_server.service[name].network_interface : nic if nic.type == "public"]) == 0 && output.inventory[name].public_ip == null])
    error_message = "Internal services must have no public interface or public address in inventory."
  }
  assert {
    condition     = toset(upcloud_gateway.egress.features) == toset(["nat"]) && upcloud_network.sdn["internal"].ip_network[0].gateway == "10.42.10.1"
    error_message = "The private network needs a NAT gateway and a defined next hop."
  }
}
run "public_hosts_bootstrap_their_firewall" {
  command = plan
  assert {
    condition = alltrue([for name, server in upcloud_server.service : local.nodes[name].public_ip ? (
      strcontains(yamldecode(server.user_data).bootcmd[0][5], "systemctl mask --runtime --now ssh.service ssh.socket") &&
      strcontains(yamldecode(server.user_data).bootcmd[0][5], "ip daddr ${local.nodes[name].private_ip} ip saddr 10.42.10.0/24 tcp dport 22 accept") &&
      strcontains(yamldecode(server.user_data).bootcmd[0][5], "policy drop;")
    ) : server.user_data == null])
    error_message = "Public hosts need an initial firewall with private SSH access before Ansible."
  }
}
run "reject_private_address_outside_subnet" {
  command = plan
  variables {
    config_file = "tests/fixtures/outside-subnet.yml"
  }
  expect_failures = [upcloud_network.sdn]
}

run "dhcp_connects_private_networks" {
  command = plan
  assert {
    condition = alltrue([for name, subnet in upcloud_network.sdn :
      toset(subnet.ip_network[0].dhcp_routes) == toset([for other_name, other in local.subnets : "${other.cidr}-nexthop=${local.subnets[name].gateway}" if other_name != name]) &&
      toset(subnet.ip_network[0].dhcp_dns) == toset(local.config.network.dns_servers)
    ])
    error_message = "DHCP must provide cross-network routes and DNS on both subnets."
  }
  assert {
    condition     = toset([for attachment in upcloud_managed_database_postgresql.apps.network : attachment.name]) == toset(["internal", "edge"])
    error_message = "Database clients on both networks need private database attachments."
  }
  assert {
    condition = alltrue([for name, node in local.nodes :
      node.public_ip ? node.network == "edge" : node.network == "internal"
    ])
    error_message = "Public services belong on edge; private services belong on internal."
  }
}
