#!/usr/bin/env bash

set -euo pipefail

# to authenticate as a service principal, at the plan stage, you need
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

# -detailed error code give 2 as rc if plan needs an apply
set +e
terraform plan -detailed-exitcode "${@}"
rc=$?
set -e

if [[ $rc -eq 0 ]]; then
  echo "No diff, no apply needed"
  echo "##vso[task.setvariable variable=result;isOutput=true]unchanged"
elif [[ $rc -eq 1 ]]; then
  echo "Error running plan"
  exit 1
elif [[ $rc -eq 2 ]]; then
  echo "Diff, apply needed"
  echo "##vso[task.setvariable variable=result;isOutput=true]changed"
else
  echo "Unexpected rc $rc - erroring"
  exit $rc
fi
