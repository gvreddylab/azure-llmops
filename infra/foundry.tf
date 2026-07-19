# Deploys chat and embedding models into the existing Foundry / Azure AI Services account.
# The account itself is managed outside Terraform (referenced via data block in network.tf).
# azapi is used because azurerm has no stable resource for Cognitive Services deployments.
#
# ignore_changes = ["body"] prevents Terraform from re-PUTting the deployment on every apply.
# The body is only used on initial creation; Azure may return extra fields that differ.

resource "azapi_resource" "chat_deployment" {
  type      = "Microsoft.CognitiveServices/accounts/deployments@2024-06-01-preview"
  name      = var.chat_deployment_name
  parent_id = data.azurerm_cognitive_account.foundry.id

  body = jsonencode({
    sku = {
      name     = "GlobalStandard"
      capacity = 250
    }
    properties = {
      model = {
        format  = "OpenAI"
        name    = var.chat_model_name
        version = var.chat_model_version
      }
    }
  })

  response_export_values = ["*"]

  lifecycle {
    ignore_changes = [body]
  }
}

resource "azapi_resource" "embedding_deployment" {
  type      = "Microsoft.CognitiveServices/accounts/deployments@2024-06-01-preview"
  name      = var.embedding_deployment_name
  parent_id = data.azurerm_cognitive_account.foundry.id

  # Foundry only allows one deployment operation at a time per account.
  depends_on = [azapi_resource.chat_deployment]

  body = jsonencode({
    sku = {
      name     = "GlobalStandard"
      capacity = 500
    }
    properties = {
      model = {
        format  = "OpenAI"
        name    = var.embedding_model_name
        version = var.embedding_model_version
      }
    }
  })

  response_export_values = ["*"]

  lifecycle {
    ignore_changes = [body]
  }
}
