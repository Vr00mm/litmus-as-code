#!/bin/bash

set -e
set -o pipefail

source /functions.sh

LITMUS_CONFIGURATION_PATH="${1}"

login
#create_user
create_or_update_projects
get_projects
deploy_agents
