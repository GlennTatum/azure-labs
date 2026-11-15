targetScope = 'resourceGroup'

param login string = 'pfsenseadmin'
param pfsenseASN int = 65014

@secure()
param password string

// ================================================
// Hub Configuration
// ================================================

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
        routeTable: {
            id: gwToInternet.id
        }
    }
}

// https://github.com/MicrosoftDocs/azure-docs/blob/main/articles/route-server/troubleshoot-route-server.md
resource gwToInternet 'Microsoft.Network/routeTables@2026-03-01' = {
    name: 'gw-to-internet'
    location: resourceGroup().location
    properties: {
        routes: [
            {
                name: 'toInternet'
                properties: {
                    addressPrefix: '0.0.0.0/0'
                    nextHopType: 'Internet'
                }
            }
        ]
    }
}


// ================================================
// BEGIN Static User Defined Routes (Alternative Option)
// ================================================
// The following will demonstrate utilizing User Defined Routes to configure
// east-west communication within the Hub and Spoke Topology. If this is
// desired, remove the Azure Route Server Configuration setup. Note, that
// routes will no longer be dynamically learned, therefore a new route,
// will needed to be added per each spoke added to the hub.



// ================================================
// END Static User Defined Routes (Alternative Option)
// ================================================



// ================================================
// BEGIN Azure Route Server Configuration
// ================================================
// The following will demonstrate Azure Route Server to provide route injection
// in spoke vnets.

resource azRouteServerSubnet 'Microsoft.Network/virtualNetworks/subnets@2026-03-01' = {
    name: 'RouteServerSubnet'
    parent: connectivityNetwork
    properties: {
        addressPrefix: '10.0.2.0/26'
    }
}

resource azRouteServerPublicIp 'Microsoft.Network/publicIPAddresses@2026-03-01' = {
    name: 'routeserver-nus-publicip'
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

resource connectivityRouteServer 'Microsoft.Network/virtualHubs@2026-03-01' = {
    name: 'routeserver-nus-rs'
    location: resourceGroup().location
    properties: {
        sku: 'Standard'
        hubRoutingPreference: 'ExpressRoute'
    }
}

resource connectivityRouteServerIpConfig 'Microsoft.Network/virtualHubs/ipConfigurations@2026-03-01' = {
    name: 'routeserver-nus-ipconfig'
    parent: connectivityRouteServer
    properties: {
        subnet: {
            id: azRouteServerSubnet.id
        }
        publicIPAddress: {
            id: azRouteServerPublicIp.id
        }
    }
}

resource connectivityRouteServerBGPPeering 'Microsoft.Network/virtualHubs/bgpConnections@2026-03-01' = {
    name: 'routeserver-nva-nus-bgpconnection'
    parent: connectivityRouteServer
    properties: {
        peerAsn: pfsenseASN
        peerIp: gwNic.properties.ipConfigurations[0].properties.privateIPAddress
    }
    dependsOn: [
        connectivityRouteServerIpConfig
    ]
}

// ================================================
// END Azure Route Server Configuration
// ================================================

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

// ================================================
// Spoke A Configuration
// ================================================

// Peer Hub VNET to Spoke A
// A bidirectional peering must be configured between the Hub and the Spoke
// - Note: This can be automated via an Azure Policy Definition to automate the peering
// - Note: The naming convention for peerings is peer-{parent-vnet-name}-{child-vnet}
resource peerToSpokeA 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2026-03-01' = {
    name: 'peer-connectivity-nus-vnet-spoke-a-nus-vnet'
    parent: connectivityNetwork
    properties: {
        allowForwardedTraffic: true
        allowVirtualNetworkAccess: true
        allowGatewayTransit: true
        useRemoteGateways: false
        remoteVirtualNetwork: {
            id: spokeAvnet.id
        }
    }
}

