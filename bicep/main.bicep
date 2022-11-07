@description('Optional. A name that will be prepended to all deployed resources. Defaults to an alphanumeric id that is unique to the resource group.')
param applicationName string = 'hazripaas-${uniqueString(resourceGroup().id)}'

@description('Optional. The Azure region (location) to deploy to. Must be a region that supports availability zones. Defaults to the resource group location.')
param location string = resourceGroup().location

@description('Optional. An Azure tags object for tagging parent resources that support tags.')
param tags object = {
  Project: 'Azure highly-available zone-redundant iPaaS application'
}

@description('Optional. SQL admin username. Defaults to \'\${applicationName}-admin\'')
param sqlAdmin string = '${applicationName}-admin'

@description('Optional. A password for the Azure SQL server admin user. Defaults to a new GUID.')
@secure()
param sqlAdminPassword string = newGuid()

@description('Optional. Name of the SQL database to create. Defaults to \'\${applicationName}-sql-db\'')
param sqlDatabaseName string = '${applicationName}-sql-db'

@description('Optional. Name of the Service Bus queue to create. Defaults to \'Queue1\'')
param servicebusQueueName string = 'Queue1'

param apimPublisherEmail string = 'publisher@localtest.me'
param apimPublisherName string = 'Publisher'

@allowed(['Premium', 'Developer'])
param apimSkuName string = 'Premium'

param enableDdosProtection bool = true


// VARS

// Storage account name must be lowercase, alpha-numeric, and less the 24 chars in length
var functionsStorage = take(toLower(replace('${applicationName}func', '-', '')), 24)

var vnet = '${applicationName}-vnet'

// App GW
var appGw = '${applicationName}-appgw'
var appGwBackendRequestTimeout = 31   // seconds
var appGwPublicFrontendIp = 'appGwPublicFrontendIp'
var publicHttpsListener = 'publicHttpsListener'
var apimBackendPool = 'apimBackendPool'
var backendHttpSettings = 'backendHttpSettings'
var httpRedirectConfiguration = 'httpRedirectConfiguration'
var appGwWafPolicy = '${applicationName}-appgw-waf'
var appGwPip = '${applicationName}-appgw-pip'

// APIM
var apim = '${applicationName}-apim'


var redis = '${applicationName}-cache'

var servicebus = '${applicationName}-bus'

var keyvault = '${applicationName}-kv'
var redisConnectionStringSecretName = 'RedisConnectionString'
var sqlConnectionStringSecretName = 'SqlConnectionString'

var sql = '${applicationName}-sql'

var workspace = '${applicationName}-workspace'
var insights = '${applicationName}-insights'

// Role definition Ids for managed identity role assignments
var roleDefinitionIds = {
  storage: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'                   // Storage Blob Data Contributor
  keyvault: '4633458b-17de-408a-b874-0445c86b69e6'                  // Key Vault Secrets User
  servicebus: '090c5cfd-751d-490a-894a-3ce6f1109419'                // Azure Service Bus Data Owner
}

// Environment specific private link suffixes
//  references: 
//    https://docs.microsoft.com/azure/private-link/private-endpoint-dns
//    https://docs.azure.cn/en-us/articles/guidance/developerdifferences

var privateLinkRedisDnsNames = {
  AzureCloud: 'privatelink.redis.cache.windows.net'
  AzureUSGovernment: 'privatelink.redis.cache.usgovcloudapi.net'
  AzureChinaCloud: 'privatelink.redis.cache.chinacloudapi.cn'
}

var privateLinkServiceBusDnsNames = {
  AzureCloud: 'privatelink.servicebus.windows.net'
  AzureUSGovernment: 'privatelink.servicebus.usgovcloudapi.net'
  AzureChinaCloud: 'privatelink.servicebus.chinacloudapi.cn'
}

var privateLinkKeyVaultDnsNames = {
  AzureCloud: 'privatelink.vaultcore.azure.net'
  AzureUSGovernment: 'privatelink.vaultcore.usgovcloudapi.net'
  AzureChinaCloud: 'privatelink.vaultcore.azure.cn'
}

