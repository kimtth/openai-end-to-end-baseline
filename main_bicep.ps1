$APP_GATEWAY_LISTENER_CERTIFICATE_APPSERV = [Convert]::ToBase64String([IO.File]::ReadAllBytes("appgw.pfx"))
$BASE_NAME="<your-base-name>"
$RESOURCE_GROUP = "rg-chat-baseline-$BASE_NAME"
$PRINCIPAL_ID = "<your-principal-id>"

az deployment group create -f ./infra-as-code/bicep/main.bicep `
 -g $RESOURCE_GROUP `
 -p appGatewayListenerCertificate=$APP_GATEWAY_LISTENER_CERTIFICATE_APPSERV `
 -p baseName=$BASE_NAME `
 -p yourPrincipalId=$PRINCIPAL_ID `
 -p jumpBoxAdminPassword="<your-jumpbox-admin-password>"
