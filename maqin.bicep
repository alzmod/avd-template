@description('Location for all resources.')
param location string = resourceGroup().location

@description('Set this to true if creating a new network')
param subnetResourceId string

@description('Host pool resource id')
param hostPoolResourceId string

@secure()
@description('Host pool registration info token')
param registrationInfoToken string

@description('Virtual machine resource name')
param virtualMachineName string

@description('Virtual machine size')
param virtualMachineSize string

@description('Virtual machine image reference')
param virtualMachineImageReference object

@secure()
@description('Virtual machine resource admin username')
param adminUsername string

@secure()
@description('Virtual machine resource admin password')
param adminPassword string

param artifactsLocation string

@description('Domain name for on-premises domain join')
param domainName string = ''

@secure()
@description('Domain join username')
param domainJoinUsername string = ''

@secure()
@description('Domain join password')
param domainJoinPassword string = ''

@description('Organizational Unit path for domain join')
param domainJoinOUPath string = ''

// Get existing resources

resource hostPool 'Microsoft.DesktopVirtualization/hostPools@2024-04-08-preview' existing = {
  name: last(split(hostPoolResourceId, '/'))
  scope: resourceGroup(last(split(hostPoolResourceId, '/')))
}

// Create resources

resource networkinterface 'Microsoft.Network/networkInterfaces@2024-01-01' = {
  location: location
  name: 'nic-${virtualMachineName}'
  properties: {
    enableAcceleratedNetworking: true
    ipConfigurations: [
      {
        name: 'ipConfig'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: subnetResourceId
          }
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-03-01' = {
  location: location
  name: virtualMachineName
  properties: {
    licenseType: 'Windows_Client'
    hardwareProfile: {
      vmSize: virtualMachineSize
    }
    storageProfile: {
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
        deleteOption: 'Delete'
      }
      imageReference: {
        publisher: virtualMachineImageReference.publisher
        offer: virtualMachineImageReference.offer
        sku: virtualMachineImageReference.sku
        version: virtualMachineImageReference.version
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: networkinterface.id
          properties: {
            deleteOption: 'Delete'
          }
        }
      ]
    }
    securityProfile: {
      securityType: 'TrustedLaunch'
      uefiSettings: {
        secureBootEnabled: true
        vTpmEnabled: true
      }
    }
    additionalCapabilities: {
      hibernationEnabled: false
    }
    osProfile: {
      computerName: virtualMachineName
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}

resource domainJoin 'Microsoft.Compute/virtualMachines/extensions@2024-03-01' = if (domainName != '') {
  parent: vm
  name: 'JsonADDomainExtension'
  location: location
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'JsonADDomainExtension'
    typeHandlerVersion: '1.3'
    autoUpgradeMinorVersion: true
    settings: {
      name: domainName
      ouPath: domainJoinOUPath
      user: '${domainName}\\${domainJoinUsername}'
      restart: true
      options: 3
    }
    protectedSettings: {
      password: domainJoinPassword
    }
  }
}

resource dcs 'Microsoft.Compute/virtualMachines/extensions@2024-03-01' = {
  parent: vm
  name: 'MicrosoftPowershellDSC'
  location: location
  properties: {
    publisher: 'Microsoft.Powershell'
    type: 'DSC'
    typeHandlerVersion: '2.73'
    settings: {
      modulesUrl: artifactsLocation
      configurationFunction: 'Configuration.ps1\\AddSessionHost'
      properties: {
        hostPoolName: hostPool.name
        aadJoin: true
      }
    }
    protectedSettings: {
      properties: {
        registrationInfoToken: registrationInfoToken
      }
    }
  }
  dependsOn: [
    domainJoin
  ]
}
