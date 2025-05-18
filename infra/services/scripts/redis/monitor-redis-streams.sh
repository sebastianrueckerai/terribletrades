#!/bin/sh
# Script to monitor Redis streams in real-time

while true; do
  clear
  echo "==== MONITORING REDIS STREAMS ===="
  echo "Press Ctrl+C to exit\n"
  
  echo "reddit-events stream:"
  redis-cli -h $REDIS_HOST -a $REDIS_PASSWORD XLEN reddit-events
  
  echo "\ntrade-signals stream:"
  redis-cli -h $REDIS_HOST -a $REDIS_PASSWORD XLEN trade-signals
  
  echo "\nLatest events (3):"
  redis-cli -h $REDIS_HOST -a $REDIS_PASSWORD XREVRANGE reddit-events + - COUNT 3
  
  echo "\nLatest signals (3):"
  SIGNALS=$(redis-cli -h $REDIS_HOST -a $REDIS_PASSWORD XREVRANGE trade-signals + - COUNT 3)
  
  # Basic formatting for signals in monitoring mode
  echo "$SIGNALS" | awk '
  BEGIN { id=""; }
  
  # Print ID and basic info
  /^[0-9]/ { 
    id=$1; 
    printf "\nID: %s\n", id;
  }
  
  # Show key decision fields
  /decision/ { 
    value=$4;
    printf "  decision: %s\n", value;
  }
  
  /ticker/ { 
    value=$4;
    printf "  ticker: %s\n", value;
  }
  '
  
  sleep 5
done