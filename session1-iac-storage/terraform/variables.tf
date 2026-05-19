variable "location" {
  type        = string
  description = "Azure region for all resources."
  default     = "eastus"
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group Terraform will create."
}

variable "storage_account_prefix" {
  type        = string
  description = "Lowercase prefix used to build a globally unique storage account name."
  default     = "stsession1"

  validation {
    condition     = can(regex("^[a-z0-9]{3,11}$", var.storage_account_prefix))
    error_message = "The storage_account_prefix must be 3-11 lowercase letters or numbers."
  }
}

variable "container_name" {
  type        = string
  description = "Name of the private blob container to create."
  default     = "training-terraform"
}

variable "environment" {
  type        = string
  description = "Environment tag value."
  default     = "dev"
}
