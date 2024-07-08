#!/usr/bin/env bash
# note we require bash v4+, as we use associative arrays
# assumes wget and jq installed, which is typical on azure devops agents

set -euo pipefail

function parseCLIArgs() {
  local -n args="${1}"

  shift

  while getopts "v:d:" arg; do
    case "${arg}" in
    v) args[version]="${OPTARG}" ;;
    d) args[directory]="${OPTARG}" ;;
    *) usage && exit 1;;
    esac
  done
}

function argSanity() {
  local -nr args="${1}"

  if [[ ${#args[version]} -eq 0 ]]; then
    echo "must specify a version of TF"
    usage
    exit 1
  elif [[ ${#args[directory]}  -eq 0 ]]; then
    echo "must specify an install directory" 
    usage
    exit 1
  fi    
}

function usage() {
  echo "Mandatory arguments - "
  echo "  -v <version> : version of terraform to install"
  echo "Optional arguments - "
  echo "  -d <path>    : install dir, default /usr/local/bin"
}

function install() {
  local -nr args="${1}"
  local rc
  local install_required=1

  if [[ -s "${args[directory]}/terraform" ]]; then
    echo "terraform installed, check correct version"
    installed_version=$("${args[directory]}/terraform" version -json | jq -r .terraform_version )
    echo "installed version: ${installed_version}"
    echo "required version : ${args[version]}"

    if [[ ( -v installed_version) && ("${installed_version}" == "${args[version]}") ]]; then
      echo "correct version already installed"
      install_required=0
    fi
  fi

  if [[ "${install_required}" -eq 1 ]]; then
    install_terraform args
  fi
}

function install_terraform() {
  # shell doesnt handle same name between functions well
  local -nr installation_args="${1}"

  local package="terraform_${args[version]}_linux_amd64.zip"
  local url="https://releases.hashicorp.com/terraform/${args[version]}/${package}"

  echo "Download ${url}"
  wget --no-verbose "${url}"
  unzip "${package}"
  echo "install to destination directory"
  sudo cp -v terraform "${args[directory]}"
  echo "installed version" $("${args[directory]}/terraform" version -json | jq -r .terraform_version)
  rm "${package}"
  rm terraform # remanent of unzip
}

# map of k-v pairs
declare -A arguments=(
  [directory]="/usr/local/bin"
  [version]=""
)

echo "Before processing, CLI args are"
echo "${*}"

echo "parse CLI"
parseCLIArgs arguments "${@}"

echo "check argument sanity"
argSanity arguments

install arguments

exit 0