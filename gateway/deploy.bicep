targetScope = 'resourceGroup'

param login string = 'pfsenseadmin'

@secure()
param password string

resource fwPublicIp 'Microsoft.Network/publicIPAddresses@2026-03-01' = {
    name: 'fw-nus-publicip'
    location: resourceGroup().location
    sku: {
        name: 'Standard'
        tier: 'Regional'
    }
    properties: {
        publicIPAddressVersion: 'IPv4'
        publicIPAllocationMethod: 'Static'
    }
}

resource connectivityNetwork 'Microsoft.Network/virtualNetworks@2026-03-01' = {
    name: 'connectivity-nus-vnet'
    location: resourceGroup().location
    properties: {
        addressSpace: {
            addressPrefixes: [
                '10.0.0.0/21'
            ]
        }
    }
}

resource connectivitySubnet 'Microsoft.Network/virtualNetworks/subnets@2026-03-01' = {
    name: 'connectivity-nus-nbsb-snet'
    parent: connectivityNetwork
    properties: {
        addressPrefix: '10.0.1.0/24'
        networkSecurityGroup: {
            id: gwnsg.id
        }
    }
}

// Gateway 
// Gateway is attached to connectivity subnet to restrict Internet NB/SB flow only to the NVA
resource gwnsg 'Microsoft.Network/networkSecurityGroups@2025-07-01' = {
    name: 'connectivity-nus-nbsb-nsg'
    location: resourceGroup().location
    properties: {
        securityRules: [
            {
                name: 'AllowInternetHTTPSSB'
                properties: {
                    direction: 'Inbound'
                    protocol: 'Tcp'
                    sourceAddressPrefix: 'Internet'
                    destinationAddressPrefix: '10.0.1.10'
                    destinationPortRange: '443'
                    access: 'Allow'
                    sourcePortRange: '*'
                    priority: 500
                }
            }
                        {
                name: 'AllowInternetHTTPSB'
                properties: {
                    direction: 'Inbound'
                    protocol: 'Tcp'
                    sourceAddressPrefix: 'Internet'
                    destinationAddressPrefix: '10.0.1.10'
                    destinationPortRange: '80'
                    access: 'Allow'
                    sourcePortRange: '*'
                    priority: 501
                }
            }
            {
                name: 'AllowIKESB'
                properties: {
                    direction: 'Inbound'
                    protocol: 'UDP'
                    sourceAddressPrefix: 'Internet'
                    destinationAddressPrefix: '10.0.1.10'
                    destinationPortRange: '500'
                    access: 'Allow'
                    sourcePortRange: '*'
                    priority: 502
                }
            }
            {
                name: 'AllowNATTSB'
                properties: {
                    direction: 'Inbound'
                    protocol: 'UDP'
                    sourceAddressPrefix: 'Internet'
                    destinationAddressPrefix: '10.0.1.10'
                    destinationPortRange: '4500'
                    access: 'Allow'
                    sourcePortRange: '*'
                    priority: 503
                }
            }
        ]
    }
}

resource gwNic 'Microsoft.Network/networkInterfaces@2026-03-01' = {
    name: 'connectivity-nus-gw-nic'
    location: resourceGroup().location
    properties: {
        enableIPForwarding: true
        ipConfigurations: [
            {
                name: 'connectivtiy-nus-gw-snet-ip'
                properties: {
                    primary: true
                    privateIPAddressVersion: 'IPv4'
                    privateIPAllocationMethod: 'Static'
                    privateIPAddress: '10.0.1.10'
                    subnet: {
                        id: connectivitySubnet.id
                    }
                    publicIPAddress: {
                        id: fwPublicIp.id
                    }
                }
            }
        ]
    }
}


resource pfsenseVirtualAppliance 'Microsoft.Compute/virtualMachines@2026-04-01' = {
    name: 'connectivity-nus-nbsb-fw-1-vm'
    location: resourceGroup().location
    plan: {
        name: 'pfsense-plus-public-tac-lite'
        product: 'pfsense-plus-public-cloud-fw-vpn-router'
        publisher: 'netgate'   
    }
    properties: {
        hardwareProfile: {
            vmSize: 'Standard_B2ats_v2'
        }
        networkProfile: {
            networkInterfaces: [
                {
                    id: gwNic.id
                    properties: {
                        primary: true
                    }
                }
            ]
        }
        storageProfile: {
            imageReference: {
                offer: 'pfsense-plus-public-cloud-fw-vpn-router'
                publisher: 'netgate'
                sku: 'pfsense-plus-public-tac-lite'
                version: '26.03.1'
            }
            osDisk: {
                createOption: 'FromImage'
                name: 'pfsense-prd-01-osdisk'
                diskSizeGB: 20
                caching: 'ReadWrite'
            }

        }
        osProfile: {
        adminPassword: password
        adminUsername: login
        computerName: 'pfsense-prd-01-nus'
        linuxConfiguration: {
            disablePasswordAuthentication: false
        }
        }
    }
}
