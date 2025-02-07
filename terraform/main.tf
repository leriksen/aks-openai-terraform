terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.0"
    }
  }

  cloud {
    organization = "#{hcp_organization}#"
    hostname     = "#{hcp_hostname}#"
  }
}

provider "azurerm" {
  features {}
}

locals {
  storage_account_prefix = "boot"
}

data "azurerm_client_config" "current" {
}

resource "random_string" "prefix" {
  length  = 6
  special = false
  upper   = false
  numeric = false
}

resource "random_string" "storage_account_suffix" {
  length  = 8
  special = false
  lower   = true
  upper   = false
  numeric  = false
}

resource "azurerm_resource_group" "rg" {
  name     = var.name_prefix == null ? "${random_string.prefix.result}${var.resource_group_name}" : "${var.name_prefix}${var.resource_group_name}"
  location = var.location
  tags     = var.tags
}

module "log_analytics_workspace" {
  source                           = "./modules/log_analytics"
  name                             = var.name_prefix == null ? "${random_string.prefix.result}${var.log_analytics_workspace_name}" : "${var.name_prefix}${var.log_analytics_workspace_name}"
  location                         = var.location
  resource_group_name              = azurerm_resource_group.rg.name
  solution_plan_map                = var.solution_plan_map
  daily_quota_gb                   = var.daily_quota_gb
  tags                             = var.tags
}

module "virtual_network" {
  source                       = "./modules/virtual_network"
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = var.location
  vnet_name                    = var.name_prefix == null ? "${random_string.prefix.result}${var.vnet_name}" : "${var.name_prefix}${var.vnet_name}"
  address_space                = var.vnet_address_space
  log_analytics_workspace_id   = module.log_analytics_workspace.id
  log_analytics_retention_days = var.log_analytics_retention_days
  tags                         = var.tags

  subnets = [
    {
      name : var.system_node_pool_subnet_name
      address_prefixes : var.system_node_pool_subnet_address_prefix
      private_endpoint_network_policies_enabled : "Enabled"
      private_link_service_network_policies_enabled : false
      delegation: null
    },
    {
      name : var.user_node_pool_subnet_name
      address_prefixes : var.user_node_pool_subnet_address_prefix
      private_endpoint_network_policies_enabled : "Enabled"
      private_link_service_network_policies_enabled : false
      delegation: null
    },
    {
      name : var.pod_subnet_name
      address_prefixes : var.pod_subnet_address_prefix
      private_endpoint_network_policies_enabled : "Enabled"
      private_link_service_network_policies_enabled : false
      delegation: "Microsoft.ContainerService/managedClusters"
    },
    {
      name : var.vm_subnet_name
      address_prefixes : var.vm_subnet_address_prefix
      private_endpoint_network_policies_enabled : "Enabled"
      private_link_service_network_policies_enabled : false
      delegation: null
    },
    {
      name : "AzureBastionSubnet"
      address_prefixes : var.bastion_subnet_address_prefix
      private_endpoint_network_policies_enabled : "Enabled"
      private_link_service_network_policies_enabled : false
      delegation: null
    }
  ]
}

module "nat_gateway" {
  source                       = "./modules/nat_gateway"
  name                         = var.name_prefix == null ? "${random_string.prefix.result}${var.nat_gateway_name}" : "${var.name_prefix}${var.nat_gateway_name}"
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = var.location
  sku_name                     = var.nat_gateway_sku_name
  idle_timeout_in_minutes      = var.nat_gateway_idle_timeout_in_minutes
  zones                        = var.nat_gateway_zones
  tags                         = var.tags
  subnet_ids                   = module.virtual_network.subnet_ids
}

module "container_registry" {
  source                       = "./modules/container_registry"
  name                         = var.name_prefix == null ? "${random_string.prefix.result}${var.acr_name}" : "${var.name_prefix}${var.acr_name}"
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = var.location
  sku                          = var.acr_sku
  admin_enabled                = var.acr_admin_enabled
  georeplication_locations     = var.acr_georeplication_locations
  log_analytics_workspace_id   = module.log_analytics_workspace.id
  log_analytics_retention_days = var.log_analytics_retention_days
  tags                         = var.tags

}

