# Trading Signal Analyzer

A microservices-based application that monitors Reddit for potential trading signals and uses LLM-powered analysis to detect buy/sell indicators.

## Architecture

This project consists of several components:

1. **Reddit Poller** (Go): Monitors Reddit (specifically r/wallstreetbets) for new posts and streams them to Redis
2. **Strategy Worker** (Python): Consumes Reddit posts from Redis, analyzes them with a Groq LLM, and generates trading signals
3. **Redis**: Acts as the message broker between components using Redis Streams
4. **Redis Inspector**: Utility for monitoring and debugging Redis Streams
5. **Centrifugo**: Real-time messaging server for pushing trading signals to frontend clients
6. **Web Front End**: Minimal React front end displaying latest signals

## Infrastructure

The application runs on Kubernetes (K3s) and is deployed with Terraform in two stages:

1. **Platform**: Creates the K3s cluster and basic infrastructure
2. **Services**: Deploys Redis, Reddit Poller, and Strategy Worker

All apps are small and deployed via InitContainers and ConfigMaps.
This is to avoid external dependencies on Cotainer Registries and to avoid having to host our own Registry or even rely on Docker being present while building.

## Prerequisites

- Terraform (v1.0+)
- kubectl
- A Reddit API account with client credentials
- A Groq API key for LLM access

## Quick Start

### 1. Set up environment variables

```bash
export TF_VAR_redis_password="..."

export TF_VAR_reddit_client_id="..."
export TF_VAR_reddit_client_secret="..."
export TF_VAR_reddit_username="..."
export TF_VAR_reddit_password="..."

export TF_VAR_hcloud_token="..."

export TF_VAR_groq_api_key="..."

export TF_VAR_centrifugo_token_hmac_secret="..."
export TF_VAR_centrifugo_api_key="..."
export TF_VAR_centrifugo_admin_password="..."
export TF_VAR_centrifugo_admin_secret="..."
export TF_VAR_TF_VAR_centrifugo_token="..."
```

### 2. Deploy everything with one command

```bash
./deploy.sh
```

This script will:

- Create a K3s cluster
- Deploy Redis, Reddit Poller, and Strategy Worker
- Set up the Redis Inspector for monitoring
- Push events to the FE with Centrifugo
- Host the web front end (provided you supply a domain)

### 3. Connect to your cluster

```bash
export KUBECONFIG=kubeconfig.yaml
kubectl get pods --all-namespaces
```

## Deployment

To deploy or destroy all stages do:
`deploy.sh`
`destroy.sh`

## Monitoring the System

### Using Redis Inspector

To inspect Redis streams and monitor trading signals:

```bash
kubectl exec -it redis-inspector -n trading -- /bin/sh
```

Once connected, run one of the following:

- `inspect-redis-streams.sh` - Provides a detailed one-time inspection of streams and consumer groups
- `monitor-redis-streams.sh` - Shows a real-time view of streams that updates every 5 seconds

## Components

### Reddit Poller (Go)

Monitors Reddit for new posts and adds them to the `reddit-events` Redis stream. See [apps/reddit-poller/README.md](apps/reddit-poller/README.md) for details.

### Strategy Worker (Python)

Analyzes posts using Groq LLM and generates trading signals. See [apps/reddit-strategy/README.md](apps/reddit-strategy/README.md) for details.

### Redis Streams Architecture

The application uses Redis Streams for reliable message processing:

- **reddit-events**: Input stream of Reddit posts from the poller
- **trade-signals**: Output stream of trading signals from the strategy worker that are also pushed to Centrifugo
- **Consumer Groups**: Allow multiple strategy workers to process posts in parallel without duplication

## Centrifugo

Provides real-time updates of trading signals to web clients. Connected to the strategy worker which pushes signals as they're generated. See [apps/frontend/README.md](apps/frontend/README.md) for details on connecting clients.

#### Monitoring Centrifugo

To check Centrifugo's status and view connected clients:

```bash
# Access Centrifugo admin interface (requires port-forwarding)
kubectl port-forward -n trading svc/centrifugo 8000:8000 9000:9000
```

### Front End

Shows latest events and short history as well as connection status.
See [fe/README.md](fe/README.md) for details.
