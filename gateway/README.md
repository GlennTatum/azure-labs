# NB/SB Firewall Setup with PFSense Network Virtual Appliance

## Resources

The following resources/assets will be deployed to created:
- 1x Public IP Address
- 1x Connectivity vnet w/ `/21` Address Range
- 1x Resource Group
- 1x Azure Route Server
- 1x Spoke VNet w/ default routes specified by Azure Route Server
- 1x Network Security Group attached to PFSense Virtual Machine NIC
- 1x NIC
- 1x Virtual Machine

## Pre-requisite Steps

1. Prior to beginning the lab, please create a **Subscription** to store the following resources.

2. Ensure that Microsoft.Compute is registered within your subscription to be able to provision virtual machines.

![alt text](media/registration.png)

3. Accept the EULA for the `pfsense` image:

```
az vm image accept-terms --plan pfsense-plus-public-tac-lite --offer pfsense-plus-public-cloud-fw-vpn-router --publish netgate
```

## Setup

1. Run the `deploy.sh` script to apply the bicep configuration

## Post-Setup Instructions

1. Access the Virtual Machine via the public IP Address
    - Login with the following credentials: `pfsenseadmin` `$(cat /tmp/gwpasswd)`

2. In the setup wizard configure the following settings.
    ```
    IP Address: 10.0.1.10
    Subnet Mask: 24
    Upstream Gateway: 10.0.1.1
    ```

### Configuring WireGuard Access for PFSense

## Additional Information

Query the PFSense NVA Image
```bash
az vm image list \
  --publisher netgate \
  --location eastus2 \
  --all \
  --output table
```