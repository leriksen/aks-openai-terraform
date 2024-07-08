#!/usr/bin/env bash

set -euo pipefail

echo "terraform init ${*}"

which terraform
terraform -version

terraform init "${@}"
