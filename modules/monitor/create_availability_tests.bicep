// SET MODULE DATE
param module_metadata object = {
  module_last_updated: '2024-01-04'
  owner: 'miztiik@github'
}

param deploymentParams object
param r_app_insights_name string
param target_url string

// https://docs.microsoft.com/en-us/azure/azure-monitor/app/monitor-web-app-availability

resource r_standardWebTestPageHome 'Microsoft.Insights/webtests@2022-06-15' = {
  name: 'trigger_event_producer'
  location: deploymentParams.location
  tags: { 'hidden-link:${resourceId('microsoft.insights/components/', r_app_insights_name)}': 'Resource' }
  kind: 'ping'
  properties: {
    SyntheticMonitorId: 'trigger_event_producer'
    Name: 'trigger_event_producer'
    Description: null
    Enabled: true
    Frequency: 300
    Timeout: 120
    Kind: 'standard'
    RetryEnabled: true
    Locations: [
      // {
      //   Id: 'us-va-ash-azr' // East US
      // }
      // {
      //   Id: 'us-fl-mia-edge' // Central US
      // }
      // {
      //   Id: 'us-ca-sjc-azr' // West US
      // }
      {
        Id: 'emea-au-syd-edge' // Austrailia East
      }
      // {
      //   Id: 'apac-jp-kaw-edge' // Japan East
      // }
      // {
      //   Id: 'emea-nl-ams-azr' // West Europe
      // }
    ]
    Configuration: null
    Request: {
      RequestUrl: target_url
      Headers: null
      HttpVerb: 'GET'
      RequestBody: null
      ParseDependentRequests: false
      FollowRedirects: null
    }
    ValidationRules: {
      ExpectedHttpStatusCode: 200
      IgnoreHttpStatusCode: false
      ContentValidation: null
      SSLCheck: true
      SSLCertRemainingLifetimeCheck: 7
    }
  }
}

// OUTPUTS
output module_metadata object = module_metadata
