variable "cluster_name" {
  type    = string
  default = "vsc-orchestrierung"
}

variable "kubernetes_version" {
  type    = string
  default = "1.36.3-do.2"
}

variable "node_pool_name" {
  type    = string
  default = "pool-3y84frtdj"
}

variable "node_size" {
  type    = string
  default = "s-2vcpu-4gb"
}

variable "node_count" {
  type    = number
  default = 1

  validation {
    condition     = var.node_count >= 1 && floor(var.node_count) == var.node_count
    error_message = "node_count must be a positive whole number."
  }
}

variable "region" {
  type    = string
  default = "fra1"
}

variable "vpc_uuid" {
  type    = string
  default = "5502bd81-1d0d-46d4-b7ab-3da6f1afa99f"
}

variable "database_size" {
  type    = string
  default = "db-s-1vcpu-1gb"
}

# Keep false until the cluster-only import plan has been reviewed and applied.
variable "enable_databases" {
  type    = bool
  default = false
}
