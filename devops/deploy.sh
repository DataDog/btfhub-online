#! /bin/bash

IMAGE_NAME=${IMAGE_NAME:-"us.gcr.io/seekret/btfhub"}
REGION=${REGION:-"us-east1"}

if [[ -z $SERVICE_ACCOUNT ]]; then
  echo "SERVICE_ACCOUNT environment variable is mandatory"
fi

if [[ -z $PROJECT_ID ]]; then
  echo "$PROJECT_ID environment variable is mandatory"
fi

gcloud run deploy btfhub --image "$IMAGE_NAME" --region "$REGION" --allow-unauthenticated --min-instances=1   \
  --max-instances=100 --service-account=$SERVICE_ACCOUNT --format=json --project $PROJECT_ID --concurrency=40 \
  --set-env-vars="BUCKET_NAME=btfhub"
