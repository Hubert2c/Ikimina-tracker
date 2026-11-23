terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# Credentials are never written here. Sign in with `az login` and export
# ARM_SUBSCRIPTION_ID (see README.md).
provider "azurerm" {
  features {}
}
