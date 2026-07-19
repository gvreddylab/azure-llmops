variable "location" {
  default = "eastus"
}

variable "project_name" {
  default = "llmopslearn"
}

variable "resource_group_name" {
  default = "rg-llmops-learning"
}

variable "vnet_address_space" {
  description = "Address space for the project VNet"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "container_apps_subnet_prefix" {
  description = "CIDR for the Container Apps Environment subnet (needs /23 or larger)"
  type        = list(string)
  default     = ["10.0.0.0/23"]
}

variable "private_endpoints_subnet_prefix" {
  description = "CIDR for the private endpoints subnet"
  type        = list(string)
  default     = ["10.0.3.0/24"]
}

variable "relay_subnet_prefix" {
  description = "CIDR for the relay VM subnet"
  type        = list(string)
  default     = ["10.0.4.0/24"]
}

variable "postgres_subnet_prefix" {
  description = "CIDR for the PostgreSQL Flexible Server delegated subnet"
  type        = list(string)
  default     = ["10.0.5.0/24"]
}

variable "allowed_ssh_source_ip" {
  description = "Your IP address allowed to SSH into the relay VM (format: x.x.x.x/32)"
  type        = string
}

variable "relay_admin_username" {
  description = "Admin username for the relay VM"
  type        = string
  default     = "azureuser"
}

variable "relay_ssh_public_key" {
  description = "Your local SSH public key"
  type        = string
}

variable "tailscale_auth_key" {
  description = "Tailscale reusable auth key"
  type        = string
  sensitive   = true
}

variable "foundry_account_name" {
  description = "Name of the existing Azure AI Foundry / Cognitive Services account"
  type        = string
  default     = "ragmodeldeploy-resource"
}

variable "chat_deployment_name" {
  description = "Deployment name for the chat model (stored in Key Vault and used by the orchestrator)"
  type        = string
  default     = "gpt-5-mini"
}

variable "chat_model_name" {
  description = "Underlying Azure OpenAI model identifier (e.g. gpt-4o-mini, gpt-5-mini)"
  type        = string
  default     = "gpt-5-mini"
}

variable "chat_model_version" {
  description = "Model version string as shown in the Azure AI Foundry portal"
  type        = string
  default     = "2025-08-07"
}

variable "embedding_deployment_name" {
  description = "Deployment name for the embedding model (stored in Key Vault)"
  type        = string
  default     = "text-embedding-3-small"
}

variable "embedding_model_name" {
  description = "Underlying Azure OpenAI embedding model identifier"
  type        = string
  default     = "text-embedding-3-small"
}

variable "embedding_model_version" {
  description = "Embedding model version string"
  type        = string
  default     = "1"
}

variable "github_org" {
  description = "GitHub organisation or username that owns the repository"
  type        = string
  default     = "gvreddylab"
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = "azure-llmops-project"
}