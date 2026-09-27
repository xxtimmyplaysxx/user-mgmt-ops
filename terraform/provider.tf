terraform {
  required_version = ">= 1.5.0, < 2.0.0"
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.100"
    }
  }
}

# Supply DIGITALOCEAN_TOKEN through the environment, never through Git.
provider "digitalocean" {}
