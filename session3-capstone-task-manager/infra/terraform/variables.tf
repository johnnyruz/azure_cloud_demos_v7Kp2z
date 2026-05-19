variable "location" {
  type        = string
  description = "Azure region for all resources."
  default     = "eastus"
}

variable "resource_group_name" {
  type        = string
  description = "Name of the pre-created resource group to deploy into."
  default     = "rg-session3-capstone"
}

variable "workload_name" {
  type        = string
  description = "Short lowercase workload name used to build Azure resource names."
  default     = "capstonetasks"

  validation {
    condition     = can(regex("^[a-z0-9]{3,14}$", var.workload_name))
    error_message = "The workload_name must be 3-14 lowercase letters or numbers."
  }
}

variable "app_service_sku" {
  type        = string
  description = "App Service SKU."
  default     = "F1"
}

variable "environment" {
  type        = string
  description = "Environment tag value."
  default     = "dev"
}

variable "vnet_address_space" {
  type        = list(string)
  description = "Address space for the capstone virtual network."
  default     = ["10.30.0.0/16"]
}

variable "app_subnet_prefix" {
  type        = string
  description = "CIDR prefix for the App Service VNet integration subnet."
  default     = "10.30.1.0/24"
}

variable "data_subnet_prefix" {
  type        = string
  description = "CIDR prefix for the data subnet hosting the Cosmos DB private endpoint."
  default     = "10.30.2.0/24"
}

variable "database_name" {
  type        = string
  description = "Cosmos DB SQL database name."
  default     = "taskdb"
}

variable "container_name" {
  type        = string
  description = "Cosmos DB SQL container name."
  default     = "tasks"
}

variable "partition_key_path" {
  type        = string
  description = "Cosmos DB container partition key path."
  default     = "/status"
}
