param location string = 'japaneast'
param logic_apps_name string = 'logic-'
param synapse_workspace_name string
param sql_pool_name string 
param interval int = 4


resource logic_apps 'Microsoft.Logic/workflows@2017-07-01' = {
  name: logic_apps_name
  location: 'japaneast'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {}
      triggers: {
        Recurrence: {
          recurrence: {
            frequency: 'Hour'
            interval: interval
            startTime: '2019-01-01T00:00:00Z'
            timeZone: 'Tokyo Standard Time'
          }
          evaluatedRecurrence: {
            frequency: 'Hour'
            interval: interval
            startTime: '2019-01-01T00:00:00Z'
            timeZone: 'Tokyo Standard Time'
          }
          type: 'Recurrence'
        }
      }
      actions: {
        Get_Synapse_state: {
          runAfter: {
            Initialize_ActiveQueryCount_variable: [
              'Succeeded'
            ]
          }
          type: 'Http'
          inputs: {
            authentication: {
              type: 'ManagedServiceIdentity'
            }
            method: 'GET'
            uri: 'https://management.azure.com/subscriptions/@{variables(\'RestAPIVariables\')[\'SubscriptionId\']}/resourceGroups/@{variables(\'RestAPIVariables\')[\'ResourceGroupName\']}/providers/Microsoft.Synapse/workspaces/@{variables(\'RestAPIVariables\')[\'workspaceName\']}/sqlPools/@{variables(\'RestAPIVariables\')[\'sqlPoolName\']}?api-version=2019-06-01-preview'
          }
        }
        Initialize_API_variables: {
          runAfter: {}
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'RestAPIVariables'
                type: 'Object'
                value: {
                  ResourceGroupName: resourceGroup().name
                  ScheduleTimeZone: 'Tokyo Standard Time'
                  SubscriptionId: subscription().subscriptionId
                  TenantId: tenant().tenantId
                  sqlPoolName: sql_pool_name
                  workspaceName: synapse_workspace_name
                }
              }
            ]
          }
        }
        Initialize_ActiveQueryCount_variable: {
          runAfter: {
            Initialize_API_variables: [
              'Succeeded'
            ]
          }
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'ActiveQueryCount'
                type: 'Integer'
                value: 1
              }
            ]
          }
        }
        Parse_JSON: {
          runAfter: {
            Get_Synapse_state: [
              'Succeeded'
            ]
          }
          type: 'ParseJson'
          inputs: {
            content: '@body(\'Get_Synapse_state\')'
            schema: {
              properties: {
                id: {
                  type: 'string'
                }
                location: {
                  type: 'string'
                }
                name: {
                  type: 'string'
                }
                properties: {
                  properties: {
                    collation: {
                      type: 'string'
                    }
                    creationDate: {
                      type: 'string'
                    }
                    maxSizeBytes: {
                      type: 'integer'
                    }
                    provisioningState: {
                      type: 'string'
                    }
                    restorePointInTime: {
                      type: 'string'
                    }
                    status: {
                      type: 'string'
                    }
                  }
                  type: 'object'
                }
                sku: {
                  properties: {
                    capacity: {
                      type: 'integer'
                    }
                    name: {
                      type: 'string'
                    }
                  }
                  type: 'object'
                }
                type: {
                  type: 'string'
                }
              }
              type: 'object'
            }
          }
        }
        PauseSynapseIfOnline: {
          actions: {
            Pause_SQL_Pool: {
              runAfter: {
                Until_ZeroActiveQueries: [
                  'Succeeded'
                ]
              }
              type: 'Http'
              inputs: {
                authentication: {
                  type: 'ManagedServiceIdentity'
                }
                method: 'POST'
                uri: 'https://management.azure.com/subscriptions/@{variables(\'RestAPIVariables\')[\'SubscriptionId\']}/resourceGroups/@{variables(\'RestAPIVariables\')[\'ResourceGroupName\']}/providers/Microsoft.Synapse/workspaces/@{variables(\'RestAPIVariables\')[\'workspaceName\']}/sqlPools/@{variables(\'RestAPIVariables\')[\'sqlPoolName\']}/pause?api-version=2019-06-01-preview'
              }
            }
            Until_ZeroActiveQueries: {
              actions: {
                GetActiveQueryCount: {
                  runAfter: {}
                  type: 'Http'
                  inputs: {
                    authentication: {
                      type: 'ManagedServiceIdentity'
                    }
                    method: 'GET'
                    uri: 'https://management.azure.com/subscriptions/@{variables(\'RestAPIVariables\')[\'SubscriptionId\']}/resourceGroups/@{variables(\'RestAPIVariables\')[\'ResourceGroupName\']}/providers/Microsoft.Synapse/workspaces/@{variables(\'RestAPIVariables\')[\'WorkspaceName\']}/sqlpools/@{variables(\'RestAPIVariables\')[\'SQLPoolName\']}/dataWarehouseUserActivities/current?api-version=2019-06-01-preview'
                  }
                }
                Update_ActiveQueryCount_variable: {
                  runAfter: {
                    GetActiveQueryCount: [
                      'Succeeded'
                    ]
                  }
                  type: 'SetVariable'
                  inputs: {
                    name: 'ActiveQueryCount'
                    value: '@body(\'GetActiveQueryCount\')[\'properties\'][\'activeQueriesCount\']'
                  }
                }
                Wait5minsIfActiveQuery: {
                  actions: {
                    Wait_5mins: {
                      runAfter: {}
                      type: 'Wait'
                      inputs: {
                        interval: {
                          count: 5
                          unit: 'Minute'
                        }
                      }
                    }
                  }
                  runAfter: {
                    Update_ActiveQueryCount_variable: [
                      'Succeeded'
                    ]
                  }
                  expression: {
                    and: [
                      {
                        greater: [
                          '@variables(\'ActiveQueryCount\')'
                          0
                        ]
                      }
                    ]
                  }
                  type: 'If'
                }
              }
              runAfter: {}
              expression: '@equals(variables(\'ActiveQueryCount\'), 0)'
              limit: {
                count: 3
                timeout: 'PT3H'
              }
              type: 'Until'
            }
          }
          runAfter: {
            Parse_JSON: [
              'Succeeded'
            ]
          }
          expression: {
            and: [
              {
                equals: [
                  '@body(\'Get_Synapse_state\')[\'properties\'][\'status\']'
                  'Online'
                ]
              }
            ]
          }
          type: 'If'
        }
      }
    }
    parameters: {}
  }
}
