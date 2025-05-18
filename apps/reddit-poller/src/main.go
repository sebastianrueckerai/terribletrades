package main

import (
	"container/list"
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/go-redis/redis/v8"
	"github.com/vartanbeno/go-reddit/v2/reddit"
)

const (
	seenLimit = 500 // max posts to remember
)

var (
	ctx       = context.Background()
	seenPosts = make(map[string]*list.Element)
	seenList  = list.New() // LRU: front = newest, back = oldest

	// Health check state
	appState struct {
		sync.RWMutex
		redisConnected        bool
		redditConnected       bool
		lastSuccessfulPoll    time.Time
		messageCount          int
		errors                []string
		maxStoredErrors       int
	}
)

// Initialize app state
func init() {
	appState.maxStoredErrors = 100
	appState.errors = make([]string, 0, appState.maxStoredErrors)
}

// Health check handlers
func setupHealthServer(port string) {
	// Livez endpoint - basic aliveness check
	http.HandleFunc("/livez", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]string{"status": "alive"})
	})

	// Readyz endpoint - checks if dependencies are ready
	http.HandleFunc("/readyz", func(w http.ResponseWriter, r *http.Request) {
		appState.RLock()
		redisOK := appState.redisConnected
		redditOK := appState.redditConnected
		appState.RUnlock()

		w.Header().Set("Content-Type", "application/json")

		if redisOK && redditOK {
			w.WriteHeader(http.StatusOK)
			json.NewEncoder(w).Encode(map[string]string{"status": "ready"})
		} else {
			w.WriteHeader(http.StatusServiceUnavailable)
			json.NewEncoder(w).Encode(map[string]interface{}{
				"status":          "not_ready",
				"redis_connected": redisOK,
				"reddit_connected": redditOK,
			})
		}
	})

	// Full health status endpoint
	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		appState.RLock()
		redisOK := appState.redisConnected
		redditOK := appState.redditConnected
		lastPoll := appState.lastSuccessfulPoll
		msgCount := appState.messageCount
		
		// Get last 5 errors at most
		errorCount := len(appState.errors)
		recentErrors := []string{}
		if errorCount > 0 {
			startIdx := 0
			if errorCount > 5 {
				startIdx = errorCount - 5
			}
			recentErrors = appState.errors[startIdx:errorCount]
		}
		appState.RUnlock()

		w.Header().Set("Content-Type", "application/json")

		// Check if we have polled recently (last 30 seconds)
		recentPoll := time.Since(lastPoll) < 30*time.Second

		status := "healthy"
		httpStatus := http.StatusOK
		
		if !redisOK || !redditOK {
			status = "unhealthy"
			httpStatus = http.StatusServiceUnavailable
		}

		w.WriteHeader(httpStatus)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"status":            status,
			"redis_connected":   redisOK,
			"reddit_connected":  redditOK,
			"last_poll":         lastPoll,
			"recent_poll":       recentPoll,
			"message_count":     msgCount,
			"recent_errors":     recentErrors,
		})
	})

	// Start HTTP server in a goroutine
	go func() {
		log.Printf("Starting health server on port %s", port)
		if err := http.ListenAndServe(":"+port, nil); err != nil {
			log.Fatalf("Health server failed: %v", err)
		}
	}()
}

func rememberPost(id string) {
	// If already exists, move to front
	if elem, exists := seenPosts[id]; exists {
		seenList.MoveToFront(elem)
		return
	}

	// Add to front
	elem := seenList.PushFront(id)
	seenPosts[id] = elem

	// Trim if needed
	if seenList.Len() > seenLimit {
		tail := seenList.Back()
		if tail != nil {
			delete(seenPosts, tail.Value.(string))
			seenList.Remove(tail)
		}
	}
}

func hasSeen(id string) bool {
	_, exists := seenPosts[id]
	return exists
}

func recordError(err string) {
	appState.Lock()
	defer appState.Unlock()
	
	// Add error to the list
	appState.errors = append(appState.errors, err)
	
	// Trim if needed
	if len(appState.errors) > appState.maxStoredErrors {
		appState.errors = appState.errors[1:]
	}
}

