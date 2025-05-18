## Dependencies

- `redis.asyncio`: Async Redis client with Streams support
- `groq`: Groq LLM API client
- `asyncio`: Asynchronous I/O for concurrent operations# Reddit Strategy Worker

A Python application that analyzes Reddit posts using an LLM and generates trading signals.

## Overview

The Reddit Strategy Worker consumes posts from a Redis Stream, analyzes them with Groq's LLM, and detects potential buy/sell trading signals. It then publishes these signals to another Redis Stream for further processing.

## Features

- **LLM-powered analysis**: Uses Groq's LLM to analyze Reddit posts for trading signals
- **Redis Streams integration**: Consumes from and publishes to Redis Streams
- **Consumer group model**: Enables horizontal scaling with multiple workers
- **Reliable message processing**: Acknowledges messages only after successful processing
- **Graceful shutdown**: Handles termination signals properly

## Configuration

The application is configured via environment variables:

| Variable          | Description                                           | Required |
| ----------------- | ----------------------------------------------------- | -------- |
| `GROQ_MODEL_NAME` | Groq LLM model name (e.g., "llama-3.3-70b-versatile") | Yes      |
| `GROQ_API_KEY`    | Groq API key                                          | Yes      |
| `REDIS_ADDR`      | Redis server address (e.g., "redis:6379")             | Yes      |
| `REDIS_PASSWORD`  | Redis server password                                 | Yes      |
| `STREAM`          | Input Redis Stream name (e.g., "reddit-events")       | Yes      |
| `GROUP`           | Consumer group name (e.g., "strategy-group")          | Yes      |
| `CONSUMER`        | Consumer name (e.g., "strategy-worker-1")             | Yes      |
| `SIGNAL_STREAM`   | Output Redis Stream name (e.g., "trade-signals")      | Yes      |
| `PROMPT_FILE`     | Path to the LLM prompt file                           | Yes      |
| `LOG_LEVEL`       | Logging level (default: "INFO")                       | No       |

## Build and Run Locally

### Prerequisites

- Python 3.12 or later
- Redis server
- Groq API key

### Setup

```bash
pip install -r requirements.txt
```

### Running

```bash
export GROQ_MODEL_NAME=llama-3.3-70b-versatile
export GROQ_API_KEY=your_groq_api_key
export REDIS_ADDR=localhost:6379
export REDIS_PASSWORD=your_redis_password
export STREAM=reddit-events
export GROUP=strategy-group
export CONSUMER=strategy-worker-1
export SIGNAL_STREAM=trade-signals
export PROMPT_FILE=./prompt.txt

python src/strategy_worker.py
```

## Deployment

The application is deployed to Kubernetes using Terraform. The deployment:

1. Creates ConfigMaps with the Python source code and prompt template
2. Uses an init container to set up the Python environment
3. Runs the application in a container with the necessary environment variables

See the main project README for deployment instructions.

## How It Works

1. On startup, the worker connects to Redis and ensures the consumer group exists
2. It continuously reads messages from the input stream using the consumer group
3. For each message, it:
   - Extracts the post title and body
   - Creates a prompt for the LLM
   - Calls the Groq API to analyze the post
   - Extracts a decision code from the LLM response (0 = no signal, 1 = buy, 2 = sell)
   - For buy/sell signals, publishes to the output stream
   - Acknowledges the message to the consumer group

## Redis Streams and Consumer Groups

The worker uses Redis Streams and Consumer Groups to enable:

- **Reliable delivery**: Messages aren't lost if the worker crashes
- **Exactly-once processing**: Each message is processed by only one worker
- **Horizontal scaling**: Multiple workers can process messages in parallel
- **Message acknowledgment**: Messages are only removed from the pending list after successful processing

## Prompt Engineering

The LLM prompt instructs the model to analyze the post for trading signals and end its response with a numeric code:

```
You are a trading signal analyzer. You will read a Reddit post and determine if it contains a trading signal.

Analyze the post for sentiment and trading signals related to stocks or cryptocurrencies. Look for:
- Clear buy or sell recommendations
- Strong bullish or bearish sentiment
- Specific ticker mentions with directional predictions
- Claims of substantial price movements

End your response with a single digit:
0 = No clear trading signal
1 = Buy signal detected
2 = Sell signal detected
```