var apimSuffixes = {
  AzureCloud: {
    Gateway: '.azure-api.net'
    Portal: '.developer.azure-api.net'
    Management: '.management.azure-api.net'
    Scm: '.scm.azure-api.net'
  }
  AzureUSGovernment: {
    Gateway: '.azure-api.us'
    Portal: '.developer.azure-api.us'
    Management: '.management.azure-api.us'
    Scm: '.scm.azure-api.us'
  }
  AzureChinaCloud: {
    Gateway: '.azure-api.cn'
    Portal: '.developer.azure-api.cn'
    Management: '.management.azure-api.cn'
    Scm: '.scm.azure-api.cn'
  }
}


// VNET
resource vnetResource 'Microsoft.Network/virtualNetworks@2022-01-01' = {
  name: vnet
  location: location
  properties: {
    enableDdosProtection: enableDdosProtection
    addressSpace:{
      addressPrefixes:[
        '10.0.0.0/20'
      ]
    }
    subnets:[
      // [0] Web app vnet integration subnet
      {
        name: 'appgw-subnet'
        properties:{
          addressPrefix: '10.0.0.0/24'
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      // [1] APIM subnet
      {
        name: 'apim-subnet'
        properties:{
          addressPrefix: '10.0.1.0/27'
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      // [3] Storage private endpoint subnet
      {
        name: 'storage-subnet'
        properties:{
          addressPrefix: '10.0.1.32/27'
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      // [4] Azure Cache for Redis private endpoint subnet
      {
        name: 'redis-subnet'
        properties:{
          addressPrefix: '10.0.1.64/27'
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      // [5] Service Bus private endpoint subnet
      {
        name: 'servicebus-subnet'
        properties:{
          addressPrefix: '10.0.1.96/27'
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'  
        }
      }
      // [8] Key Vault private endpoint subnet
      {
        name: 'keyvault-subnet'
        properties:{
          addressPrefix: '10.0.1.192/27'
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      // [9] Azure SQL DB private endpoint subnet
      {
        name: 'sql-server-subnet'
        properties:{
          addressPrefix: '10.0.1.224/27'
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
    ]
  }
  tags: tags
}


// AZURE MONITOR - APPLICATION INSIGHTS
resource workspaceResource 'Microsoft.OperationalInsights/workspaces@2021-06-01' = {
  name: workspace
  location: location
  tags: tags
}

resource insightsResource 'Microsoft.Insights/components@2020-02-02' = {
  name: insights
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: workspaceResource.id
  }
}


// PRIVATE DNS ZONES

resource privateBlobsDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.blob.${environment().suffixes.storage}'
  location: 'global'
  tags: tags
  resource privateSitesDnsZoneVNetLink 'virtualNetworkLinks' = {
    name: '${last(split(vnetResource.id, '/'))}-vnetlink'
    location: 'global'
    properties:{
      registrationEnabled: false
      virtualNetwork:{
        id: vnetResource.id
      }
    }
  }
}

resource privateFilesDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.file.${environment().suffixes.storage}'
  location: 'global'
  tags: tags
  resource privateSitesDnsZoneVNetLink 'virtualNetworkLinks' = {
    name: '${last(split(vnetResource.id, '/'))}-vnetlink'
    location: 'global'
    properties:{
      registrationEnabled: false
      virtualNetwork:{
        id: vnetResource.id
      }
    }
  }
}

resource privateTablesDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.table.${environment().suffixes.storage}'
  location: 'global'
  tags: tags
  resource privateSitesDnsZoneVNetLink 'virtualNetworkLinks' = {
    name: '${last(split(vnetResource.id, '/'))}-vnetlink'
    location: 'global'
    properties:{
      registrationEnabled: false
      virtualNetwork:{
        id: vnetResource.id
      }
    }
  }
}

resource privateQueuesDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.queue.${environment().suffixes.storage}'
  location: 'global'
  tags: tags
  resource privateSitesDnsZoneVNetLink 'virtualNetworkLinks' = {
    name: '${last(split(vnetResource.id, '/'))}-vnetlink'
    location: 'global'
    properties:{
      registrationEnabled: false
      virtualNetwork:{
        id: vnetResource.id
      }
    }
  }
}

resource privateRedisDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateLinkRedisDnsNames[environment().name]
  location: 'global'
  tags: tags
  resource privateSitesDnsZoneVNetLink 'virtualNetworkLinks' = {
    name: '${last(split(vnetResource.id, '/'))}-vnetlink'
    location: 'global'
    properties:{
      registrationEnabled: false
      virtualNetwork:{
        id: vnetResource.id
      }
    }
  }
}

resource privateServicebusDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateLinkServiceBusDnsNames[environment().name]
  location: 'global'
  tags: tags
  resource privateSitesDnsZoneVNetLink 'virtualNetworkLinks' = {
    name: '${last(split(vnetResource.id, '/'))}-vnetlink'
    location: 'global'
    properties:{
      registrationEnabled: false
      virtualNetwork:{
        id: vnetResource.id
      }
    }
  }
}

resource privateKeyvaultDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateLinkKeyVaultDnsNames[environment().name]
  location: 'global'
  tags: tags
  resource privateSitesDnsZoneVNetLink 'virtualNetworkLinks' = {
    name: '${last(split(vnetResource.id, '/'))}-vnetlink'
    location: 'global'
    properties:{
      registrationEnabled: false
      virtualNetwork:{
        id: vnetResource.id
      }
    }
  }
}

resource privateSqlDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink${environment().suffixes.sqlServerHostname}'
  location: 'global'
  tags: tags
  resource privateSitesDnsZoneVNetLink 'virtualNetworkLinks' = {
    name: '${last(split(vnetResource.id, '/'))}-vnetlink'
    location: 'global'
    properties:{
      registrationEnabled: false
      virtualNetwork:{
        id: vnetResource.id
      }
    }
  }
}

resource privateApimGwDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: '${apim}${apimSuffixes[environment().name].Gateway}'
  location: 'global'
  tags: tags
  resource vnetLink 'virtualNetworkLinks' = {
    name: '${last(split(vnetResource.id, '/'))}-vnetlink'
    location: 'global'
    properties:{
      registrationEnabled: false
      virtualNetwork:{
        id: vnetResource.id
      }
    }
  }
}

resource privateApimPortalDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: '${apim}${apimSuffixes[environment().name].Portal}'
  location: 'global'
  tags: tags
  resource vnetLink 'virtualNetworkLinks' = {
    name: '${last(split(vnetResource.id, '/'))}-vnetlink'
    location: 'global'
    properties:{
      registrationEnabled: false
      virtualNetwork:{
        id: vnetResource.id
      }
    }
  }
}

resource privateApimManagementDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: '${apim}${apimSuffixes[environment().name].Management}'
  location: 'global'
  tags: tags
  resource vnetLink 'virtualNetworkLinks' = {
    name: '${last(split(vnetResource.id, '/'))}-vnetlink'
    location: 'global'
    properties:{
      registrationEnabled: false
      virtualNetwork:{
        id: vnetResource.id
      }
    }
  }
}

