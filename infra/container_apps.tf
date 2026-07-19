resource "azurerm_container_app_environment" "llmops_vnet" {
  name                        = "${var.project_name}-env-vnet"
  location                     = azurerm_resource_group.llmresgrp.location
  resource_group_name          = azurerm_resource_group.llmresgrp.name
  log_analytics_workspace_id   = azurerm_log_analytics_workspace.llmops.id
  infrastructure_subnet_id     = azurerm_subnet.container_apps.id
  lifecycle {
    ignore_changes = [infrastructure_resource_group_name]
  }
}

resource "azurerm_container_app" "litellm" {
  name                         = "litellm-gateway"
  container_app_environment_id = azurerm_container_app_environment.llmops_vnet.id
  resource_group_name          = azurerm_resource_group.llmresgrp.name
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.orchestrator.id]
  }

  registry {
    server   = azurerm_container_registry.llmops.login_server
    identity = azurerm_user_assigned_identity.orchestrator.id
  }

  template {
    min_replicas = 1
    max_replicas = 1

    container {
      name   = "litellm"
      image  = "${azurerm_container_registry.llmops.login_server}/litellm-gateway:v1"
      cpu    = 1.0
      memory = "2Gi"

      env {
        name  = "AZURE_CLIENT_ID"
        value = azurerm_user_assigned_identity.orchestrator.client_id
      }
      env {
        name        = "AZURE_OPENAI_ENDPOINT"
        secret_name = "openai-endpoint"
      }
      env {
        name        = "AZURE_OPENAI_API_KEY"
        secret_name = "openai-key"
      }
      env {
        name        = "LITELLM_MASTER_KEY"
        secret_name = "litellm-key"
      }
      env {
        name        = "GROQ_API_KEY"
        secret_name = "groq-key"
      }
      env {
        name        = "DATABASE_URL"
        secret_name = "db-url"
      }
      env {
        name        = "SLACK_WEBHOOK_URL"
        secret_name = "slack-webhook"
      }
    }
  }

  secret {
    name                = "openai-endpoint"
    key_vault_secret_id = "https://llmopslearn-kv.vault.azure.net/secrets/foundry-endpoint"
    identity            = azurerm_user_assigned_identity.orchestrator.id
  }
  secret {
    name                = "openai-key"
    key_vault_secret_id = "https://llmopslearn-kv.vault.azure.net/secrets/foundry-api-key"
    identity            = azurerm_user_assigned_identity.orchestrator.id
  }
  secret {
    name                = "litellm-key"
    key_vault_secret_id = "https://llmopslearn-kv.vault.azure.net/secrets/litellm-master-key"
    identity            = azurerm_user_assigned_identity.orchestrator.id
  }
  secret {
    name                = "groq-key"
    key_vault_secret_id = "https://llmopslearn-kv.vault.azure.net/secrets/groq-api-key"
    identity            = azurerm_user_assigned_identity.orchestrator.id
  }
  secret {
    name                = "db-url"
    key_vault_secret_id = "https://llmopslearn-kv.vault.azure.net/secrets/litellm-db-url"
    identity            = azurerm_user_assigned_identity.orchestrator.id
  }
  secret {
    name                = "slack-webhook"
    key_vault_secret_id = "https://llmopslearn-kv.vault.azure.net/secrets/litellm-slack-webhook"
    identity            = azurerm_user_assigned_identity.orchestrator.id
  }

  ingress {
    external_enabled = false
    target_port       = 4000
    transport         = "auto"
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  lifecycle {
    ignore_changes = [template[0].container[0].image]
  }
}

output "litellm_internal_url" {
  value = azurerm_container_app.litellm.latest_revision_fqdn
}