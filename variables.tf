variable "prefix" {
  description = "The prefix which should be used for all resources in this example"
  default = "ad-lab"
}

variable "location" {
  description = "The Azure Region in which all resources in this example should be created."
  default = "uksouth"
}

variable "vm_username" {
  description = "The admin username used for the deployed Azure VM."
  default = "azure-user"
}

variable "tenant" {
  description = "Azure AD tenant Name"
}
