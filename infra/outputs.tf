output "inventory" {
  description = "Public addresses are for console recovery records, never automatic SSH targets."
  value = { for name, server in upcloud_server.service : name => {
    server_id  = server.id
    private_ip = local.nodes[name].private_ip
    public_ip  = try([for nic in server.network_interface : nic.ip_address if nic.type == "public"][0], null)
    data_id    = upcloud_storage.data[name].id
  } }
}
output "database" {
  value = { host = upcloud_managed_database_postgresql.apps.service_host, port = upcloud_managed_database_postgresql.apps.service_port }
}