module "aks_cluster" {
  source                                  = "./modules/aks"
  name                                    = var.name_prefix == null ? "${random_string.prefix.result}${var.aks_cluster_name}" : "${var.name_prefix}${var.aks_cluster_name}"
  location                                = var.location
  resource_group_name                     = azurerm_resource_group.rg.name
  resource_group_id                       = azurerm_resource_group.rg.id
  kubernetes_version                      = var.kubernetes_version
  dns_prefix                              = lower(var.aks_cluster_name)
  private_cluster_enabled                 = var.private_cluster_enabled
  automatic_channel_upgrade               = var.automatic_channel_upgrade
  sku_tier                                = var.sku_tier
  system_node_pool_name                   = var.system_node_pool_name
  system_node_pool_vm_size                = var.system_node_pool_vm_size
  vnet_subnet_id                          = module.virtual_network.subnet_ids[var.system_node_pool_subnet_name]
  pod_subnet_id                           = module.virtual_network.subnet_ids[var.pod_subnet_name]
  system_node_pool_availability_zones     = var.system_node_pool_availability_zones
  system_node_pool_node_labels            = var.system_node_pool_node_labels
  system_node_pool_enable_auto_scaling    = var.system_node_pool_enable_auto_scaling
  system_node_pool_enable_host_encryption = var.system_node_pool_enable_host_encryption
  system_node_pool_enable_node_public_ip  = var.system_node_pool_enable_node_public_ip
  system_node_pool_max_pods               = var.system_node_pool_max_pods
  system_node_pool_max_count              = var.system_node_pool_max_count
  system_node_pool_min_count              = var.system_node_pool_min_count
  system_node_pool_node_count             = var.system_node_pool_node_count
  system_node_pool_os_disk_type           = var.system_node_pool_os_disk_type
  tags                                    = var.tags
  network_dns_service_ip                  = var.network_dns_service_ip
  network_plugin                          = var.network_plugin
  outbound_type                           = "userAssignedNATGateway"
  network_service_cidr                    = var.network_service_cidr
  log_analytics_workspace_id              = module.log_analytics_workspace.id
  role_based_access_control_enabled       = var.role_based_access_control_enabled
  tenant_id                               = data.azurerm_client_config.current.tenant_id
  admin_group_object_ids                  = var.admin_group_object_ids
  azure_rbac_enabled                      = var.azure_rbac_enabled
  admin_username                          = var.admin_username
  ssh_public_key                          = var.ssh_public_key
  keda_enabled                            = var.keda_enabled
  vertical_pod_autoscaler_enabled         = var.vertical_pod_autoscaler_enabled
  workload_identity_enabled               = var.workload_identity_enabled
  oidc_issuer_enabled                     = var.oidc_issuer_enabled
  open_service_mesh_enabled               = var.open_service_mesh_enabled
  image_cleaner_enabled                   = var.image_cleaner_enabled
  azure_policy_enabled                    = var.azure_policy_enabled
  http_application_routing_enabled        = var.http_application_routing_enabled

  depends_on = [
    module.nat_gateway,
    module.container_registry
  ]
}

