#!/usr/bin/env bash

set -euo pipefail

terraform apply -input=false tfplan.tfout
