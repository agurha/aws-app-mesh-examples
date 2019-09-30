#!/bin/bash

set -ex

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

# ecs-rgcapp.yaml expects "true" or "false" (default is "false")
# will deploy the TesterService, which perpetually invokes /tags to generate history
: "${DEPLOY_TESTER:=false}"

# Creating Task Definitions
source ${DIR}/create-task-defs.sh

aws --profile "${AWS_PROFILE}" --region "${AWS_DEFAULT_REGION}" \
    cloudformation deploy \
    --stack-name "${ENVIRONMENT_NAME}-ecs-rgcapp" \
    --capabilities CAPABILITY_IAM \
    --template-file "${DIR}/ecs-rgcapp.yaml"  \
    --parameter-overrides \
    EnvironmentName="${ENVIRONMENT_NAME}" \
    ECSServicesDomain="${SERVICES_DOMAIN}" \
    AppMeshMeshName="${MESH_NAME}" \
    ResearchPreferencesTaskDefinition="${researchpreferences_task_def_arn}" \
    SearchServiceWhiteTaskDefinition="${searchservice_microsoft_task_def_arn}" \
    SearchServiceRedTaskDefinition="${searchservice_dropbox_task_def_arn}" \
    SearchServiceBlueTaskDefinition="${searchservice_apple_task_def_arn}" \
    SearchServiceBlackTaskDefinition="${searchservice_tesla_task_def_arn}" \
    DeployTester="${DEPLOY_TESTER}"

