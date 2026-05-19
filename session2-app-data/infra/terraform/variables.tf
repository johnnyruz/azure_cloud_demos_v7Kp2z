variable "location" {
  type        = string
  description = "Azure region for all resources."
  default     = "eastus"
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group Terraform will create."
  default     = "rg-session2-app-data"
}

variable "workload_name" {
  type        = string
  description = "Short lowercase workload name used to build Azure resource names."
  default     = "session2appdata"

  validation {
    condition     = can(regex("^[a-z0-9]{3,20}$", var.workload_name))
    error_message = "The workload_name must be 3-20 lowercase letters or numbers."
  }
}

variable "app_service_sku" {
  type        = string
  description = "App Service SKU."
  default     = "F1"
}


variable "database_name" {
  type        = string
  description = "Cosmos DB SQL database name."
  default     = "trainingdb"
}

variable "container_name" {
  type        = string
  description = "Cosmos DB SQL container name."
  default     = "items"
}

variable "partition_key_path" {
  type        = string
  description = "Cosmos DB container partition key path."
  default     = "/category"
}

variable "environment" {
  type        = string
  description = "Environment tag value."
  default     = "dev"
}
