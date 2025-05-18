package main

import (
	"container/list"
	"os"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/vartanbeno/go-reddit/v2/reddit"
)

// TestMainLoopWithMocks tests the main loop functionality with mocked dependencies
func TestMainLoopWithMocks(t *testing.T) {
	// Skip in short mode
	if testing.Short() {
		t.Skip("Skipping test in short mode.")
	}

	// Save original environment variables
	originalRedditID := os.Getenv("REDDIT_CLIENT_ID")
	originalRedditSecret := os.Getenv("REDDIT_CLIENT_SECRET")
	originalRedditUser := os.Getenv("REDDIT_USERNAME")
	originalRedditPass := os.Getenv("REDDIT_PASSWORD")
	originalRedisAddr := os.Getenv("REDIS_ADDR")
	originalRedisPass := os.Getenv("REDIS_PASSWORD")

	// Set test environment variables
	os.Setenv("REDDIT_CLIENT_ID", "test-id")
	os.Setenv("REDDIT_CLIENT_SECRET", "test-secret")
	os.Setenv("REDDIT_USERNAME", "test-user")
	os.Setenv("REDDIT_PASSWORD", "test-pass")
	os.Setenv("REDIS_ADDR", "localhost:6379")
	os.Setenv("REDIS_PASSWORD", "")

	// Restore original environment variables after test
	defer func() {
		os.Setenv("REDDIT_CLIENT_ID", originalRedditID)
		os.Setenv("REDDIT_CLIENT_SECRET", originalRedditSecret)
		os.Setenv("REDDIT_USERNAME", originalRedditUser)
		os.Setenv("REDDIT_PASSWORD", originalRedditPass)
		os.Setenv("REDIS_ADDR", originalRedisAddr)
		os.Setenv("REDIS_PASSWORD", originalRedisPass)
	}()

	// Reset seen posts cache
	seenPosts = make(map[string]*list.Element)
	seenList = list.New()

	// Create mock Redis client
	mockRedis := new(MockRedisStreamer)
	mockRedis.On("XAdd", mock.Anything, mock.Anything).Return("message-id", nil)

	// Create timestamp for test posts
	now := time.Now()
	redditTimestamp := reddit.Timestamp{Time: now}

	// Create sample Reddit posts
	samplePosts := []*reddit.Post{
		{
			ID:            "post1",
			Title:         "Test Post 1",
			Body:          "This is test post 1",
			URL:           "https://reddit.com/r/test/1",
			Author:        "user1",
			SubredditName: "wallstreetbets",
			Created:       &redditTimestamp,
		},
		{
			ID:            "post2",
			Title:         "Test Post 2",
			Body:          "This is test post 2",
			URL:           "https://reddit.com/r/test/2",
			Author:        "user2",
			SubredditName: "wallstreetbets",
			Created:       &redditTimestamp,
		},
	}

	// Mock the Reddit service manually (simulation of main loop)
	for _, redditPost := range samplePosts {
		// Convert to our internal post type
		post := RedditPost{
			ID:        redditPost.ID,
			Title:     redditPost.Title,
			Body:      redditPost.Body,
			URL:       redditPost.URL,
			Author:    redditPost.Author,
			Subreddit: redditPost.SubredditName,
			Created:   redditPost.Created.Time,
		}
		
		// Process the post
		err := processPost(mockRedis, post)
		assert.NoError(t, err)
	}

	// Verify Redis was called
	mockRedis.AssertNumberOfCalls(t, "XAdd", 2)

	// Verify posts are marked as seen
	assert.True(t, hasSeen("post1"))
	assert.True(t, hasSeen("post2"))

	// Verify post1 and post2 are in the cache
	assert.Equal(t, 2, seenList.Len())
}