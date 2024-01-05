// SET MODULE DATE
param module_metadata object = {
  module_last_updated: '2023-12-24'
  owner: 'miztiik@github'
}

param deploymentParams object
param svc_bus_params object
param tags object

param enableDiagnostics bool = true
param logAnalyticsWorkspaceId string

var svc_bus_name = replace('${deploymentParams.enterprise_name_suffix}-${deploymentParams.loc_short_code}-${svc_bus_params.name_prefix}-svc-bus-ns-${deploymentParams.global_uniqueness}', '_', '-')

resource r_svc_bus_ns 'Microsoft.ServiceBus/namespaces@2022-01-01-preview' = {
  name: svc_bus_name
  location: deploymentParams.location
  tags: tags
  sku: {
    name: 'Standard'
    //name: 'Premium'
  }
  properties: {}
}

var svc_bus_q_name = replace('${svc_bus_params.name_prefix}-${deploymentParams.loc_short_code}-q-${deploymentParams.enterprise_name_suffix}-${deploymentParams.global_uniqueness}', '_', '-')

resource r_svc_bus_q 'Microsoft.ServiceBus/namespaces/queues@2022-01-01-preview' = {
  parent: r_svc_bus_ns
  name: svc_bus_q_name
  properties: {
    lockDuration: 'PT5M'
    maxSizeInMegabytes: 1024
    requiresDuplicateDetection: false
    requiresSession: false
    // defaultMessageTimeToLive: 'P10675199DT2H48M5.4775807S'
    deadLetteringOnMessageExpiration: false
    duplicateDetectionHistoryTimeWindow: 'PT10M'
    maxDeliveryCount: 5
    // autoDeleteOnIdle: 'P10675199DT2H48M5.4775807S'
    enablePartitioning: false
    enableExpress: false
  }
}

////////////////////////////////////////////
//                                        //
//         Diagnostic Settings            //
//                                        //
////////////////////////////////////////////

@description('Enabling Diagnostics for the Service Bus Namespace')
resource r_svc_bus_ns_diags 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics) {
  name: '${svc_bus_name}-diags'
  scope: r_svc_bus_ns
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
      {
        categoryGroup: 'audit'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
    logAnalyticsDestinationType: 'Dedicated'
  }
}

// OUTPUTS
output module_metadata object = module_metadata

output svc_bus_ns_name string = r_svc_bus_ns.name
output svc_bus_q_name string = r_svc_bus_q.name
