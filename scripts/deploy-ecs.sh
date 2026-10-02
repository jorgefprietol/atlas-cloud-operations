#!/usr/bin/env bash
set -euo pipefail
registry="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$registry"
for service in api worker; do
  if [[ "$service" == api ]]; then ecr="$API_ECR"; family="$API_TASK_FAMILY"; target="$API_SERVICE"; else ecr="$WORKER_ECR"; family="$WORKER_TASK_FAMILY"; target="$WORKER_SERVICE"; fi
  source="ghcr.io/${GITHUB_REPOSITORY}-${service}:${RELEASE_SHA}"
  docker pull "$source"
  # Immutable tags may already exist when retrying a partially completed deployment.
  if ! digest=$(aws ecr describe-images --repository-name "${ecr#*/}" --image-ids "imageTag=$RELEASE_SHA" --query 'imageDetails[0].imageDigest' --output text 2>/dev/null); then
    docker tag "$source" "$ecr:$RELEASE_SHA"
    docker push "$ecr:$RELEASE_SHA"
    digest=$(aws ecr describe-images --repository-name "${ecr#*/}" --image-ids "imageTag=$RELEASE_SHA" --query 'imageDetails[0].imageDigest' --output text)
  fi
  aws ecs describe-task-definition --task-definition "$family" --query taskDefinition > task.json
  jq --arg image "$ecr@$digest" --arg service "$service" '.containerDefinitions |= map(if .name == $service then .image = $image else . end) | del(.taskDefinitionArn,.revision,.status,.requiresAttributes,.compatibilities,.registeredAt,.registeredBy)' task.json > task-updated.json
  arn=$(aws ecs register-task-definition --cli-input-json file://task-updated.json --query taskDefinition.taskDefinitionArn --output text)
  aws ecs update-service --cluster "$ECS_CLUSTER" --service "$target" --task-definition "$arn" >/dev/null
  aws ecs wait services-stable --cluster "$ECS_CLUSTER" --services "$target"
  active=$(aws ecs describe-services --cluster "$ECS_CLUSTER" --services "$target" --query 'services[0].taskDefinition' --output text)
  [[ "$active" == "$arn" ]] || { echo "ECS rolled back $service; deployment failed"; exit 1; }
done
