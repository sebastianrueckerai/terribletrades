package main

import (
	"container/list"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
)

func TestProcessPost(t *testing.T) {
	// Reset the seen cache
	seenPosts = make(map[string]*list.Element)
	seenList = list.New()
	
	// Create a mock Redis streamer
	mockRedis := new(MockRedisStreamer)
	mockRedis.On("XAdd", mock.Anything, mock.Anything).Return("message-id", nil)
	
	// Create a test post
	testPost := RedditPost{
		ID:        "test1",
		Title:     "Test Post",
		Body:      "Test Body",
		URL:       "https://example.com",
		Author:    "testuser",
		Subreddit: "testsubreddit",
		Created:   time.Now(),
	}
	
	// Process the post
	err := processPost(mockRedis, testPost)
	
	// Verify no errors
	assert.NoError(t, err)
	
	// Verify the post was added to Redis
	mockRedis.AssertCalled(t, "XAdd", ctx, mock.MatchedBy(func(args *XAddArgs) bool {
		return args.Stream == "reddit-events" && 
			args.Values["id"] == testPost.ID &&
			args.Values["title"] == testPost.Title
	}))
	
	// Verify the post was marked as seen
	assert.True(t, hasSeen(testPost.ID))
	
	// Process the same post again
	mockRedis.On("XAdd", mock.Anything, mock.Anything).Return("message-id-2", nil)
	err = processPost(mockRedis, testPost)
	
	// Verify no errors
	assert.NoError(t, err)
	
	// Verify XAdd was NOT called a second time (post was already seen)
	mockRedis.AssertNumberOfCalls(t, "XAdd", 1)
}

// Test that the LRU cache functionality works correctly
func TestLRUCache(t *testing.T) {
	// Reset global variables before test
	seenPosts = make(map[string]*list.Element)
	seenList = list.New()
	
	// Test hasSeen for non-existent post
	assert.False(t, hasSeen("post1"))
	
	// Test rememberPost and hasSeen
	rememberPost("post1")
	assert.True(t, hasSeen("post1"))
	
	// Test that rememberPost moves existing items to front
	rememberPost("post2")
	rememberPost("post3")
	assert.Equal(t, "post3", seenList.Front().Value.(string))
	
	rememberPost("post1") // This should move post1 to the front
	assert.Equal(t, "post1", seenList.Front().Value.(string))
}

// TestLRUEviction tests the LRU eviction logic directly
func TestLRUEviction(t *testing.T) {
	// Since we can't modify seenLimit (it's a constant), we'll test the eviction
	// logic by adding more than seenLimit items and checking the result
	
	// Reset global variables before test
	seenPosts = make(map[string]*list.Element)
	seenList = list.New()
	
	// Add posts up to the limit
	for i := 0; i < seenLimit; i++ {
		rememberPost(string(rune('a' + i % 26)) + string(rune('0' + i / 26)))
	}
	
	// Verify we have exactly seenLimit items
	assert.Equal(t, seenLimit, seenList.Len())
	assert.Equal(t, seenLimit, len(seenPosts))
	
	// Remember one more post to trigger eviction
	rememberPost("extra_post")
	
	// We should still have exactly seenLimit items (one was evicted)
	assert.Equal(t, seenLimit, seenList.Len())
	assert.Equal(t, seenLimit, len(seenPosts))
	
	// The first post ("a0") should have been evicted
	assert.False(t, hasSeen("a0"))
	
	// The extra post should be at the front
	assert.Equal(t, "extra_post", seenList.Front().Value.(string))
}