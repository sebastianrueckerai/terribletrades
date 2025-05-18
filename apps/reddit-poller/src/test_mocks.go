package main

import (
	"context"

	"github.com/stretchr/testify/mock"
	"github.com/vartanbeno/go-reddit/v2/reddit"
)

// MockRedisStreamer is a mock implementation of the RedisStreamer interface
type MockRedisStreamer struct {
	mock.Mock
}

// XAdd mocks the XAdd method
func (m *MockRedisStreamer) XAdd(ctx context.Context, args *XAddArgs) (string, error) {
	called := m.Called(ctx, args)
	return called.String(0), called.Error(1)
}

// MockRedditClient mocks the Reddit client
type MockRedditClient struct {
	mock.Mock
	Subreddit *MockSubreddit
}

// MockSubreddit mocks the Subreddit service
type MockSubreddit struct {
	mock.Mock
}

// NewPosts mocks the NewPosts method
func (m *MockSubreddit) NewPosts(ctx context.Context, subreddit string, opts *reddit.ListOptions) ([]*reddit.Post, *reddit.Response, error) {
	args := m.Called(ctx, subreddit, opts)
	return args.Get(0).([]*reddit.Post), args.Get(1).(*reddit.Response), args.Error(2)
}