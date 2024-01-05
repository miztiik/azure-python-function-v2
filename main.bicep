// SET MODULE DATE
param module_metadata object = {
  module_last_updated: '2024-01-04'
  owner: 'miztiik@github'
}

// targetScope = 'subscription'

targetScope = 'resourceGroup'

// Parameters
param deploymentParams object
param identity_params object
param key_vault_params object

param sa_params object

param logAnalyticsWorkspaceParams object

param brand_tags object

param dce_params object
param vnet_params object
param vm_params object

param fn_params object
param svc_bus_params object

param cosmosdb_params object

param date_now string = utcNow('yyyy-MM-dd')

var create_kv = false
var create_dce = false
var create_dcr = false
var create_vnet = false
var create_vm = false

param tags object = union(brand_tags, { last_deployed: date_now })

@description('Create Identity')
module r_uami 'modules/identity/create_uami.bicep' = {
  name: '${deploymentParams.enterprise_name_suffix}_${deploymentParams.loc_short_code}_${deploymentParams.global_uniqueness}_uami'
  params: {
    deploymentParams: deploymentParams
    identity_params: identity_params
    tags: tags
  }
}

@description('Add Permissions to User Assigned Managed Identity(UAMI)')
module r_add_perms_to_uami 'modules/identity/assign_perms_to_uami.bicep' = {
  name: '${deploymentParams.enterprise_name_suffix}_${deploymentParams.loc_short_code}_${deploymentParams.global_uniqueness}_perms_provider_to_uami'
  params: {
    uami_name_akane: r_uami.outputs.uami_name_akane
  }
  dependsOn: [
    r_uami
  ]
}

@description('Create Key Vault')
module r_kv 'modules/security/create_key_vault.bicep' = if (create_kv) {
  name: '${deploymentParams.enterprise_name_suffix}_${deploymentParams.loc_short_code}_${deploymentParams.global_uniqueness}_kv'
  params: {
    deploymentParams: deploymentParams
    key_vault_params: key_vault_params
    tags: tags
    uami_name_akane: r_uami.outputs.uami_name_func
  }
}

@description('Create Cosmos DB')
module r_cosmosdb 'modules/database/create_cosmos.bicep' = {
  name: '${deploymentParams.enterprise_name_suffix}_${deploymentParams.loc_short_code}_${deploymentParams.global_uniqueness}_cosmos_db'
  params: {
    deploymentParams: deploymentParams
    cosmosdb_params: cosmosdb_params

    logAnalyticsWorkspaceId: r_logAnalyticsWorkspace.outputs.logAnalyticsPayGWorkspaceId

    tags: tags
  }
}

@description('Create the Log Analytics Workspace')
module r_logAnalyticsWorkspace 'modules/monitor/create_log_analytics_workspace.bicep' = {
  name: '${logAnalyticsWorkspaceParams.name_prefix}_${deploymentParams.loc_short_code}_${deploymentParams.global_uniqueness}_la'
  params: {
    deploymentParams: deploymentParams
    logAnalyticsWorkspaceParams: logAnalyticsWorkspaceParams
    tags: tags
  }
}

@description('Create Storage Accounts')
module r_sa 'modules/storage/create_storage_account.bicep' = {
  name: '${deploymentParams.enterprise_name_suffix}_${deploymentParams.loc_short_code}_${deploymentParams.global_uniqueness}_sa'
  params: {
    deploymentParams: deploymentParams
    sa_params: sa_params
    tags: tags
    logAnalyticsWorkspaceId: r_logAnalyticsWorkspace.outputs.logAnalyticsPayGWorkspaceId
  }
}

@description('Create Storage Account - Blob container')
module r_blob 'modules/storage/create_blob.bicep' = {
  name: '${deploymentParams.enterprise_name_suffix}_${deploymentParams.loc_short_code}_${deploymentParams.global_uniqueness}_blob'
  params: {
    deploymentParams: deploymentParams
    sa_params: sa_params
    sa_name: r_sa.outputs.sa_name
    misc_sa_name: r_sa.outputs.misc_sa_name
  }
  dependsOn: [
    r_sa
    r_logAnalyticsWorkspace
  ]
}

