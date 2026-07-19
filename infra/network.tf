resource "azurerm_virtual_network" "llmops" {
  name                = "${var.project_name}-vnet"
  address_space       = var.vnet_address_space
  location             = azurerm_resource_group.llmresgrp.location
  resource_group_name  = azurerm_resource_group.llmresgrp.name
}

resource "azurerm_subnet" "container_apps" {
  name                 = "subnet-container-apps"
  resource_group_name  = azurerm_resource_group.llmresgrp.name
  virtual_network_name = azurerm_virtual_network.llmops.name
  address_prefixes      = var.container_apps_subnet_prefix

  delegation {
    name = "Microsoft.App.environments"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "private_endpoints" {
  name                 = "subnet-private-endpoints"
  resource_group_name  = azurerm_resource_group.llmresgrp.name
  virtual_network_name = azurerm_virtual_network.llmops.name
  address_prefixes      = var.private_endpoints_subnet_prefix
}

resource "azurerm_private_dns_zone" "keyvault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.llmresgrp.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "keyvault" {
  name                  = "kv-dns-link"
  resource_group_name  = azurerm_resource_group.llmresgrp.name
  private_dns_zone_name = azurerm_private_dns_zone.keyvault.name
  virtual_network_id     = azurerm_virtual_network.llmops.id
}

resource "azurerm_private_endpoint" "keyvault" {
  name                = "${var.project_name}-kv-pe"
  location             = azurerm_resource_group.llmresgrp.location
  resource_group_name  = azurerm_resource_group.llmresgrp.name
  subnet_id             = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                            = "kv-privateserviceconnection"
    private_connection_resource_id  = azurerm_key_vault.llmKeyVault.id
    subresource_names                = ["vault"]
    is_manual_connection             = false
  }

  private_dns_zone_group {
    name                  = "kv-dns-zone-group"
    private_dns_zone_ids  = [azurerm_private_dns_zone.keyvault.id]
  }
}

resource "azurerm_private_dns_zone" "search" {
  name                = "privatelink.search.windows.net"
  resource_group_name = azurerm_resource_group.llmresgrp.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "search" {
  name                  = "search-dns-link"
  resource_group_name   = azurerm_resource_group.llmresgrp.name
  private_dns_zone_name = azurerm_private_dns_zone.search.name
  virtual_network_id    = azurerm_virtual_network.llmops.id
}

resource "azurerm_private_endpoint" "search" {
  name                = "${var.project_name}-search-pe"
  location            = azurerm_resource_group.llmresgrp.location
  resource_group_name = azurerm_resource_group.llmresgrp.name
  subnet_id            = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "search-privateserviceconnection"
    private_connection_resource_id = azurerm_search_service.llmops.id
    subresource_names               = ["searchService"]
    is_manual_connection            = false
  }

  private_dns_zone_group {
    name                 = "search-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.search.id]
  }
}

data "azurerm_cognitive_account" "foundry" {
  name                = var.foundry_account_name
  resource_group_name = azurerm_resource_group.llmresgrp.name
}

resource "azurerm_private_dns_zone" "openai" {
  # cognitiveservices.azure.com — correct zone for multi-service Foundry accounts.
  # Classic Azure OpenAI-only accounts use privatelink.openai.azure.com instead.
  name                = "privatelink.cognitiveservices.azure.com"
  resource_group_name = azurerm_resource_group.llmresgrp.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "openai" {
  name                  = "openai-dns-link"
  resource_group_name   = azurerm_resource_group.llmresgrp.name
  private_dns_zone_name = azurerm_private_dns_zone.openai.name
  virtual_network_id    = azurerm_virtual_network.llmops.id
}

resource "azurerm_private_endpoint" "openai" {
  name                = "${var.project_name}-openai-pe"
  location            = azurerm_resource_group.llmresgrp.location
  resource_group_name = azurerm_resource_group.llmresgrp.name
  subnet_id            = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "openai-privateserviceconnection"
    private_connection_resource_id = data.azurerm_cognitive_account.foundry.id
    subresource_names               = ["account"]
    is_manual_connection            = false
  }

  private_dns_zone_group {
    name                 = "openai-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.openai.id]
  }
}