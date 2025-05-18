package main

import (
	"context"
	"log"
	"time"
)

// RedisStreamer is an interface for Redis stream operations
// This allows us to mock Redis for testing
type RedisStreamer interface {
	XAdd(ctx context.Context, args *XAddArgs) (string, error)
}

// XAddArgs holds the arguments for the XAdd operation
type XAddArgs struct {
	Stream string
	Values map[string]interface{}
}

// processPost processes a single Reddit post and adds it to Redis if it's new
func processPost(streamer RedisStreamer, post RedditPost) error {
	if hasSeen(post.ID) {
		return nil // Already processed
	}

	log.Printf("New unseen post: %s", post.Title)
	rememberPost(post.ID)

	// Add to Redis stream
	_, err := streamer.XAdd(ctx, &XAddArgs{
		Stream: "reddit-events",
		Values: map[string]interface{}{
			"id":        post.ID,
			"title":     post.Title,
			"body":      post.Body,
			"url":       post.URL,
			"author":    post.Author,
			"subreddit": post.Subreddit,
			"created":   post.Created.Format(time.RFC3339),
		},
	})

	if err != nil {
		log.Printf("Redis push failed: %v", err)
		return err
	}

	log.Printf("Post pushed to Redis.")
	return nil
}

// RedditPost represents a Reddit post
type RedditPost struct {
	ID        string
	Title     string
	Body      string
	URL       string
	Author    string
	Subreddit string
	Created   time.Time
}