resource privateApimScmDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: '${apim}${apimSuffixes[environment().name].Scm}'
  location: 'global'
  tags: tags
  resource vnetLink 'virtualNetworkLinks' = {
    name: '${last(split(vnetResource.id, '/'))}-vnetlink'
    location: 'global'
    properties:{
      registrationEnabled: false
      virtualNetwork:{
        id: vnetResource.id
      }
    }
  }
}


// PRIVATE ENDPOINTS

//  Each Private endpoint (PEP) is comprised of: 
//    1. Private endpoint resource, 
//    2. Private link service connection to the target resource, 
//    3. Private DNS zone group, linked to a VNet-linked private DNS Zone


resource blobStoragePepResource 'Microsoft.Network/privateEndpoints@2022-01-01' = {
  name: '${functionsStorage}-blob-pep'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: vnetResource.properties.subnets[3].id
    }
    privateLinkServiceConnections: [
      {
        name: 'peplink'
        properties: {
          privateLinkServiceId: storageResource.id
          groupIds: [
            'blob'
          ]
        }
      }
    ]
  }
  resource privateDnsZoneGroup 'privateDnsZoneGroups' = {
    name: 'dnszonegroup'
    properties: {
      privateDnsZoneConfigs: [
        {
          name: 'config'
          properties: {
            privateDnsZoneId: privateBlobsDnsZone.id
          }
        }
      ]
    }
  }
}

