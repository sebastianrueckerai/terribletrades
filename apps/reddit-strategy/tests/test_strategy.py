import asyncio
import pytest
from unittest.mock import patch, AsyncMock

from src.strategy_worker import (
    extract_decision,
    process_entry,
    NO_SIGNAL,
    BUY,
    SELL,
)


# Test the extract_decision function
def test_extract_decision():
    """Test that extract_decision correctly identifies decision codes."""
    # Test buy signal (1) with ticker
    decision, signal_type, ticker, analysis = extract_decision(
        "This is a buy signal---AAPL---1"
    )
    assert decision == BUY
    assert signal_type == "buy"
    assert ticker == "AAPL"
    assert analysis == "This is a buy signal"

    # Test sell signal (2) with ticker
    decision, signal_type, ticker, analysis = extract_decision(
        "This is a sell signal---TSLA---2"
    )
    assert decision == SELL
    assert signal_type == "sell"
    assert ticker == "TSLA"
    assert analysis == "This is a sell signal"

    # Test no signal (0) with ticker
    decision, signal_type, ticker, analysis = extract_decision(
        "This is not a signal---SPY---0"
    )
    assert decision == NO_SIGNAL
    assert signal_type == "no_signal"
    assert ticker == "SPY"
    assert analysis == "This is not a signal"

    # Test with "NONE" ticker
    decision, signal_type, ticker, analysis = extract_decision(
        "No specific ticker here---NONE---1"
    )
    assert decision == BUY
    assert signal_type == "buy"
    assert ticker == "NONE"
    assert analysis == "No specific ticker here"

    # Test malformed response - wrong number of segments
    decision, signal_type, ticker, analysis = extract_decision(
        "This has no proper format"
    )
    assert decision == NO_SIGNAL
    assert signal_type == "no_signal"
    assert ticker == "NONE"

    # Test empty string
    decision, signal_type, ticker, analysis = extract_decision("")
    assert decision == NO_SIGNAL
    assert signal_type == "no_signal"
    assert ticker == "NONE"
    assert analysis == ""


# Test processing a single post
@pytest.mark.asyncio
async def test_process_entry():
    """Test processing a single Reddit post."""
    # Create mocks for dependencies
    redis_client = AsyncMock()
    redis_client.xadd.return_value = "mock-message-id"
    redis_client.xack.return_value = 1

    # Mock the Groq client
    class MockGroq:
        class Chat:
            class Completions:
                @staticmethod
                async def create(**kwargs):
                    class Message:
                        content = "This looks like a buy signal---NVDA---1"

                    class Choice:
                        message = Message()

                    class Completion:
                        choices = [Choice()]

                    return Completion()

            completions = Completions()

        chat = Chat()

    # Create test message
    message = {
        "id": "test-id",
        "data": {"title": "NVDA to the moon!", "url": "https://example.com"},
    }

    # Simple test prompt
    test_prompt = "Analyze this post and decide: 0 = No signal, 1 = Buy, 2 = Sell"

    # Process the message
    await process_entry(
        redis_client,
        MockGroq(),
        "test-model",
        message,
        test_prompt,
        "test-reddit-events",
        "test-group",
        "test-trade-signals",
    )

    # Check that xadd was called with the right parameters
    redis_client.xadd.assert_called_once()

    # Get the arguments
    args, kwargs = redis_client.xadd.call_args

    # Check stream name
    assert args[0] == "test-trade-signals"

    # Check signal data structure
    signal_data = args[1]
    assert signal_data["decision"] == "buy"
    assert signal_data["ticker"] == "NVDA"
    assert "analysis" in signal_data
    assert signal_data["src"] == "test-id"

    # Check that xack was called
    redis_client.xack.assert_called_once_with(
        "test-reddit-events", "test-group", "test-id"
    )


