# Writes all runtime secrets into Key Vault so the orchestrator and ingestion script
# never need hard-coded credentials.
#
# IMPORTANT: Key Vault has public_network_access_enabled = false.
# The Terraform runner must be connected to the Tailscale VPN before applying
# these resources, otherwise the azurerm provider cannot reach the Key Vault
# data plane to create/update secrets.
#
# Two-phase apply:
#   Phase 1 (no VPN required): terraform apply -target=... (all except this file)
#   Phase 2 (VPN required):    tailscale up && terraform apply

locals {
  kv_id = azurerm_key_vault.llmKeyVault.id
}

resource "azurerm_key_vault_secret" "foundry_endpoint" {
  name         = "foundry-endpoint"
  value        = data.azurerm_cognitive_account.foundry.endpoint
  key_vault_id = local.kv_id

  depends_on = [azurerm_private_endpoint.keyvault]
}

resource "azurerm_key_vault_secret" "foundry_api_key" {
  name         = "foundry-api-key"
  value        = data.azurerm_cognitive_account.foundry.primary_access_key
  key_vault_id = local.kv_id

  depends_on = [azurerm_private_endpoint.keyvault]
}

resource "azurerm_key_vault_secret" "chat_deployment_name" {
  name         = "chat-deployment-name"
  value        = var.chat_deployment_name
  key_vault_id = local.kv_id

  depends_on = [azurerm_private_endpoint.keyvault, azapi_resource.chat_deployment]
}

resource "azurerm_key_vault_secret" "embedding_deployment_name" {
  name         = "embedding-deployment-name"
  value        = var.embedding_deployment_name
  key_vault_id = local.kv_id

  depends_on = [azurerm_private_endpoint.keyvault, azapi_resource.embedding_deployment]
}

resource "azurerm_key_vault_secret" "appinsights_connection_string" {
  name         = "appinsights-connection-string"
  value        = azurerm_application_insights.llmops.connection_string
  key_vault_id = local.kv_id

  depends_on = [azurerm_private_endpoint.keyvault]
}

resource "azurerm_key_vault_secret" "litellm_db_url" {
  name  = "litellm-db-url"
  value = "postgresql://litellmadmin:${random_password.postgres.result}@${azurerm_postgresql_flexible_server.litellm.fqdn}:5432/litellm?sslmode=require"
  key_vault_id = local.kv_id

  depends_on = [
    azurerm_private_endpoint.keyvault,
    azurerm_postgresql_flexible_server_database.litellm,
  ]
}
