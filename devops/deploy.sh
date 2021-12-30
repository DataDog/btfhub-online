#! /bin/bash

IMAGE_NAME=${IMAGE_NAME:-"us.gcr.io/seekret/btfhub"}

gcloud run deploy btfhub --image "$IMAGE_NAME" --region us-east1 --allow-unauthenticated --min-instances=1 \
  --max-instances=5 --service-account=$SERVICE_ACCOUNT --format=json --project $PROJECT_ID \
  --set-env-vars="ARCHIVE_DIR=/archive,TOOLS_DIR=/app/tools" --memory 2Gi

gcloud scheduler jobs create http update-btfhub --schedule "0 12 1 * *" \
   --http-method=POST \
   --uri=https://btfhub.seekret.com/update \
   --oidc-service-account-email=$SERVICE_ACCOUNT   \
   --oidc-token-audience=https://btfhub.seekret.com