module "node_pool" {
  source = "./modules/node_pool"
  resource_group_name = azurerm_resource_group.rg.name
  kubernetes_cluster_id = module.aks_cluster.id
  name                         = var.user_node_pool_name
  vm_size                      = var.user_node_pool_vm_size
  mode                         = var.user_node_pool_mode
  node_labels                  = var.user_node_pool_node_labels
  node_taints                  = var.user_node_pool_node_taints
  availability_zones           = var.user_node_pool_availability_zones
  vnet_subnet_id               = module.virtual_network.subnet_ids[var.user_node_pool_subnet_name]
  pod_subnet_id                = module.virtual_network.subnet_ids[var.pod_subnet_name]
  enable_auto_scaling          = var.user_node_pool_enable_auto_scaling
  enable_host_encryption       = var.user_node_pool_enable_host_encryption
  enable_node_public_ip        = var.user_node_pool_enable_node_public_ip
  orchestrator_version         = var.kubernetes_version
  max_pods                     = var.user_node_pool_max_pods
  max_count                    = var.user_node_pool_max_count
  min_count                    = var.user_node_pool_min_count
  node_count                   = var.user_node_pool_node_count
  os_type                      = var.user_node_pool_os_type
  priority                     = var.user_node_pool_priority
  tags                         = var.tags
}

module "openai" {
  source                                   = "./modules/openai"
  name                                     = var.name_prefix == null ? "${random_string.prefix.result}${var.openai_name}" : "${var.name_prefix}${var.openai_name}"
  location                                 = var.location
  resource_group_name                      = azurerm_resource_group.rg.name
  sku_name                                 = var.openai_sku_name
  tags                                     = var.tags
  deployments                              = var.openai_deployments
  custom_subdomain_name                    = var.openai_custom_subdomain_name == "" || var.openai_custom_subdomain_name == null ? var.name_prefix == null ? lower("${random_string.prefix.result}${var.openai_name}") : lower("${var.name_prefix}${var.openai_name}") : lower(var.openai_custom_subdomain_name)
  public_network_access_enabled            = var.openai_public_network_access_enabled
  log_analytics_workspace_id               = module.log_analytics_workspace.id
  log_analytics_retention_days             = var.log_analytics_retention_days
}

resource "azurerm_user_assigned_identity" "aks_workload_identity" {
  name                = var.name_prefix == null ? "${random_string.prefix.result}${var.workload_managed_identity_name}" : "${var.name_prefix}${var.workload_managed_identity_name}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  tags                = var.tags

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_role_assignment" "cognitive_services_user_assignment" {
  scope                = module.openai.id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_user_assigned_identity.aks_workload_identity.principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_federated_identity_credential" "federated_identity_credential" {
  name                = "${title(var.namespace)}FederatedIdentity"
  resource_group_name = azurerm_resource_group.rg.name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = module.aks_cluster.oidc_issuer_url
  parent_id           = azurerm_user_assigned_identity.aks_workload_identity.id
  subject             = "system:serviceaccount:${var.namespace}:${var.service_account_name}"
}

