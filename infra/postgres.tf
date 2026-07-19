resource "random_password" "postgres" {
  length  = 32
  special = false
}

# PostgreSQL Flexible Server in canadacentral — eastus and eastus2 are quota-restricted
# for this subscription. Canada Central is <5 ms from East US over Azure backbone.
# Dev/Test workload type, Burstable B2s (2 vCores, 4 GiB) matches portal defaults.
resource "azurerm_postgresql_flexible_server" "litellm" {
  name                          = "${var.project_name}-litellmdb"
  resource_group_name           = azurerm_resource_group.llmresgrp.name
  location                      = "canadacentral"
  version                       = "16"
  administrator_login           = "litellmadmin"
  administrator_password        = random_password.postgres.result
  storage_mb                    = 32768
  sku_name                      = "B_Standard_B2s"
  public_network_access_enabled = true
  backup_retention_days         = 7

  lifecycle {
    ignore_changes = [zone]
  }
}

resource "azurerm_postgresql_flexible_server_firewall_rule" "allow_azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_postgresql_flexible_server.litellm.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

resource "azurerm_postgresql_flexible_server_database" "litellm" {
  name      = "litellm"
  server_id = azurerm_postgresql_flexible_server.litellm.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}
