#!/bin/sh
# Script to inspect Redis streams with raw output (no formatting)

# Check if stream exists
redis-cli -h "$REDIS_HOST" -a "$REDIS_PASSWORD" EXISTS reddit-events | grep -q "1" || { echo "Stream reddit-events does not exist!"; exit 1; }

# Stream info
echo "\n==== STREAM INFORMATION ===="
redis-cli -h "$REDIS_HOST" -a "$REDIS_PASSWORD" XINFO STREAM reddit-events

# Consumer groups
echo "\n==== CONSUMER GROUPS ===="
redis-cli -h "$REDIS_HOST" -a "$REDIS_PASSWORD" XINFO GROUPS reddit-events

# Show latest messages
echo "\n==== LATEST 3 MESSAGES IN reddit-events ===="
redis-cli -h "$REDIS_HOST" -a "$REDIS_PASSWORD" XREVRANGE reddit-events + - COUNT 3

# Show trade signals if available
if redis-cli -h "$REDIS_HOST" -a "$REDIS_PASSWORD" EXISTS trade-signals | grep -q "1"; then
  echo "\n==== LATEST 3 SIGNALS IN trade-signals ===="
  redis-cli -h "$REDIS_HOST" -a "$REDIS_PASSWORD" XREVRANGE trade-signals + - COUNT 3
fi

# Check pending messages
echo "\n==== PENDING MESSAGES ===="
GROUPS=$(redis-cli -h "$REDIS_HOST" -a "$REDIS_PASSWORD" XINFO GROUPS reddit-events | grep name | awk '{print $2}')
for GROUP in $GROUPS; do
  echo "\nPending messages for group: $GROUP"
  redis-cli -h "$REDIS_HOST" -a "$REDIS_PASSWORD" XPENDING reddit-events "$GROUP"
done
