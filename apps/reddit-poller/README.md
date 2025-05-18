# Reddit Poller

A Go application that monitors Reddit (specifically r/wallstreetbets) for new posts and streams them to Redis.

## Overview

The Reddit Poller continuously polls the Reddit API for new posts from the r/wallstreetbets subreddit and adds them to a Redis Stream. It uses an LRU (Least Recently Used) cache to track posts it has already seen to avoid duplicates.

## Features

- **Real-time Reddit monitoring**: Polls r/wallstreetbets for new posts
- **Duplicate detection**: Uses an LRU cache to avoid duplicate posts
- **Redis Streams integration**: Pushes posts to Redis Streams for reliable message processing
- **Containerized deployment**: Runs in Kubernetes with an init container for building

## Configuration

The application is configured via environment variables:

| Variable               | Description                               | Required |
| ---------------------- | ----------------------------------------- | -------- |
| `REDDIT_CLIENT_ID`     | Reddit API client ID                      | Yes      |
| `REDDIT_CLIENT_SECRET` | Reddit API client secret                  | Yes      |
| `REDDIT_USERNAME`      | Reddit account username                   | Yes      |
| `REDDIT_PASSWORD`      | Reddit account password                   | Yes      |
| `REDIS_ADDR`           | Redis server address (e.g., "redis:6379") | Yes      |
| `REDIS_PASSWORD`       | Redis server password                     | Yes      |

## Build and Run Locally

### Prerequisites

- Go 1.22 or later
- Redis server
- Reddit API credentials

### Building

```bash
go mod download
go build -o reddit-poller .
```

### Running

```bash
export REDDIT_CLIENT_ID=your_client_id
export REDDIT_CLIENT_SECRET=your_client_secret
export REDDIT_USERNAME=your_username
export REDDIT_PASSWORD=your_password
export REDIS_ADDR=localhost:6379
export REDIS_PASSWORD=your_redis_password

./reddit-poller
```

## Deployment

The application is deployed to Kubernetes using Terraform. The deployment:

1. Creates a ConfigMap with the Go source code
2. Uses an init container to build the application
3. Runs the application in a container with the necessary environment variables

See the main project README for deployment instructions.

## Test

Run `go test -v`

## How It Works

1. The application connects to Reddit and Redis at startup
2. Every 5 seconds, it polls the Reddit API for new posts from r/wallstreetbets
3. For each new post, it checks the LRU cache to see if it's already been processed
4. New posts are added to the Redis Stream "reddit-events" with the following data structure:

```json
{
  "id": "post_id",
  "title": "Post title",
  "body": "Post body content",
  "url": "https://reddit.com/r/wallstreetbets/...",
  "author": "username",
  "subreddit": "wallstreetbets",
  "created": "2025-05-15T12:00:00Z"
}
```

## Code Structure

- `main.go`: Entry point and main application logic
- Functions:
  - `rememberPost()`: Adds posts to the LRU cache
  - `hasSeen()`: Checks if a post has already been processed
  - `main()`: Main application loop, connects to Reddit and Redis, polls for posts

## Dependencies

- [github.com/go-redis/redis/v8](https://github.com/go-redis/redis): Redis client
- [github.com/vartanbeno/go-reddit/v2](https://github.com/vartanbeno/go-reddit): Reddit API client
- Standard library: container/list for LRU cache implementation

## Health checks

Forward the pod's port 8080 to your local port 8080

```bash
kubectl port-forward -n trading pod/reddit-poller-[pod-id] 8080:8080
```

Then in another terminal, you can access the endpoints:

```bash
# Check liveness endpoint
curl http://localhost:8080/livez

# Check readiness endpoint
curl http://localhost:8080/readyz

# Check detailed health status
curl http://localhost:8080/health
```
