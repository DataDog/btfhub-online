#! /bin/bash

IMAGE_NAME=${IMAGE_NAME:-"us.gcr.io/seekret/btfhub"}

gcloud run deploy btfhub --image "$IMAGE_NAME" --region us-east1 --allow-unauthenticated --min-instances=1 \
  --max-instances=100 --service-account=$SERVICE_ACCOUNT --format=json --project $PROJECT_ID --concurrency=40
