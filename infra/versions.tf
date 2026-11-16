terraform {
  required_version = ">= 1.10.0, < 2.0.0"
  required_providers {
    upcloud = {
      source  = "UpCloudLtd/upcloud"
      version = "= 5.45.0"
    }
  }
}
provider "upcloud" {}