@description('Create the function app & Functions')
module r_fn_app 'modules/functions/create_function_v2.bicep' = {
  name: '${deploymentParams.enterprise_name_suffix}_${deploymentParams.loc_short_code}_${deploymentParams.global_uniqueness}_fn_app'
  params: {
    deploymentParams: deploymentParams
    uami_name_func: r_uami.outputs.uami_name_func
    fn_params: fn_params
    misc_sa_name: r_sa.outputs.misc_sa_name

    laws_id: r_logAnalyticsWorkspace.outputs.logAnalyticsPayGWorkspaceId
    tags: tags

    // appConfigName: r_appConfig.outputs.appConfigName

    sa_name: r_sa.outputs.sa_name
    blob_container_name: r_blob.outputs.blob_container_name

    cosmos_db_accnt_name: r_cosmosdb.outputs.cosmos_db_accnt_name
    cosmos_db_name: r_cosmosdb.outputs.cosmos_db_name
    cosmos_db_container_name: r_cosmosdb.outputs.cosmos_db_container_name

    svc_bus_ns_name: r_svc_bus.outputs.svc_bus_ns_name
    svc_bus_q_name: r_svc_bus.outputs.svc_bus_q_name
    svc_bus_topic_name: r_svc_bus_topic.outputs.svc_bus_topic_name
    sales_events_subscriber_name: r_svc_bus_sub_filter.outputs.sales_events_subscriber_name

  }
  dependsOn: [
    r_sa
    r_logAnalyticsWorkspace
  ]
}

@description('Create API Management')
module r_apim_svc 'modules/integration/create_apim.bicep' = {
  name: '${deploymentParams.enterprise_name_suffix}_${deploymentParams.loc_short_code}_${deploymentParams.global_uniqueness}_apim'
  params: {
    deploymentParams: deploymentParams
    tags: tags
    logAnalyticsWorkspaceId: r_logAnalyticsWorkspace.outputs.logAnalyticsPayGWorkspaceId

    fn_app_name: r_fn_app.outputs.fn_app_name
    event_generator_fn_name: 'miztiik_automation/store_events_producer'
    app_insights_name: r_fn_app.outputs.r_app_insights_name
  }
}

@description('Create Avaialbility Test')
module r_availability_test 'modules/monitor/create_availability_tests.bicep' = {
  name: '${deploymentParams.enterprise_name_suffix}_${deploymentParams.loc_short_code}_${deploymentParams.global_uniqueness}_availability_test'
  params: {
    deploymentParams: deploymentParams
    r_app_insights_name: r_fn_app.outputs.r_app_insights_name
    // target_url: 'https://.azurewebsites.net/miztiik_automation/store_events_producer'
    target_url: r_apim_svc.outputs.producer_api_url
  }
}

@description('Create Service Bus')
module r_svc_bus 'modules/integration/create_svc_bus.bicep' = {
  name: '${deploymentParams.enterprise_name_suffix}_${deploymentParams.loc_short_code}_${deploymentParams.global_uniqueness}_svc_bus'
  params: {
    deploymentParams: deploymentParams
    svc_bus_params: svc_bus_params
    tags: tags
    logAnalyticsWorkspaceId: r_logAnalyticsWorkspace.outputs.logAnalyticsPayGWorkspaceId
  }
}

@description('Create Service Bus Topic')
module r_svc_bus_topic 'modules/integration/create_topic.bicep' = {
  name: '${deploymentParams.enterprise_name_suffix}_${deploymentParams.loc_short_code}_${deploymentParams.global_uniqueness}_svc_bus_topic'
  params: {
    deploymentParams: deploymentParams
    svc_bus_params: svc_bus_params
    svc_bus_ns_name: r_svc_bus.outputs.svc_bus_ns_name
    tags: tags
  }
  dependsOn: [
    r_svc_bus
  ]
}

@description('Create Service Bus Subscription Filter')
module r_svc_bus_sub_filter 'modules/integration/create_queue_subscription.bicep' = {
  name: '${deploymentParams.enterprise_name_suffix}_${deploymentParams.loc_short_code}_${deploymentParams.global_uniqueness}_svc_bus_sub_filter'
  params: {
    deploymentParams: deploymentParams
    svc_bus_params: svc_bus_params

    svc_bus_ns_name: r_svc_bus.outputs.svc_bus_ns_name
    svc_bus_topic_name: r_svc_bus_topic.outputs.svc_bus_topic_name

  }
  dependsOn: [
    r_svc_bus
    r_svc_bus_topic
  ]
}