/*
Virtual network peering must have Use the remote virtual network's gateway or 
Route Server enabled on the spoke peering, so that spokes use the Route Server
hosted in the hub. (useRemoteGateways)
*/
resource spokeAToHub 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2026-03-01' = {
    name: 'peer-vnet-spoke-a-nus-vnet-connectivity-nus'
    parent: spokeAvnet
    properties: {
        allowForwardedTraffic: true
        allowVirtualNetworkAccess: true
        allowGatewayTransit: false
        useRemoteGateways: true
        remoteVirtualNetwork: {
            id: connectivityNetwork.id
        }
    }
    dependsOn: [
        peerToSpokeA
    ]
}
// Note: A race condition can occur if AllowGatewayTransit is not enabled given 
// useRemoteGateways is applied first. The PeerToHub MUST depend on Hub to Peer 

resource spokeAvnet 'Microsoft.Network/virtualNetworks@2026-03-01' = {
    name: 'spoke-a-nus-vnet'
    location: resourceGroup().location
    properties: {
        addressSpace: {
            addressPrefixes: [
                '10.1.0.0/21'
            ]
        }
    }
}


resource spokeAsnet 'Microsoft.Network/virtualNetworks/subnets@2026-03-01' = {
    name: 'spoke-a-nus-snet'
    parent: spokeAvnet
    properties: {
        addressPrefix: '10.1.1.0/24'
        privateEndpointNetworkPolicies: 'Disabled'
        privateLinkServiceNetworkPolicies: 'Disabled'
        defaultOutboundAccess: false
    }
}


// ================================================
// Spoke B Configuration
// ================================================

resource peerToSpokeB 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2026-03-01' = {
    name: 'peer-connectivity-nus-vnet-spoke-b-nus-vnet'
    parent: connectivityNetwork
    properties: {
        allowForwardedTraffic: true
        allowVirtualNetworkAccess: true
        allowGatewayTransit: true
        useRemoteGateways: false
        remoteVirtualNetwork: {
            id: spokeBvnet.id
        }
    }
}

/*
Virtual network peering must have Use the remote virtual network's gateway or 
Route Server enabled on the spoke peering, so that spokes use the Route Server
hosted in the hub. (useRemoteGateways)
*/
resource spokeBToHub 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2026-03-01' = {
    name: 'peer-vnet-spoke-b-nus-vnet-connectivity-nus'
    parent: spokeBvnet
    properties: {
        allowForwardedTraffic: true
        allowVirtualNetworkAccess: true
        allowGatewayTransit: false
        useRemoteGateways: true
        remoteVirtualNetwork: {
            id: connectivityNetwork.id
        }
    }
    dependsOn: [
        peerToSpokeB
    ]
}


resource spokeBvnet 'Microsoft.Network/virtualNetworks@2026-03-01' = {
    name: 'spoke-b-nus-vnet'
    location: resourceGroup().location
    properties: {
        addressSpace: {
            addressPrefixes: [
                '10.2.0.0/21'
            ]
        }

    }
}


resource spokeBsnet 'Microsoft.Network/virtualNetworks/subnets@2026-03-01' = {
    name: 'spoke-b-nus-snet'
    parent: spokeBvnet
    properties: {
        addressPrefix: '10.2.1.0/24'
        privateEndpointNetworkPolicies: 'Disabled'
        privateLinkServiceNetworkPolicies: 'Disabled'
        defaultOutboundAccess: false
    }
}


// References
// Azure Route Server: https://github.com/Azure/azure-quickstart-templates/blob/master/quickstarts/microsoft.network/route-server/main.bicep
// Hub and Spoke: https://github.com/Azure-Samples/azure-hub-spoke/blob/main/hub-spoke/bicep/main.bicep
// Route Injection in Spokes: https://learn.microsoft.com/en-us/azure/route-server/route-injection-in-spokes
// Peer Route Server with Virtual Appliance: https://learn.microsoft.com/en-us/azure/route-server/peer-route-server-with-virtual-appliance
// Gateway Transit Reference Hub & Spoke: https://learn.microsoft.com/en-us/azure/virtual-network/virtual-network-peering-overview#gateways-and-on-premises-connectivity
