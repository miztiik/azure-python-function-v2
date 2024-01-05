// SET MODULE DATE
param module_metadata object = {
  module_last_updated: '2023-05-21'
  owner: 'miztiik@github'
}

param deploymentParams object
param svc_bus_params object
param tags object
param svc_bus_ns_name string

// Get Service Bus Namespace Reference
resource r_svc_bus_ns_ref 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' existing = {
  name: svc_bus_ns_name
}

var svc_bus_topic_name = replace('${svc_bus_params.name_prefix}-${deploymentParams.loc_short_code}-topic-${deploymentParams.enterprise_name_suffix}-${deploymentParams.global_uniqueness}', '_', '-')

resource r_svc_bus_topic 'Microsoft.ServiceBus/namespaces/topics@2022-10-01-preview' = {
  name: svc_bus_topic_name
  parent: r_svc_bus_ns_ref
  properties: {
    autoDeleteOnIdle: 'P10D'
    defaultMessageTimeToLive: 'P14D'
    duplicateDetectionHistoryTimeWindow: 'PT10M'
    enableBatchedOperations: false
    enableExpress: false
    enablePartitioning: false
    maxSizeInMegabytes: 1024
    requiresDuplicateDetection: false
    supportOrdering: false
    // forwardTo: 'string'
  }
}

// Email Action Group
resource r_email_on_alerts 'microsoft.insights/actionGroups@2019-06-01' = {
  name: 'EmailActionGroup'
  location: 'Global'
  properties: {
    groupShortName: 'Email'
    enabled: true
    emailReceivers: [
      {
        name: 'Myztique'
        emailAddress: 'abc@xyz.com'
      }
    ]
  }
}

// Create Alert for DLQ

resource r_dlq_alert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'dlq_gt_5_${svc_bus_params.name_prefix}_${deploymentParams.global_uniqueness}_alert'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when DLQ has >5 messages in last 5 minutes '
    severity: 0
    enabled: true
    autoMitigate: true
    targetResourceRegion: deploymentParams.location
    targetResourceType: 'Microsoft.ServiceBus/namespaces'
    scopes: [
      r_svc_bus_ns_ref.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          name: 'dlq_gt_5_in_5_min_Metric1'
          metricNamespace: 'Microsoft.ServiceBus/namespaces'
          metricName: 'DeadletteredMessages'
          dimensions: [
            {
              name: 'EntityName'
              operator: 'Include'
              values: [
                svc_bus_topic_name
              ]
            }
          ]
          timeAggregation: 'Minimum'
          operator: 'GreaterThanOrEqual'
          threshold: 4
          skipMetricValidation: false
        }
      ]
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
    }
    actions: [
      {
        actionGroupId: r_email_on_alerts.id
        webHookProperties: {}
      }
    ]
  }
}

// Alert for Service Bus Throttled Requests
resource r_svc_bus_throttled_reqs_alert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'throttle_reqs_${svc_bus_params.name_prefix}_${deploymentParams.global_uniqueness}_alert'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when a Service Bus entity has throttled more than 5 requests.'
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    severity: 2
    enabled: true
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          metricName: 'ThrottledRequests'
          metricNamespace: 'Microsoft.ServiceBus/namespaces'
          name: 'Metric1'
          skipMetricValidation: false
          timeAggregation: 'Total'
          criterionType: 'StaticThresholdCriterion'
          operator: 'GreaterThan'
          threshold: 10
          dimensions: [
            {
              name: 'EntityName'
              operator: 'Include'
              values: [
                svc_bus_topic_name
              ]
            }
          ]
        }
      ]
    }
    scopes: [ r_svc_bus_ns_ref.id ]
    actions: [
      {
        actionGroupId: r_email_on_alerts.id
        webHookProperties: {}
      }
    ]

  }
}

// OUTPUTS
output module_metadata object = module_metadata

output svc_bus_topic_name string = r_svc_bus_topic.name
output svc_bus_topic_id string = r_svc_bus_topic.id