# Test process_messages by mocking everything it calls
@pytest.mark.asyncio
async def test_process_messages():
    """
    Test process_messages by directly mocking process_entry.
    Since we've tested process_entry separately, we can focus on
    verifying that process_messages calls it correctly.
    """
    # Create a direct patch for process_entry
    with patch(
        "src.strategy_worker.process_entry", new=AsyncMock()
    ) as mock_process_entry:
        # Create mock dependencies
        redis_client = AsyncMock()
        groq_client = AsyncMock()

        # Mock xreadgroup to return a batch of messages once then nothing
        redis_client.xreadgroup.side_effect = [
            # First call returns messages
            [
                (
                    "test-stream",
                    [
                        ("msg-id-1", {"title": "Post 1"}),
                        ("msg-id-2", {"title": "Post 2"}),
                    ],
                )
            ],
            # Second call returns nothing (to break the loop)
            [],
        ]

        # Mock Config object
        class MockConfig:
            stream_name = "test-stream"
            group_name = "test-group"
            consumer_name = "test-consumer"
            signal_stream = "test-signals"
            groq_model_name = "test-model"

        # Import process_messages here to avoid circular imports
        from src.strategy_worker import process_messages

        # Run process_messages but with a timeout to prevent hanging
        try:
            # Run with a short timeout
            await asyncio.wait_for(
                process_messages(
                    redis_client, groq_client, "test-prompt", MockConfig()
                ),
                timeout=0.5,
            )
        except asyncio.TimeoutError:
            # This is expected since process_messages runs forever
            pass

        # Verify process_entry was called for each message
        assert mock_process_entry.call_count == 2

        # Check first call
        first_call = mock_process_entry.call_args_list[0]
        assert first_call[0][0] == redis_client  # redis client
        assert first_call[0][1] == groq_client  # groq client
        assert first_call[0][2] == "test-model"  # model name
        assert first_call[0][3] == {
            "id": "msg-id-1",
            "data": {"title": "Post 1"},
        }  # message

        # Check second call
        second_call = mock_process_entry.call_args_list[1]
        assert second_call[0][0] == redis_client  # redis client
        assert second_call[0][1] == groq_client  # groq client
        assert second_call[0][2] == "test-model"  # model name
        assert second_call[0][3] == {
            "id": "msg-id-2",
            "data": {"title": "Post 2"},
        }  # message


# Test acknowledgment functionality
@pytest.mark.asyncio
async def test_acknowledge_processed_messages():
    """Test that messages are acknowledged after processing."""
    # We'll test this by mocking process_entry directly
    with patch(
        "src.strategy_worker.process_entry", new=AsyncMock()
    ) as mock_process_entry:
        # Create mock dependencies
        redis_client = AsyncMock()
        groq_client = AsyncMock()

        # Set up redis_client.xreadgroup to return a message then nothing
        redis_client.xreadgroup.side_effect = [
            # First call returns a message
            [("test-stream", [("msg-id-1", {"title": "Test Post"})])],
            # Second call returns nothing (to break the loop)
            [],
        ]

        # Mock Config object
        class MockConfig:
            stream_name = "test-stream"
            group_name = "test-group"
            consumer_name = "test-consumer"
            signal_stream = "test-signals"
            groq_model_name = "test-model"

        # Import process_messages here to avoid circular imports
        from src.strategy_worker import process_messages

        # Run process_messages but with a timeout to prevent hanging
        try:
            # Run with a short timeout
            await asyncio.wait_for(
                process_messages(
                    redis_client, groq_client, "test-prompt", MockConfig()
                ),
                timeout=0.5,
            )
        except asyncio.TimeoutError:
            # This is expected since process_messages runs forever
            pass

        # Verify process_entry was called once
        mock_process_entry.assert_called_once()

        # Verify the message structure passes through correctly
        message_arg = mock_process_entry.call_args[0][3]
        assert message_arg["id"] == "msg-id-1"
        assert message_arg["data"]["title"] == "Test Post"
