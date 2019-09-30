#!/bin/bash

set -ex

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

if [ -z "${ENVOY_IMAGE}" ]; then
    echo "ENVOY_IMAGE environment is not defined"
    exit 1
fi

if [ -z "${RESEARCH_PREFERENCES_IMAGE}" ]; then
    echo "RESEARCH_PREFERENCES_IMAGE environment is not defined"
    exit 1
fi

if [ -z "${SEARCH_SERVICE_IMAGE}" ]; then
    echo "SEARCH_SERVICE_IMAGE environment is not defined"
    exit 1
fi

stack_output=$(aws --profile "${AWS_PROFILE}" --region "${AWS_DEFAULT_REGION}" \
    cloudformation describe-stacks --stack-name "${ENVIRONMENT_NAME}-ecs-cluster" \
    | jq '.Stacks[].Outputs[]')

task_role_arn=($(echo $stack_output \
    | jq -r 'select(.OutputKey == "TaskIamRoleArn") | .OutputValue'))

execution_role_arn=($(echo $stack_output \
    | jq -r 'select(.OutputKey == "TaskExecutionIamRoleArn") | .OutputValue'))

ecs_service_log_group=($(echo $stack_output \
    | jq -r 'select(.OutputKey == "ECSServiceLogGroup") | .OutputValue'))

envoy_log_level="debug"

generate_xray_container_json() {
    app_name=$1
    xray_container_json=$(jq -n \
    --arg ECS_SERVICE_LOG_GROUP $ecs_service_log_group \
    --arg AWS_REGION $AWS_DEFAULT_REGION \
    --arg AWS_LOG_STREAM_PREFIX "${app_name}-xray" \
    -f "${DIR}/xray-container.json")
}

generate_envoy_container_json() {
    app_name=$1
    envoy_container_json=$(jq -n \
    --arg ENVOY_IMAGE $ENVOY_IMAGE \
    --arg VIRTUAL_NODE "mesh/$MESH_NAME/virtualNode/${app_name}-vn" \
    --arg APPMESH_XDS_ENDPOINT "${APPMESH_XDS_ENDPOINT}" \
    --arg ENVOY_LOG_LEVEL $envoy_log_level \
    --arg ECS_SERVICE_LOG_GROUP $ecs_service_log_group \
    --arg AWS_REGION $AWS_DEFAULT_REGION \
    --arg AWS_LOG_STREAM_PREFIX "${app_name}-envoy" \
    -f "${DIR}/envoy-container.json")
}

generate_sidecars() {
    app_name=$1
    generate_envoy_container_json ${app_name}
    generate_xray_container_json ${app_name}
}

generate_search_service_task_def() {
    tags=$1
    task_def_json=$(jq -n \
    --arg NAME "$ENVIRONMENT_NAME-SearchService-${tags}" \
    --arg STAGE "$APPMESH_STAGE" \
    --arg TAGS "${tags}" \
    --arg APP_IMAGE $SEARCH_SERVICE_IMAGE \
    --arg AWS_REGION $AWS_DEFAULT_REGION \
    --arg ECS_SERVICE_LOG_GROUP $ecs_service_log_group \
    --arg AWS_LOG_STREAM_PREFIX_APP "searchservice-${tags}-app" \
    --arg TASK_ROLE_ARN $task_role_arn \
    --arg EXECUTION_ROLE_ARN $execution_role_arn \
    --argjson ENVOY_CONTAINER_JSON "${envoy_container_json}" \
    --argjson XRAY_CONTAINER_JSON "${xray_container_json}" \
    -f "${DIR}/searchservice-base-task-def.json")
    task_def=$(aws --profile "${AWS_PROFILE}" --region "${AWS_DEFAULT_REGION}" \
    ecs register-task-definition \
    --cli-input-json "$task_def_json")
}

generate_sidecars "researchpreferences"
task_def_json=$(jq -n \
    --arg NAME "$ENVIRONMENT_NAME-ResearchPreferences" \
    --arg STAGE "$APPMESH_STAGE" \
    --arg SEARCH_SERVICE_ENDPOINT "searchservice.$SERVICES_DOMAIN:9080" \
    --arg TCP_ECHO_ENDPOINT "tcpecho.$SERVICES_DOMAIN:2701" \
    --arg APP_IMAGE $RESEARCH_PREFERENCES_IMAGE \
    --arg AWS_REGION $AWS_DEFAULT_REGION \
    --arg ECS_SERVICE_LOG_GROUP $ecs_service_log_group \
    --arg AWS_LOG_STREAM_PREFIX_APP "researchpreferences-app" \
    --arg TASK_ROLE_ARN $task_role_arn \
    --arg EXECUTION_ROLE_ARN $execution_role_arn \
    --argjson ENVOY_CONTAINER_JSON "${envoy_container_json}" \
    --argjson XRAY_CONTAINER_JSON "${xray_container_json}" \
    -f "${DIR}/researchpreferences-base-task-def.json")
task_def=$(aws --profile "${AWS_PROFILE}" --region "${AWS_DEFAULT_REGION}" \
    ecs register-task-definition \
    --cli-input-json "$task_def_json")
researchpreferences_task_def_arn=($(echo $task_def \
    | jq -r '.taskDefinition | .taskDefinitionArn'))

generate_sidecars "searchservice-microsoft"
generate_search_service_task_def "microsoft"
searchservice_microsoft_task_def_arn=($(echo $task_def \
    | jq -r '.taskDefinition | .taskDefinitionArn'))

generate_sidecars "searchservice-dropbox"
generate_search_service_task_def "dropbox"
searchservice_dropbox_task_def_arn=($(echo $task_def \
    | jq -r '.taskDefinition | .taskDefinitionArn'))

generate_sidecars "searchservice-apple"
generate_search_service_task_def "apple"
searchservice_apple_task_def_arn=($(echo $task_def \
    | jq -r '.taskDefinition | .taskDefinitionArn'))

generate_sidecars "searchservice-tesla"
generate_search_service_task_def "tesla"
searchservice_tesla_task_def_arn=($(echo $task_def \
    | jq -r '.taskDefinition | .taskDefinitionArn'))