/*
@description('Create the Data Collection Endpoint')
module r_data_collection_endpoint 'modules/monitor/data_collection_endpoint.bicep' = if (create_dce) {
  name: '${deploymentParams.enterprise_name_suffix}_${deploymentParams.loc_short_code}_${deploymentParams.global_uniqueness}_dce'
  params: {
    deploymentParams: deploymentParams
    dce_params: dce_params
    tags: tags
  }
}

@description('Create the Data Collection Rule')
module r_dataCollectionRule 'modules/monitor/data_collection_rule.bicep' = if (create_dcr) {
  name: '${deploymentParams.enterprise_name_suffix}_${deploymentParams.loc_short_code}_${deploymentParams.global_uniqueness}_dcr'
  params: {
    deploymentParams: deploymentParams
    osKind: 'Linux'
    tags: tags

    storeEventsRuleName: 'storeEvents_Dcr'
    storeEventsLogFilePattern: '/var/log/miztiik*.json'
    storeEventscustomTableNamePrefix: r_logAnalyticsWorkspace.outputs.storeEventsCustomTableNamePrefix

    automationEventsRuleName: 'miztiikAutomation_Dcr'
    automationEventsLogFilePattern: '/var/log/miztiik-automation-*.log'
    automationEventsCustomTableNamePrefix: r_logAnalyticsWorkspace.outputs.automationEventsCustomTableNamePrefix

    managedRunCmdRuleName: 'miztiikManagedRunCmd_Dcr'
    managedRunCmdLogFilePattern: '/var/log/azure/run-command-handler/*.log'
    managedRunCmdCustomTableNamePrefix: r_logAnalyticsWorkspace.outputs.managedRunCmdCustomTableNamePrefix

    linDataCollectionEndpointId: r_data_collection_endpoint.outputs.linux_dce_id
    logAnalyticsPayGWorkspaceName: r_logAnalyticsWorkspace.outputs.logAnalyticsPayGWorkspaceName
    logAnalyticsPayGWorkspaceId: r_logAnalyticsWorkspace.outputs.logAnalyticsPayGWorkspaceId

  }
  dependsOn: [
    r_logAnalyticsWorkspace
  ]
}

@description('Create Vnets, Subnets, NSGs, Routes')
module r_vnet 'modules/vnet/create_vnet.bicep' = if (create_vnet) {
  name: '${deploymentParams.enterprise_name_suffix}_${deploymentParams.loc_short_code}_${deploymentParams.global_uniqueness}_vnet'
  params: {
    deploymentParams: deploymentParams
    vnet_params: vnet_params
    tags: tags
  }
}

@description('Create Virtual Machines(s)')
module r_vm 'modules/vm/create_vm.bicep' = if (create_vm) {
  name: '${deploymentParams.enterprise_name_suffix}_${deploymentParams.loc_short_code}_${deploymentParams.global_uniqueness}_vm'
  params: {
    deploymentParams: deploymentParams
    uami_name_vm: r_uami.outputs.uami_name_vm

    misc_sa_name: r_sa.outputs.misc_sa_name

    vm_params: vm_params

    vm_subnet_id: r_vnet.outputs.web_subnet_01_id
    no_of_vms: 1

    logAnalyticsPayGWorkspaceId: r_logAnalyticsWorkspace.outputs.logAnalyticsPayGWorkspaceId

    linDataCollectionEndpointId: r_data_collection_endpoint.outputs.linux_dce_id
    storeEventsDcrId: r_dataCollectionRule.outputs.storeEventsDcrId
    automationEventsDcrId: r_dataCollectionRule.outputs.automationEventsDcrId

    add_to_appln_gw: false
    appln_gw_name: ''
    appln_gw_back_end_pool_name: ''

    tags: tags
  }
  dependsOn: [
    r_vnet
  ]
}
*/

//////////////////////////////////////////
// OUTPUTS                              //
//////////////////////////////////////////

output module_metadata object = module_metadata
