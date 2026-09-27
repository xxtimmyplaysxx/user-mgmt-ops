locals {
  databases = var.enable_databases ? {
    postgres = { engine = "pg", version = "16", name = "vsc-user-postgres" }
    mysql    = { engine = "mysql", version = "8.4", name = "vsc-module-mysql" }
  } : {}
}

resource "digitalocean_database_cluster" "service" {
  for_each             = local.databases
  name                 = each.value.name
  engine               = each.value.engine
  version              = each.value.version
  size                 = var.database_size
  region               = var.region
  node_count           = 1
  private_network_uuid = var.vpc_uuid

  lifecycle {
    prevent_destroy = true
  }
}

resource "digitalocean_database_db" "service" {
  for_each   = local.databases
  cluster_id = digitalocean_database_cluster.service[each.key].id
  name       = each.key == "postgres" ? "usermgmt_staging" : "modules"
}

resource "digitalocean_database_firewall" "service" {
  for_each   = local.databases
  cluster_id = digitalocean_database_cluster.service[each.key].id
  rule {
    type  = "k8s"
    value = "7e46ab36-b79c-4dea-8301-2a2a998822c5"
  }
}

output "database_ids" {
  value = { for key, db in digitalocean_database_cluster.service : key => db.id }
}
