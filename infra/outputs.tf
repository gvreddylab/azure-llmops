output "key_vault_uri" {
  value = azurerm_key_vault.llmKeyVault.vault_uri
}

output "storage_account_name" {
  value = azurerm_storage_account.llmops.name
}

output "search_service_name" {
  value = azurerm_search_service.llmops.name
}

output "app_insights_connection_string" {
  value     = azurerm_application_insights.llmops.connection_string
  sensitive = true
}

output "acr_login_server" {
  value = azurerm_container_registry.llmops.login_server
}

output "orchestrator_url" {
  value = "https://${azurerm_container_app.orchestrator.ingress[0].fqdn}"
}