func main() {
	// Get environment variables
	redditID := os.Getenv("REDDIT_CLIENT_ID")
	redditSecret := os.Getenv("REDDIT_CLIENT_SECRET")
	redditUser := os.Getenv("REDDIT_USERNAME")
	redditPass := os.Getenv("REDDIT_PASSWORD")
	redisAddr := os.Getenv("REDIS_ADDR")
	redisPass := os.Getenv("REDIS_PASSWORD")
	healthPort := os.Getenv("HEALTH_PORT")
	redditAppName := os.Getenv("REDDIT_APP_NAME")
	subredditEnv := os.Getenv("SUBREDDITS")

	if redditAppName == "" {
		redditAppName = "reddit-watcher" // Default app name if not provided
	}

	if healthPort == "" {
		healthPort = "8080" // Default health check port
	}

	var subreddits []string
	if subredditEnv != "" {
		// Split by comma and trim whitespace from each subreddit
		for _, sub := range strings.Split(subredditEnv, ",") {
			trimmedSub := strings.TrimSpace(sub)
			if trimmedSub != "" {
				subreddits = append(subreddits, trimmedSub)
			}
		}
	}

	// Use default subreddits if none were provided or if parsing resulted in empty list
	if len(subreddits) == 0 {
		subreddits = []string{"wallstreetbets", "pennystocks"}
		log.Printf("No valid subreddits provided in environment, using defaults: %v", subreddits)
	} else {
		log.Printf("Monitoring subreddits from environment: %v", subreddits)
	}

	// Start health check server
	setupHealthServer(healthPort)
	log.Printf("Health check server started on port %s", healthPort)

	// Initialize Redis client
	redisClient := redis.NewClient(&redis.Options{
		Addr:     redisAddr,
		Password: redisPass,
		DB:       0,
	})

	// Test Redis connection
	_, err := redisClient.Ping(ctx).Result()
	if err != nil {
		log.Printf("Redis connection failed: %v", err)
		recordError("Redis connection failed: " + err.Error())
		appState.Lock()
		appState.redisConnected = false
		appState.Unlock()
	} else {
		log.Printf("Redis connection successful")
		appState.Lock()
		appState.redisConnected = true
		appState.Unlock()
	}

	// Set up Reddit client with proper User-Agent
	creds := reddit.Credentials{
		ID:       redditID,
		Secret:   redditSecret,
		Username: redditUser,
		Password: redditPass,
	}

	// Create custom user agent string
	userAgent := fmt.Sprintf("go:%s:v1.0.0 (by /u/%s)", redditAppName, redditUser)
	log.Printf("Using User-Agent: %s", userAgent)

	client, err := reddit.NewClient(
		creds,
		reddit.WithUserAgent(userAgent),
	)

	if err != nil {
		log.Fatalf("Failed to init Reddit client: %v", err)
		recordError("Failed to init Reddit client: " + err.Error())
		appState.Lock()
		appState.redditConnected = false
		appState.Unlock()
	} else {
		appState.Lock()
		appState.redditConnected = true
		appState.Unlock()
	}

	// Main polling loop
	for {
		sleepTime := 1 * time.Second // Default wait time
		
		// Loop through each subreddit
		for _, subreddit := range subreddits {
			posts, resp, err := client.Subreddit.NewPosts(context.Background(), subreddit, &reddit.ListOptions{Limit: 10})
			
			// Check rate limits and handle them appropriately
			if resp != nil {
				// Check Reddit rate limit headers
				remaining, _ := strconv.Atoi(resp.Header.Get("X-Ratelimit-Remaining"))
				resetTime, _ := strconv.Atoi(resp.Header.Get("X-Ratelimit-Reset"))
				used, _ := strconv.Atoi(resp.Header.Get("X-Ratelimit-Used"))
				
				log.Printf("Rate limits for %s: %d used, %d remaining, %d seconds until reset", 
					subreddit, used, remaining, resetTime)
				
				// If we're getting close to the limit, respect the reset time
				if remaining < 10 {
					log.Printf("Approaching rate limit! Slowing down for %d seconds", resetTime)
					sleepTime = time.Duration(resetTime) * time.Second
				}
			}
			
			if err != nil {
				log.Printf("Failed to fetch posts from %s: %v", subreddit, err)
				recordError(fmt.Sprintf("Failed to fetch posts from %s: %v", subreddit, err.Error()))
				appState.Lock()
				appState.redditConnected = false
				appState.Unlock()
				continue // Skip to next subreddit
			}

			// Update Reddit connection status and last successful poll time
			appState.Lock()
			appState.redditConnected = true
			appState.lastSuccessfulPoll = time.Now()
			appState.Unlock()

			for _, post := range posts {
				// Skip if we've already seen this post
				if hasSeen(post.ID) {
					continue
				}

				log.Printf("New unseen post in r/%s: %s", subreddit, post.Title)
				rememberPost(post.ID)

				// Add to Redis stream
				_, err := redisClient.XAdd(ctx, &redis.XAddArgs{
					Stream: "reddit-events",
					Values: map[string]interface{}{
						"id":        post.ID,
						"title":     post.Title,
						"body":      post.Body,
						"url":       post.URL,
						"author":    post.Author,
						"subreddit": post.SubredditName,
						"created":   post.Created.Time.Format(time.RFC3339),
					},
				}).Result()

				if err != nil {
					log.Printf("Redis push failed: %v", err)
					recordError("Redis push failed: " + err.Error())
					appState.Lock()
					appState.redisConnected = false
					appState.Unlock()
				} else {
					log.Printf("Post pushed to Redis.")
					appState.Lock()
					appState.redisConnected = true
					appState.messageCount++
					appState.Unlock()
				}
			}
		}

		// Wait before next polling cycle, using calculated sleep time based on rate limits
		time.Sleep(sleepTime)
	}
}