resource tableStoragePepResource 'Microsoft.Network/privateEndpoints@2022-01-01' = {
  name: '${functionsStorage}-table-pep'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: vnetResource.properties.subnets[3].id
    }
    privateLinkServiceConnections: [
      {
        name: 'peplink'
        properties: {
          privateLinkServiceId: storageResource.id
          groupIds: [
            'table'
          ]
        }
      }
    ]
  }
  resource privateDnsZoneGroup 'privateDnsZoneGroups' = {
    name: 'dnszonegroup'
    properties: {
      privateDnsZoneConfigs: [
        {
          name: 'config'
          properties: {
            privateDnsZoneId: privateTablesDnsZone.id
          }
        }
      ]
    }
  }
}

resource queueStoragePepResource 'Microsoft.Network/privateEndpoints@2022-01-01' = {
  name: '${functionsStorage}-queue-pep'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: vnetResource.properties.subnets[3].id
    }
    privateLinkServiceConnections: [
      {
        name: 'peplink'
        properties: {
          privateLinkServiceId: storageResource.id
          groupIds: [
            'queue'
          ]
        }
      }
    ]
  }
  resource privateDnsZoneGroup 'privateDnsZoneGroups' = {
    name: 'dnszonegroup'
    properties: {
      privateDnsZoneConfigs: [
        {
          name: 'config'
          properties: {
            privateDnsZoneId: privateQueuesDnsZone.id
          }
        }
      ]
    }
  }
}

resource fileStoragePepResource 'Microsoft.Network/privateEndpoints@2022-01-01' = {
  name: '${functionsStorage}-file-pep'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: vnetResource.properties.subnets[3].id
    }
    privateLinkServiceConnections: [
      {
        name: 'peplink'
        properties: {
          privateLinkServiceId: storageResource.id
          groupIds: [
            'file'
          ]
        }
      }
    ]
  }
  resource privateDnsZoneGroup 'privateDnsZoneGroups' = {
    name: 'dnszonegroup'
    properties: {
      privateDnsZoneConfigs: [
        {
          name: 'config'
          properties: {
            privateDnsZoneId: privateFilesDnsZone.id
          }
        }
      ]
    }
  }
}

resource redisPepResource 'Microsoft.Network/privateEndpoints@2022-01-01' = {
  name: '${redis}-pep'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: vnetResource.properties.subnets[4].id
    }
    privateLinkServiceConnections: [
      {
        name: 'peplink'
        properties: {
          privateLinkServiceId: redisResource.id
          groupIds: [
            'redisCache'
          ]
        }
      }
    ]
  }
  resource privateDnsZoneGroups 'privateDnsZoneGroups' = {
    name: 'dnszonegroup'
    properties: {
      privateDnsZoneConfigs: [
        {
          name: 'config'
          properties: {
            privateDnsZoneId: privateRedisDnsZone.id
          }
        }
      ]
    }
  }
}

resource servicebusPepResource 'Microsoft.Network/privateEndpoints@2022-01-01' = {
  name: '${servicebus}-pep'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: vnetResource.properties.subnets[5].id
    }
    privateLinkServiceConnections: [
      {
        name: 'peplink'
        properties: {
          privateLinkServiceId: servicebusResource.id
          groupIds: [
            'namespace'
          ]
        }
      }
    ]
  }
  resource privateDnsZoneGroups 'privateDnsZoneGroups' = {
    name: 'dnszonegroup'
    properties: {
      privateDnsZoneConfigs: [
        {
          name: 'config'
          properties: {
            privateDnsZoneId: privateServicebusDnsZone.id
          }
        }
      ]
    }
  }
}

resource sqlPepResource 'Microsoft.Network/privateEndpoints@2022-01-01' = {
  name: '${sql}-pep'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: vnetResource.properties.subnets[9].id
    }
    privateLinkServiceConnections: [
      {
        name: 'peplink'
        properties: {
          privateLinkServiceId: sqlResource.id
          groupIds: [
            'sqlServer'
          ]
        }
      }
    ]
  }
  resource privateDnsZoneGroups 'privateDnsZoneGroups' = {
    name: 'dnszonegroup'
    properties: {
      privateDnsZoneConfigs: [
        {
          name: 'config'
          properties: {
            privateDnsZoneId: privateSqlDnsZone.id
          }
        }
      ]
    }
  }
}

