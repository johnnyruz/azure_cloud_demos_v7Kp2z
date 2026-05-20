variable "location" {
  type        = string
  description = "Azure region for all resources."
  default     = "eastus"
}

variable "resource_group_name" {
  type        = string
  description = "Name of the pre-created resource group to deploy into."
  default     = "rg-session3-capstone-alt"
}

variable "workload_name" {
  type        = string
  description = "Short lowercase workload name used to build Azure resource names."
  default     = "altcaptasks"

  validation {
    condition     = can(regex("^[a-z0-9]{3,14}$", var.workload_name))
    error_message = "workload_name must be 3-14 lowercase letters or numbers."
  }
}

variable "environment" {
  type        = string
  description = "Environment tag value."
  default     = "dev"
}

variable "vnet_address_space" {
  type        = list(string)
  description = "Address space for the virtual network."
  default     = ["10.31.0.0/16"]
}

variable "appgw_subnet_prefix" {
  type        = string
  description = "CIDR prefix for the Application Gateway subnet. Must be at least /24."
  default     = "10.31.0.0/24"
}

variable "aca_subnet_prefix" {
  type        = string
  description = "CIDR prefix for the Azure Container Apps environment subnet. Must be at least /27."
  default     = "10.31.2.0/23"
}

variable "data_subnet_prefix" {
  type        = string
  description = "CIDR prefix for the data subnet hosting the Cosmos DB private endpoint."
  default     = "10.31.4.0/24"
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

variable "github_repo" {
  type        = string
  description = "GitHub repo in owner/name format. Used in CI/CD setup instructions."
  default     = "REPLACE-WITH-OWNER/REPLACE-WITH-REPO"
}