resource "azurerm_role_assignment" "network_contributor_assignment" {
  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Network Contributor"
  principal_id         = module.aks_cluster.aks_identity_principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "acr_pull_assignment" {
  role_definition_name = "AcrPull"
  scope                = module.container_registry.id
  principal_id         = module.aks_cluster.kubelet_identity_object_id
  skip_service_principal_aad_check = true
}

module "storage_account" {
  source                      = "./modules/storage_account"
  name                        = "${local.storage_account_prefix}${random_string.storage_account_suffix.result}"
  location                    = var.location
  resource_group_name         = azurerm_resource_group.rg.name
  account_kind                = var.storage_account_kind
  account_tier                = var.storage_account_tier
  replication_type            = var.storage_account_replication_type
  tags                        = var.tags

}

module "bastion_host" {
  source                       = "./modules/bastion_host"
  name                         = var.name_prefix == null ? "${random_string.prefix.result}${var.bastion_host_name}" : "${var.name_prefix}${var.bastion_host_name}"
  location                     = var.location
  resource_group_name          = azurerm_resource_group.rg.name
  subnet_id                    = module.virtual_network.subnet_ids["AzureBastionSubnet"]
  log_analytics_workspace_id   = module.log_analytics_workspace.id
  log_analytics_retention_days = var.log_analytics_retention_days
  tags                         = var.tags
}

module "virtual_machine" {
  count                               = var.vm_enabled ? 1 : 0
  source                              = "./modules/virtual_machine"
  name                                = var.name_prefix == null ? "${random_string.prefix.result}${var.vm_name}" : "${var.name_prefix}${var.vm_name}"
  size                                = var.vm_size
  location                            = var.location
  public_ip                           = var.vm_public_ip
  vm_user                             = var.admin_username
  admin_ssh_public_key                = var.ssh_public_key
  os_disk_image                       = var.vm_os_disk_image
  resource_group_name                 = azurerm_resource_group.rg.name
  subnet_id                           = module.virtual_network.subnet_ids[var.vm_subnet_name]
  os_disk_storage_account_type        = var.vm_os_disk_storage_account_type
  boot_diagnostics_storage_account    = module.storage_account.primary_blob_endpoint
  log_analytics_workspace_id          = module.log_analytics_workspace.workspace_id
  log_analytics_workspace_key         = module.log_analytics_workspace.primary_shared_key
  log_analytics_workspace_resource_id = module.log_analytics_workspace.id
  log_analytics_retention_days        = var.log_analytics_retention_days
  tags                                = var.tags
}

module "key_vault" {
  source                          = "./modules/key_vault"
  name                            = var.name_prefix == null ? "${random_string.prefix.result}${var.key_vault_name}" : "${var.name_prefix}${var.key_vault_name}"
  location                        = var.location
  resource_group_name             = azurerm_resource_group.rg.name
  tenant_id                       = data.azurerm_client_config.current.tenant_id
  sku_name                        = var.key_vault_sku_name
  enabled_for_deployment          = var.key_vault_enabled_for_deployment
  enabled_for_disk_encryption     = var.key_vault_enabled_for_disk_encryption
  enabled_for_template_deployment = var.key_vault_enabled_for_template_deployment
  enable_rbac_authorization       = var.key_vault_enable_rbac_authorization
  purge_protection_enabled        = var.key_vault_purge_protection_enabled
  soft_delete_retention_days      = var.key_vault_soft_delete_retention_days
  bypass                          = var.key_vault_bypass
  default_action                  = var.key_vault_default_action
  log_analytics_workspace_id      = module.log_analytics_workspace.id
  log_analytics_retention_days    = var.log_analytics_retention_days
  tags                            = var.tags
}

module "acr_private_dns_zone" {
  source                       = "./modules/private_dns_zone"
  name                         = "privatelink.azurecr.io"
  resource_group_name          = azurerm_resource_group.rg.name
  tags                         = var.tags
  virtual_networks_to_link     = {
    (module.virtual_network.name) = {
      subscription_id = data.azurerm_client_config.current.subscription_id
      resource_group_name = azurerm_resource_group.rg.name
    }
  }
}

module "openai_private_dns_zone" {
  source                       = "./modules/private_dns_zone"
  name                         = "privatelink.openai.azure.com"
  resource_group_name          = azurerm_resource_group.rg.name
  tags                         = var.tags
  virtual_networks_to_link     = {
    (module.virtual_network.name) = {
      subscription_id = data.azurerm_client_config.current.subscription_id
      resource_group_name = azurerm_resource_group.rg.name
    }
  }
}

module "key_vault_private_dns_zone" {
  source                       = "./modules/private_dns_zone"
  name                         = "privatelink.vaultcore.azure.net"
  resource_group_name          = azurerm_resource_group.rg.name
  tags                         = var.tags
  virtual_networks_to_link     = {
    (module.virtual_network.name) = {
      subscription_id = data.azurerm_client_config.current.subscription_id
      resource_group_name = azurerm_resource_group.rg.name
    }
  }
}

module "blob_private_dns_zone" {
  source                       = "./modules/private_dns_zone"
  name                         = "privatelink.blob.core.windows.net"
  resource_group_name          = azurerm_resource_group.rg.name
  tags                         = var.tags
  virtual_networks_to_link     = {
    (module.virtual_network.name) = {
      subscription_id = data.azurerm_client_config.current.subscription_id
      resource_group_name = azurerm_resource_group.rg.name
    }
  }
}

module "openai_private_endpoint" {
  source                         = "./modules/private_endpoint"
  name                           = "${module.openai.name}PrivateEndpoint"
  location                       = var.location
  resource_group_name            = azurerm_resource_group.rg.name
  subnet_id                      = module.virtual_network.subnet_ids[var.vm_subnet_name]
  tags                           = var.tags
  private_connection_resource_id = module.openai.id
  is_manual_connection           = false
  subresource_name               = "account"
  private_dns_zone_group_name    = "AcrPrivateDnsZoneGroup"
  private_dns_zone_group_ids     = [module.openai_private_dns_zone.id]
}

module "acr_private_endpoint" {
  source                         = "./modules/private_endpoint"
  name                           = "${module.container_registry.name}PrivateEndpoint"
  location                       = var.location
  resource_group_name            = azurerm_resource_group.rg.name
  subnet_id                      = module.virtual_network.subnet_ids[var.vm_subnet_name]
  tags                           = var.tags
  private_connection_resource_id = module.container_registry.id
  is_manual_connection           = false
  subresource_name               = "registry"
  private_dns_zone_group_name    = "AcrPrivateDnsZoneGroup"
  private_dns_zone_group_ids     = [module.acr_private_dns_zone.id]
}

module "key_vault_private_endpoint" {
  source                         = "./modules/private_endpoint"
  name                           = "${module.key_vault.name}PrivateEndpoint"
  location                       = var.location
  resource_group_name            = azurerm_resource_group.rg.name
  subnet_id                      = module.virtual_network.subnet_ids[var.vm_subnet_name]
  tags                           = var.tags
  private_connection_resource_id = module.key_vault.id
  is_manual_connection           = false
  subresource_name               = "vault"
  private_dns_zone_group_name    = "KeyVaultPrivateDnsZoneGroup"
  private_dns_zone_group_ids     = [module.key_vault_private_dns_zone.id]
}

module "blob_private_endpoint" {
  source                         = "./modules/private_endpoint"
  name                           = var.name_prefix == null ? "${random_string.prefix.result}BlocStoragePrivateEndpoint" : "${var.name_prefix}BlobStoragePrivateEndpoint"
  location                       = var.location
  resource_group_name            = azurerm_resource_group.rg.name
  subnet_id                      = module.virtual_network.subnet_ids[var.vm_subnet_name]
  tags                           = var.tags
  private_connection_resource_id = module.storage_account.id
  is_manual_connection           = false
  subresource_name               = "blob"
  private_dns_zone_group_name    = "BlobPrivateDnsZoneGroup"
  private_dns_zone_group_ids     = [module.blob_private_dns_zone.id]
}

module "deployment_script" {
  source                              = "./modules/deployment_script"
  name                                = var.name_prefix == null ? "${random_string.prefix.result}${var.deployment_script_name}" : "${var.name_prefix}${var.deployment_script_name}"
  location                            = var.location
  resource_group_name                 = azurerm_resource_group.rg.name
  azure_cli_version                   = var.deployment_script_azure_cli_version
  managed_identity_name               = var.name_prefix == null ? "${random_string.prefix.result}${var.deployment_script_managed_identity_name}" : "${var.name_prefix}${var.deployment_script_managed_identity_name}"
  aks_cluster_name                    = module.aks_cluster.name
  hostname                            = "${var.subdomain}.${var.domain}"
  namespace                           = var.namespace
  service_account_name                = var.service_account_name
  email                               = var.email
  primary_script_uri                  = var.deployment_script_primary_script_uri
  tenant_id                           = data.azurerm_client_config.current.tenant_id
  subscription_id                     = data.azurerm_client_config.current.subscription_id
  workload_managed_identity_client_id = azurerm_user_assigned_identity.aks_workload_identity.client_id
  tags                                = var.tags

  depends_on = [ 
    module.aks_cluster
   ]
}
