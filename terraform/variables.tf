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
