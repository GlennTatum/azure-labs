#!/bin/bash

set -euox

RG="connectivity-rg-nus"

if !(cat /tmp/gwpasswd); then
    openssl rand -base64 16 > /tmp/gwpasswd
fi

az group create --name "${RG}" --location "northcentralus"

az deployment group create --resource-group "${RG}" \
    --template-file deploy.bicep \
    --parameters password=$(cat /tmp/gwpasswd)