## Code Structure

- `strategy_worker.py`: Main application code
- Core functions:
  - `extract_decision()`: Parses the LLM response to determine the signal type
  - `process_entry()`: Processes a single Reddit post message
  - `process_messages()`: Main processing loop for consuming stream messages

## Testing

The application includes pytest-based tests for key components. You can run tests using the provided Makefile:

```bash
cd apps/reddit-strategy

# Install dependencies (including development dependencies)
make setup

# Run the tests with fake Redis
make test

# Clean up cache files
make clean
```

The tests use fakeredis to mock Redis operations, allowing unit testing without a live Redis instance.

### Makefile Contents

```makefile
.PHONY: setup test clean

# Set up development environment
setup:
	python -m pip install -r requirements.txt
	python -m pip install -r requirements-dev.txt

# Run tests with fake Redis
test:
	python -m pytest -v

# Clean up
clean:
	rm -rf __pycache__ .pytest_cache
	find . -name "*.pyc" -delete
```

## Building Docker Image

To build a Docker image for the application, you'll need to first create a Dockerfile. Save the following as `Dockerfile` in the `apps/reddit-strategy` directory:

```dockerfile
FROM python:3.12-slim

WORKDIR /app

# Copy requirements first for better caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy source code
COPY src/ ./src/

# Set the prompt file
COPY src/prompt.txt /app/prompt.txt

# Environment variables will be provided in deployment
ENV GROQ_MODEL_NAME=llama-3.3-70b-versatile
ENV PROMPT_FILE=/app/prompt.txt

# Run the app
CMD ["python", "src/strategy_worker.py"]
```

Then, you can use the provided build script:

```bash
cd apps/reddit-strategy
chmod +x build.sh
./build.sh [optional-registry-url]
```

The build script:

1. Creates a Docker image tagged with the current git commit hash
2. Also tags the image as "latest"
3. Optionally pushes the image to a specified registry if a URL is provided

### build.sh Contents

```bash
#!/bin/bash
set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
IMAGE_NAME="reddit-strategy"
VERSION=$(git rev-parse --short HEAD 2>/dev/null || echo "latest")

# Build Docker image
echo "Building $IMAGE_NAME:$VERSION..."
docker build -t $IMAGE_NAME:$VERSION -t $IMAGE_NAME:latest $SCRIPT_DIR

echo "Image built: $IMAGE_NAME:$VERSION"

# If registry URL is provided, push to registry
if [ -n "$1" ]; then
  REGISTRY_URL="$1"
  REMOTE_IMAGE="$REGISTRY_URL/$IMAGE_NAME:$VERSION"
  REMOTE_LATEST="$REGISTRY_URL/$IMAGE_NAME:latest"

  echo "Tagging for registry: $REMOTE_IMAGE"
  docker tag $IMAGE_NAME:$VERSION $REMOTE_IMAGE
  docker tag $IMAGE_NAME:latest $REMOTE_LATEST

  echo "Pushing to registry..."
  docker push $REMOTE_IMAGE
  docker push $REMOTE_LATEST

  echo "Image pushed: $REMOTE_IMAGE"
fi
```

Note: When deployed via Terraform as described in the main README, you don't need to run this build script manually as the deployment uses an init container to set up the Python environment directly in the pod.

## Check health once deployed in k3s:

Check health endpoint

```bash
kubectl exec -n trading <POD_NAME> -- python -c "import urllib.request; print(urllib.request.urlopen('http://localhost:8080/livez').read().decode('utf-8'))"
```

Check readiness endpoint

```bash
kubectl exec -n trading <POD_NAME> -- python -c "import urllib.request; print(urllib.request.urlopen('http://localhost:8080/readyz').read().decode('utf-8'))"
```

Check full health status

```bash
kubectl exec -n trading <POD_NAME> -- python -c "import urllib.request; print(urllib.request.urlopen('http://localhost:8080/health').read().decode('utf-8'))"
```