resource keyvaultPepResource 'Microsoft.Network/privateEndpoints@2022-01-01' = {
  name: '${keyvault}-pep'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: vnetResource.properties.subnets[8].id
    }
    privateLinkServiceConnections: [
      {
        name: 'peplink'
        properties: {
          privateLinkServiceId: keyvaultResource.id
          groupIds: [
            'vault'
          ]
        }
      }
    ]
  }
  resource privateDnsZoneGroup 'privateDnsZoneGroups' = {
    name: 'dnszonegroup'
    properties: {
      privateDnsZoneConfigs: [
        {
          name: 'config'
          properties: {
            privateDnsZoneId: privateKeyvaultDnsZone.id
          }
        }
      ]
    }
  }
}


// APP GW

resource pipResource 'Microsoft.Network/publicIPAddresses@2022-05-01' = {
  name: appGwPip
  location: location
  tags: tags
  zones: ['1', '2', '3']
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
    idleTimeoutInMinutes: 4
  }
}

resource appGWResource 'Microsoft.Network/applicationGateways@2022-05-01' = {
  name: appGw
  location: location
  tags: tags
  zones: ['1', '2', '3']
  //TODO: {"code": "CannotSetResourceIdentity", "message": "Resource type 'Microsoft.Network/applicationGateways' does not support creation of 'SystemAssigned' resource identity. The supported types are 'UserAssigned'."}
  // identity:{
  //   type:'SystemAssigned'
  // }
  properties: {
    sku: {
      name: 'WAF_v2'
      tier: 'WAF_v2'
      capacity: 3
    }
    gatewayIPConfigurations: [
      {
        name: 'appGatewayIpConfig'
        properties: {
          subnet: {
            id: vnetResource.properties.subnets[0].id
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'appGwPublicFrontendIp'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: pipResource.id
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'port_80'
        properties: {
          port: 80
        }
      }
      {
        name: 'port_443'
        properties: {
          port: 443
        }
      }
    ]
    backendAddressPools: [
      {
        name: apimBackendPool
        properties: {
          backendAddresses:[
            {
              ipAddress: apimResource.properties.privateIPAddresses[0]
            }
          ]
        }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: backendHttpSettings
        properties: {
          port: 443
          protocol: 'Https'
          cookieBasedAffinity: 'Disabled'
          pickHostNameFromBackendAddress: true
          requestTimeout: appGwBackendRequestTimeout
          connectionDraining: { 
            enabled: false
          }
          //TODO: Use well known CA certificate = Yes
        }
      }
    ]
    httpListeners: [
      {
        name: 'publicHttpListener'
        properties: {
          firewallPolicy: {
            id: appGwWafPolicyResource.id
          }
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', appGw, appGwPublicFrontendIp)
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', appGw, 'port_80')
          }
          protocol: 'Http'
          requireServerNameIndication: false
        }
      }
      {
        name: publicHttpsListener
        properties: {
          firewallPolicy: {
            id: appGwWafPolicyResource.id
          }
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', appGw, appGwPublicFrontendIp)
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', appGw, 'port_443')
          }
          protocol: 'Https'
          requireServerNameIndication: true
          sslCertificate: {
            
          }
          sslProfile:{
            
          }
        }
      }
    ]
    redirectConfigurations:[
      {
        // Redirect HTTP => HTTPS
        name: httpRedirectConfiguration
        properties:{
          includePath: true
          includeQueryString: true
          redirectType: 'Permanent'
          targetListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', appGw, publicHttpsListener)
          }
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'httpRedirectRoutingRule'
        properties: {
          ruleType: 'Basic'
          priority: 10
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', appGw, publicHttpsListener)
          }
          redirectConfiguration:{

          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', appGw, apimBackendPool)
          }
          backendHttpSettings: {
            id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', appGw, backendHttpSettings)
          }
        }
      }
      {
        name: 'apimRoutingRule'
        properties: {
          ruleType: 'Basic'
          priority: 10
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', appGw, publicHttpsListener)
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', appGw, apimBackendPool)
          }
          backendHttpSettings: {
            id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', appGw, backendHttpSettings)
          }
        }
      }
    ]
    enableHttp2: false
    webApplicationFirewallConfiguration: {
      enabled: true
      firewallMode: 'Prevention'
      ruleSetType: 'OWASP'
      ruleSetVersion: '3.1'
      requestBodyCheck: true
      maxRequestBodySizeInKb: 128
      fileUploadLimitInMb: 100
    }
    firewallPolicy: {
      id: appGwWafPolicyResource.id
    }
  }
}

