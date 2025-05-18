# Verification Plan

## Step 1: Make the files executable
chmod +x deploy.sh
chmod +x apps/reddit-poller/build.sh

## Step 2: Check that all referenced files exist
# Verify that all paths in the updated files are correct
echo "Checking for important files..."
echo -n "apps/reddit-poller/src/main.go: "
[ -f apps/reddit-poller/src/main.go ] && echo "Found" || echo "Missing!"

echo -n "apps/reddit-poller/charts/Chart.yaml: "
[ -f apps/reddit-poller/charts/Chart.yaml ] && echo "Found" || echo "Missing!"

echo -n "apps/reddit-poller/charts/values.yaml: "
[ -f apps/reddit-poller/charts/values.yaml ] && echo "Found" || echo "Missing!"

echo -n "apps/reddit-poller/charts/templates/deployment.yaml: "
[ -f apps/reddit-poller/charts/templates/deployment.yaml ] && echo "Found" || echo "Missing!"

echo -n "infra/services/redis-values.yaml: "
[ -f infra/services/redis-values.yaml ] && echo "Found" || echo "Missing!"

## Step 3: Test running the build script
echo "You can test building the Reddit Poller with:"
echo "./deploy.sh --build-reddit-poller"

## Step 4: Test deploying the infrastructure and applications
echo "You can deploy the entire stack with:"
echo "./deploy.sh"

echo "This will run both stages of the deployment:"
echo "1. Create the K3s cluster in infra/platform"
echo "2. Deploy Redis and Reddit Poller in infra/services"