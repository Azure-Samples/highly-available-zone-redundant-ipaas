$rg = 'hazripaas5-wus3-rg'          # <-- Name of Resource Group to deploy to.
$certKeyVault = 'fscale-kv'         # <-- Name of Key Vault that stores TLS cert. Does not need to be in the same resource group.
$certSecretId = 'hazr-fscale-nz'    # <-- Secret Id of the certificate
$apimSslCertKeyVaultId = "https://$certKeyVault.vault.azure.net/secrets/$certSecretId"
$developmentEnvironment = $true     # <-- Set to false for Production deployment

az group create --name $rg --location westus3

$identity = ( az identity create --name hazripaas-appgw-user --resource-group $rg -o json | ConvertFrom-Json )

az keyvault set-policy -n $certKeyVault --secret-permissions get --object-id $identity.principalId

az deployment group create --resource-group $rg --template-file ../bicep/main.bicep --parameters `
    "developmentEnvironment=$developmentEnvironment" `
    "apimSslCertKeyVaultId=$apimSslCertKeyVaultId" `
    "apimUserIdentityId=$($identity.id)"
