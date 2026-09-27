# Generated from the existing cluster, then reviewed and parameterized.
# Disabled DRA blocks were removed because they conflict with device-plugin blocks.
# The API reports one worker; generation initially wrote node_count = 0.
resource "digitalocean_kubernetes_cluster" "course" {
  provider           = digitalocean
  auto_upgrade       = false
  cluster_subnet     = "10.108.0.0/16"
  ha                 = false
  isolated_workers   = false
  name               = var.cluster_name
  region             = var.region
  service_subnet     = "10.109.0.0/19"
  surge_upgrade      = true
  tags               = []
  version            = var.kubernetes_version
  vpc_uuid           = var.vpc_uuid
  worker_subnet_uuid = "79edd204-aac5-4805-a3af-fdfab8476f60"
  amd_gpu_device_metrics_exporter_plugin {
    enabled = false
  }
  amd_gpu_device_plugin {
    enabled = false
  }
  coredns_autoscaler {
    enabled = true
  }
  maintenance_policy {
    day        = "any"
    start_time = "14:00"
  }
  node_pool {
    auto_scale = false
    labels     = {}
    max_nodes  = 0
    min_nodes  = 0
    name       = var.node_pool_name
    node_count = var.node_count
    size       = var.node_size
    tags       = []
  }
  nvidia_gpu_device_plugin {
    enabled = false
  }
  p2p_oci_registry_plugin {
    enabled = false
  }
  rdma_shared_device_plugin {
    enabled = false
  }
  routing_agent {
    enabled = false
  }

  lifecycle {
    prevent_destroy = true
  }
}