resource appGwWafPolicyResource 'Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies@2022-05-01' = {
  name: appGwWafPolicy
  location: location
  tags: tags
  properties: {
    customRules: [
    ]
    policySettings: {
      requestBodyCheck: true
      maxRequestBodySizeInKb: 128
      fileUploadLimitInMb: 100
      state: 'Enabled'
      mode: 'Prevention'
    }
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'OWASP'
          ruleSetVersion: '3.1'
        }
      ]
    }
  }
}

// APIM
resource apimResource 'Microsoft.ApiManagement/service@2021-12-01-preview' = {
  name: apim
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  zones: [ '1', '2', '3' ]
  sku: {
    name: apimSkuName
    capacity: apimSkuName == 'Developer' ? 2 : 3
  }
  properties: {
    publisherEmail: apimPublisherEmail
    publisherName: apimPublisherName
    virtualNetworkConfiguration: {
      subnetResourceId: vnetResource.properties.subnets[0].id
    }
    virtualNetworkType: 'Internal'
  }
}

// STORAGE ACCOUNT
resource storageResource 'Microsoft.Storage/storageAccounts@2022-05-01' = {
  name: functionsStorage
  kind: 'StorageV2'
  location: location
  tags: tags
  sku: {
    name: 'Standard_ZRS'
  }
  properties:{
    allowBlobPublicAccess: false
    publicNetworkAccess: 'Disabled'
    accessTier: 'Hot'
  }
  // // When deploying a Function App with Bicep, a content fileshare must be explicitly created or Function App will not start.
  // resource functionContentShare 'fileServices' = {
  //   name: 'default'
  //   resource share 'shares@2022-05-01' = {
  //     name: functionContentShareName
  //   }
  // }
}



// REDIS PREMIUM
resource redisResource 'Microsoft.Cache/redis@2022-05-01' = {
  name: redis
  location: location
  tags: tags
  zones: ['1', '2', '3']
  properties: {
    sku: {
      capacity: 1
      family: 'P'
      name: 'Premium'
    }
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Disabled'
    replicasPerMaster: 2
    replicasPerPrimary: 2
  }
}


// SERVICE BUS PREMIUM
resource servicebusResource 'Microsoft.ServiceBus/namespaces@2021-11-01' = {
  name: servicebus
  location: location
  tags: tags
  sku: {
    name: 'Premium'
    capacity: 1
    tier: 'Premium'
  }
  properties:{
    zoneRedundant: true
  }
  resource queue1 'queues@2021-11-01' = {
    name: servicebusQueueName
  }
}




// KEY VAULT
resource keyvaultResource 'Microsoft.KeyVault/vaults@2022-07-01' = {
  name: keyvault
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenant().tenantId
    publicNetworkAccess: 'disabled'
    accessPolicies: [
      // {
      //   objectId: webApp1Resource.identity.principalId
      //   tenantId: webApp1Resource.identity.tenantId
      //   permissions: {
      //     secrets: [
      //       'list'
      //       'get'
      //     ]
      //   }
      // }
    ]
  }
  resource redisSecretResource 'secrets@2022-07-01' = {
    name: redisConnectionStringSecretName
    properties: {
      value: '${redisResource.properties.hostName}:6380,password=${redisResource.listKeys().primaryKey},ssl=True,abortConnect=False'
    }
  }
  resource sqlSecretResource 'secrets@2022-07-01' = {
    name: sqlConnectionStringSecretName
    properties: {
      value: 'Server=tcp:${sqlResource.properties.fullyQualifiedDomainName},1433;Initial Catalog=${sqlDatabaseName};Persist Security Info=False;User ID=${sqlAdmin};Password=${sqlAdminPassword};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'
    }
  }
}


// SQL
resource sqlResource 'Microsoft.Sql/servers@2021-11-01' = {
  name: sql
  location: location
  tags: tags
  properties: {
    administratorLogin: sqlAdmin
    administratorLoginPassword: sqlAdminPassword
    publicNetworkAccess: 'Disabled'
  }
  resource db 'databases@2021-11-01' = {
    name: sqlDatabaseName
    location: location
    tags: tags
    sku: {
      name: 'P1'
      tier: 'Premium'
    }
    properties: {
      zoneRedundant: true
    }
  }
}


// ROLE ASSIGNMENTS


// Outputs
output applicationName string = applicationName
output environmentOutput object = environment()
output insightsInstrumentationKey string = insightsResource.properties.InstrumentationKey
