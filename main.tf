terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 2.4.0"
    }
  }
}

provider "azurerm" {
  features {}
}


#########
# Lab 2 #
#########
resource "random_string" "rand_logicapp_name" {
  length           = 10
  upper		   = false
  special	   = false
}

resource "azurerm_logic_app_workflow" "logapp" {
  name 			= "resource-tracker-${random_string.rand_logicapp_name.result}-app"
  resource_group_name 	= azurerm_resource_group.rg.name
  location 		= azurerm_resource_group.rg.location

}

resource "null_resource" "example1" {
  provisioner "local-exec" {
    command = "az logic workflow create --resource-group ${azurerm_resource_group.rg.name} --location ${azurerm_resource_group.rg.location} --name ${azurerm_logic_app_workflow.logapp.name} --definition 'logicapp-workflow-definition.json'"
  }
}

##########
# Lab 3  #
##########

resource "azurerm_virtual_network" "vnet" {
  name                = "${var.prefix}-network"
  address_space       = ["10.0.0.0/22"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "internal" {
  name                 = "internal"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_public_ip" "pip" {
  name                = "${var.prefix}-pip"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  allocation_method   = "Dynamic"
}

resource "azurerm_network_interface" "nic" {
  name                = "${var.prefix}-nic"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.internal.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id	  = azurerm_public_ip.pip.id
  }
}


resource "random_password" "password" {
  length           = 16
  min_upper	   = 1
  min_numeric      = 1
  min_lower        = 1
  special          = true
  override_special = "_%@"
}

resource "azurerm_linux_virtual_machine" "vm" {
  name                            = "${var.prefix}-target-vm"
  resource_group_name             = azurerm_resource_group.rg.name
  location                        = azurerm_resource_group.rg.location
  size                            = "Standard_B1s"
  admin_username                  = var.vm_username
  admin_password                  = random_password.password.result
  disable_password_authentication = false
  network_interface_ids = [
    azurerm_network_interface.nic.id,
  ]

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'F-Secure Azure Attack Detection Workshop - sample sensitive data' >  ~/sensitive-info.txt",
    ]

    connection {
      host     = self.public_ip_address
      user     = self.admin_username
      password = self.admin_password
    }
  }
}

resource "azurerm_public_ip" "attack-pip" {
  name                = "${var.prefix}-attack-pip"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  allocation_method   = "Dynamic"
}

resource "azurerm_network_interface" "attack-nic" {
  name                = "${var.prefix}-attack-nic"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.internal.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id	  = azurerm_public_ip.attack-pip.id
  }
}

resource "azurerm_linux_virtual_machine" "attack-vm" {
  name                            = "${var.prefix}-attack-vm"
  resource_group_name             = azurerm_resource_group.rg.name
  location                        = azurerm_resource_group.rg.location
  size                            = "Standard_B1s"
  admin_username                  = var.vm_username
  admin_password                  = random_password.password.result
  disable_password_authentication = false
  network_interface_ids = [
    azurerm_network_interface.attack-nic.id,
  ]

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
  }
}

############
# Accounts #
############

resource "random_password" "victim-password" {
  length           = 16
  min_upper        = 1
  min_numeric      = 1
  min_lower        = 1
  special          = true
  override_special = "_%@"
}

resource "azuread_user" "victim" {
  user_principal_name = "sidney.brown@${var.tenant}"
  display_name        = "Sidney Brown"
  mail_nickname       = "Sidney"
  password            = random_password.victim-password.result
}

### Contributor SPN setup ###
resource "azuread_application" "contributor-app" {
  name                       = "resource-tracker-app"
  homepage                   = "http://resource-tracker"
  identifier_uris            = ["http://resource-tracker"]
  reply_urls                 = ["http://resource-tracker"]
  available_to_other_tenants = false
  oauth2_allow_implicit_flow = true
}

resource "azuread_service_principal" "contributor-spn" {
  application_id               = azuread_application.contributor-app.application_id
  app_role_assignment_required = false

}

resource "random_password" "contributor-spn-password" {
  length           = 16
  min_upper        = 1
  min_numeric      = 1
  min_lower        = 1
  special          = true
  override_special = "_%@"
}

resource "azuread_service_principal_password" "contributor-spn-password" {
  service_principal_id = azuread_service_principal.contributor-spn.id
  description          = "My managed password"
  value                = random_password.contributor-spn-password.result
  end_date             = "2099-01-01T01:02:03Z"
}

resource "azurerm_role_assignment" "contributor-assignment" {
  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.contributor-spn.object_id
}

### Reader SPN Setup ###
resource "azuread_application" "reader-app" {
  name                       = "ad-lab-app"
  homepage                   = "http://ad-lab"
  identifier_uris            = ["http://ad-lab"]
  reply_urls                 = ["http://ad-lab"]
  available_to_other_tenants = false
  oauth2_allow_implicit_flow = true
}

resource "azuread_service_principal" "reader-spn" {
  application_id               = azuread_application.reader-app.application_id
  app_role_assignment_required = false

}

resource "random_password" "reader-spn-password" {
  length           = 16
  min_upper        = 1
  min_numeric      = 1
  min_lower        = 1
  special          = true
  override_special = "_%@"
}

resource "azuread_service_principal_password" "reader-spn-password" {
  service_principal_id = azuread_service_principal.reader-spn.id
  description          = "My managed password"
  value                = random_password.contributor-spn-password.result
  end_date             = "2099-01-01T01:02:03Z"
}


resource "azurerm_role_assignment" "reader-assignment" {
  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Reader"
  principal_id         = azuread_service_principal.reader-spn.object_id
}



###########
# Outputs #
###########
data "azurerm_public_ip" "vm-ip-data" {
    name		= azurerm_public_ip.pip.name
    resource_group_name = azurerm_resource_group.rg.name
}

data "azurerm_public_ip" "vm-attack-ip-data" {
    name		= azurerm_public_ip.attack-pip.name
    resource_group_name = azurerm_resource_group.rg.name
}

output "vm_ip_address" {
  value		= data.azurerm_public_ip.vm-ip-data.ip_address
}

output "atack_vm_ip_address" {
  value		= data.azurerm_public_ip.vm-attack-ip-data.ip_address
}

output "vm_username" {
  value		= var.vm_username
}

output "vm_password" {
  value		= random_password.password.result
  sensitive     = true
}

output "victim_email_address" {
  value        = azuread_user.victim.mail
}

output "victim_password" {
  value        = random_password.victim-password.result
  sensitive    = true
}

output "contributor-client-id" {
  value        = azuread_application.contributor-app.application_id
}

output "contributor-spn-password" {
 value	       = random_password.contributor-spn-password.result
 sensitive     = true
}

output "reader-client-id" {
  value        = azuread_application.reader-app.application_id
}

output "reader-spn-password" {
 value	       = random_password.reader-spn-password.result
 sensitive     = true
}
