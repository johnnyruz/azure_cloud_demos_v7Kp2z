terraform {
  backend "azurerm" {
    resource_group_name  = "rg-JRuzick"
    storage_account_name = "stsession1daiyrjese2tag"
    container_name       = "tf-state-store"
    key                  = "session2.tfstate"
  }
}
