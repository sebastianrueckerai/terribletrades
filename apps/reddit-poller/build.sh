#!/bin/bash
# apps/reddit-poller/build.sh
set -e

# Get master IP from Terraform output
MASTER_IP=$(cd ../../infra/platform && terraform output -raw k3s_master_ip)
SSH_PRIV_PATH=${TF_VAR_ssh_priv_path:-"~/.ssh/id_ed25519"}

echo "Building Reddit Poller Docker image..."
docker build -t reddit-poller:latest .

echo "Saving image to tarball..."
docker save reddit-poller:latest > reddit-poller.tar

echo "Copying image to K3s cluster..."
scp -i "$SSH_PRIV_PATH" -o StrictHostKeyChecking=no reddit-poller.tar root@$MASTER_IP:/tmp/

echo "Loading image on master node..."
ssh -i "$SSH_PRIV_PATH" -o StrictHostKeyChecking=no root@$MASTER_IP "ctr images import /tmp/reddit-poller.tar"

echo "Image built and loaded successfully!"