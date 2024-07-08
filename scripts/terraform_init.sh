#!/usr/bin/env bash

set -euo pipefail

# to authenticate as a service principal, at the init stage, you need
# SA name
# container name
# key (blob) name
# addSpnToEnvironment == true in AzureCLI@2 devops task
# plus the following as envvars
# (as envvars they dont get added to state file)
# ARM_USE_AZUREAD: true
# ARM_TENANT_ID    , obtained from addSpnToEnvironment
# ARM_CLIENT_ID    , obtained from addSpnToEnvironment
# ARM_CLIENT_SECRET, obtained from addSpnToEnvironment

export ARM_TENANT_ID="${tenantId}"
export ARM_CLIENT_ID="${servicePrincipalId}"
export ARM_CLIENT_SECRET="${servicePrincipalKey}"

echo "terraform init ${*}"

terraform init "${@}"
