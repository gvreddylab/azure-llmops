resource "azurerm_resource_group" "llmresgrp" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_key_vault" "llmKeyVault" {
  name                       = "${var.project_name}-kv"
  location                   = azurerm_resource_group.llmresgrp.location
  resource_group_name        = azurerm_resource_group.llmresgrp.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  public_network_access_enabled = false
  enable_rbac_authorization  = true
}

data "azurerm_client_config" "current" {}

resource "azurerm_storage_account" "llmops" {
  name                     = "${var.project_name}sa"
  resource_group_name      = azurerm_resource_group.llmresgrp.name
  location                 = azurerm_resource_group.llmresgrp.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "documents" {
  name                  = "documents"
  storage_account_name  = azurerm_storage_account.llmops.name
  container_access_type = "private"
}

resource "azurerm_log_analytics_workspace" "llmops" {
  name                = "${var.project_name}-law"
  location            = azurerm_resource_group.llmresgrp.location
  resource_group_name = azurerm_resource_group.llmresgrp.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_application_insights" "llmops" {
  name                = "${var.project_name}-appinsights"
  location            = azurerm_resource_group.llmresgrp.location
  resource_group_name = azurerm_resource_group.llmresgrp.name
  workspace_id        = azurerm_log_analytics_workspace.llmops.id
  application_type    = "web"
}

resource "azurerm_search_service" "llmops" {
  name                = "${var.project_name}-search"
  resource_group_name = azurerm_resource_group.llmresgrp.name
  location            = azurerm_resource_group.llmresgrp.location
  sku                 = "basic"
  public_network_access_enabled = false

  local_authentication_enabled = true
  authentication_failure_mode  = "http401WithBearerChallenge"
}

resource "azurerm_role_assignment" "personal_search_data" {
  scope                = azurerm_search_service.llmops.id
  role_definition_name = "Search Index Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "personal_search_service" {
  scope                = azurerm_search_service.llmops.id
  role_definition_name = "Search Service Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "kv_admin" {
  scope                = azurerm_key_vault.llmKeyVault.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_container_registry" "llmops" {
  name                = "${var.project_name}acr"
  resource_group_name = azurerm_resource_group.llmresgrp.name
  location             = azurerm_resource_group.llmresgrp.location
  sku                   = "Basic"
  admin_enabled         = false
}

resource "azurerm_user_assigned_identity" "orchestrator" {
  name                = "${var.project_name}-orchestrator-identity"
  resource_group_name = azurerm_resource_group.llmresgrp.name
  location             = azurerm_resource_group.llmresgrp.location
}

resource "azurerm_role_assignment" "acr_pull" {
  scope                = azurerm_container_registry.llmops.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.orchestrator.principal_id
}

resource "azurerm_container_app" "orchestrator" {
  name                         = "llmops-orchestrator"
  container_app_environment_id = azurerm_container_app_environment.llmops_vnet.id
  resource_group_name          = azurerm_resource_group.llmresgrp.name
  revision_mode                 = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.orchestrator.id]
  }

  registry {
    server   = azurerm_container_registry.llmops.login_server
    identity = azurerm_user_assigned_identity.orchestrator.id
  }

  template {
    container {
      name   = "orchestrator"
      image  = "${azurerm_container_registry.llmops.login_server}/llmops-orchestrator:v1"
      cpu    = 0.5
      memory = "1Gi"

      env {
        name  = "AZURE_CLIENT_ID"
        value = azurerm_user_assigned_identity.orchestrator.client_id
      }
      # ingress[0].fqdn is the stable internal hostname (no revision suffix).
      # latest_revision_fqdn changes on every LiteLLM redeploy and would break routing.
      env {
        name  = "LITELLM_INTERNAL_URL"
        value = azurerm_container_app.litellm.ingress[0].fqdn
      }
    }
  }

  ingress {
    external_enabled = true
    target_port       = 8000
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  depends_on = [azurerm_role_assignment.acr_pull]

  lifecycle {
    ignore_changes = [template[0].container[0].image]
  }
}

resource "azurerm_role_assignment" "orchestrator_kv_secrets" {
  scope                = azurerm_key_vault.llmKeyVault.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.orchestrator.principal_id
}

resource "azurerm_role_assignment" "orchestrator_search_data" {
  scope                = azurerm_search_service.llmops.id
  role_definition_name = "Search Index Data Contributor"
  principal_id         = azurerm_user_assigned_identity.orchestrator.principal_id
}