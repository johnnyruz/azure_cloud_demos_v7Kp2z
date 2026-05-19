terraform {
  #backend "azurerm" {
  #  resource_group_name  = "RESOURCE_GROUP_NAME"
  #  storage_account_name = "STORAGE_ACCOUNT_NAME"
  #  container_name       = "tfstate"
  #  key                  = "session1.tfstate"
  #}

  backend "local" {}
}
