// Scope
targetScope = 'subscription'

// Parameters
@description('Resource group where Microsoft Fabric capacity will be deployed. Resource group will be created if it doesnt exist')
param dprg string= 'rg-fabric-s01'

@description('Resource group location')
param rglocation string = 'westeurope'

@description('Cost Centre tag that will be applied to all resources in this deployment')
param cost_centre_tag string = 'MCAPS'

@description('System Owner tag that will be applied to all resources in this deployment')
param owner_tag string = 'patrick.barkowski@strategicitkiplayground.onmicrosoft.com'

@description('Subject Matter EXpert (SME) tag that will be applied to all resources in this deployment')
param sme_tag string ='patrick.barkowski@strategicitkiplayground.onmicrosoft.com'

@description('Timestamp that will be appendedto the deployment name')
param deployment_suffix string = utcNow()

@description('Resource group where Purview will be deployed. Resource group will be created if it doesnt exist')
param purviewrg string= 'rg-datagovernance'

@description('Flag to indicate whether to create a new Purview resource with this data platform deployment')
param create_purview bool = false

@description('Flag to indicate whether to enable integration of data platform resources with either an existing or new Purview resource')
param enable_purview bool = false

@description('Resource Name of new or existing Purview Account. Specify a resource name if create_purview=true or enable_purview=true')
param purview_name string = 'SitDG'

@description('Resource group where audit resources will be deployed. Resource group will be created if it doesnt exist')
param auditrg string= 'rg-audit'


// Variables
var fabric_deployment_name = 'fabric_dataplatform_deployment_${deployment_suffix}'
var purview_deployment_name = 'purview_deployment_${deployment_suffix}'
var keyvault_deployment_name = 'keyvault_deployment_${deployment_suffix}'
var audit_deployment_name = 'audit_deployment_${deployment_suffix}'
var controldb_deployment_name = 'controldb_deployment_${deployment_suffix}'

// Create data platform resource group
resource fabric_rg  'Microsoft.Resources/resourceGroups@2024-03-01' = {
 name: dprg 
 location: rglocation
 tags: {
        CostCentre: cost_centre_tag
        Owner: owner_tag
        SME: sme_tag
  }
}


// Create purview resource group
resource purview_rg  'Microsoft.Resources/resourceGroups@2024-03-01' = if (create_purview) {
  name: purviewrg 
  location: rglocation
  tags: {
         CostCentre: cost_centre_tag
         Owner: owner_tag
         SME: sme_tag
   }
 }

 // Create audit resource group
resource audit_rg  'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: auditrg 
  location: rglocation
  tags: {
         CostCentre: cost_centre_tag
         Owner: owner_tag
         SME: sme_tag
   }
 }


 // Deploy Purview using module
module purview './modules/purview.bicep' = if (create_purview || enable_purview) {
  name: purview_deployment_name
  scope: purview_rg
  params:{
    create_purview: create_purview
    purviewrg: purviewrg
    purview_name: purview_name
    location: purview_rg.location
    cost_centre_tag: cost_centre_tag
    owner_tag: owner_tag
    sme_tag: sme_tag
  }
  
}

// Deploy Key Vault with default access policies using module
module kv './modules/keyvault.bicep' = {
  name: keyvault_deployment_name
  scope: fabric_rg
  params:{
     location: fabric_rg.location
     keyvault_name: 'ba-kv01'
     cost_centre_tag: cost_centre_tag
     owner_tag: owner_tag
     sme_tag: sme_tag
     purview_account_name: purview.outputs.purview_account_name
     purviewrg: purviewrg
  }
}

resource kv_ref 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: kv.outputs.keyvault_name
  scope: fabric_rg
}

//Enable auditing for data platform resources
module audit_integration './modules/audit.bicep' = {
  name: audit_deployment_name
  scope: audit_rg
  params:{
    location: audit_rg.location
    cost_centre_tag: cost_centre_tag
    owner_tag: owner_tag
    sme_tag: sme_tag
    audit_storage_name: 'baauditstorage01'
    audit_storage_sku: 'Standard_LRS'    
    audit_loganalytics_name: 'ba-loganalytics01'
  }
}

//Deploy Microsoft Fabric Capacity
module fabric_capacity './modules/fabric-capacity.bicep' = {
  name: fabric_deployment_name
  scope: fabric_rg
  params:{
    fabric_name: 'bafabric01'
    location: fabric_rg.location
    cost_centre_tag: cost_centre_tag
    owner_tag: owner_tag
    sme_tag: sme_tag
    adminUsers: kv_ref.getSecret('fabric-capacity-admin-username')
  }
}

//Deploy SQL control DB 
module controldb './modules/sqldb.bicep' = {
  name: controldb_deployment_name
  scope: fabric_rg
  params:{
     sqlserver_name: 'ba-sql01'
     database_name: 'controlDB' 
     location: fabric_rg.location
     cost_centre_tag: cost_centre_tag
     owner_tag: owner_tag
     sme_tag: sme_tag
     sql_admin_username: kv_ref.getSecret('sqlserver-admin-username')
     sql_admin_password: kv_ref.getSecret('sqlserver-admin-password')
     ad_admin_username:  kv_ref.getSecret('sqlserver-ad-admin-username')
     ad_admin_sid:  kv_ref.getSecret('sqlserver-ad-admin-sid')  
     auto_pause_duration: 60
     database_sku_name: 'GP_S_Gen5_1' 
     enable_purview: enable_purview
     purview_resource: purview.outputs.purview_resource
     audit_storage_name: audit_integration.outputs.audit_storage_uniquename
     auditrg: audit_rg.name
  }
}
