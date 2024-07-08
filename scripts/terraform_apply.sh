#!/usr/bin/env bash

set -euo pipefail

terraform apply -input=false -auto-approve tfplan.tfout
