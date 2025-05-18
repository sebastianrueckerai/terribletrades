package main

import (
	"container/list"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/vartanbeno/go-reddit/v2/reddit"
)

// TestIntegrationWithMocks tests an integration scenario with mocked dependencies
func TestIntegrationWithMocks(t *testing.T) {
	// Skip in short mode
	if testing.Short() {
		t.Skip("Skipping test in short mode.")
	}

	// Reset cache
	seenPosts = make(map[string]*list.Element)
	seenList = list.New()
	
	// Create mock Redis client
	mockRedis := new(MockRedisStreamer)
	mockRedis.On("XAdd", mock.Anything, mock.Anything).Return("message-id", nil)
	
	// Create a timestamp for our test posts
	now := time.Now()
	redditTimestamp := reddit.Timestamp{Time: now}
	
	// Create sample Reddit posts
	posts := []*reddit.Post{
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
	
	// Process each post as the main loop would
	for _, redditPost := range posts {
		// Convert to our internal post type
		post := RedditPost{
			ID:        redditPost.ID,
			Title:     redditPost.Title,
			Body:      redditPost.Body,
			URL:       redditPost.URL,
			Author:    redditPost.Author,
			Subreddit: redditPost.SubredditName,
			Created:   redditPost.Created.Time, // Use the Time field from the Timestamp
		}
		
		// Process the post
		err := processPost(mockRedis, post)
		assert.NoError(t, err)
	}
	
	// Verify Redis was called for each post
	mockRedis.AssertNumberOfCalls(t, "XAdd", 2)
	
	// Verify the correct data was sent (checking first call)
	mockRedis.AssertCalled(t, "XAdd", mock.Anything, mock.MatchedBy(func(args *XAddArgs) bool {
		return args.Stream == "reddit-events" && 
			args.Values["id"] == "post1" &&
			args.Values["title"] == "Test Post 1"
	}))
	
	// Verify the posts were added to the cache
	assert.True(t, hasSeen("post1"))
	assert.True(t, hasSeen("post2"))
}