#!/usr/bin/env python3
import os
import time
import signal
import logging
import asyncio
import aiohttp
from typing import Dict, Tuple, Any
from dataclasses import dataclass
from contextlib import asynccontextmanager
from datetime import datetime

import redis.asyncio as redis
from groq import AsyncGroq

import health_check
from health_check import app_state

NO_SIGNAL = 0
BUY = 1
SELL = 2

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)


@dataclass
class Config:
    """Configuration for the strategy worker."""

    groq_model_name: str
    redis_addr: str
    redis_password: str
    stream_name: str
    group_name: str
    consumer_name: str
    signal_stream: str
    prompt_file: str
    groq_api_key: str
    # Centrifugo configuration
    centrifugo_api_url: str
    centrifugo_api_key: str
    centrifugo_channel: str


def load_config() -> Config:
    """Load configuration from environment variables."""
    config = Config(
        groq_model_name=os.getenv("GROQ_MODEL_NAME", ""),
        redis_addr=os.getenv("REDIS_ADDR", ""),
        redis_password=os.getenv("REDIS_PASSWORD", ""),
        stream_name=os.getenv("STREAM", ""),
        group_name=os.getenv("GROUP", ""),
        consumer_name=os.getenv("CONSUMER", ""),
        signal_stream=os.getenv("SIGNAL_STREAM", ""),
        prompt_file=os.getenv("PROMPT_FILE", ""),
        groq_api_key=os.getenv("GROQ_API_KEY", ""),
        # Centrifugo configuration
        centrifugo_api_url=os.getenv("CENTRIFUGO_API_URL", ""),
        centrifugo_api_key=os.getenv("CENTRIFUGO_API_KEY", ""),
        centrifugo_channel=os.getenv("CENTRIFUGO_CHANNEL", ""),
    )

    # Validate required variables
    missing_vars = []
    if not config.groq_model_name:
        missing_vars.append("GROQ_MODEL_NAME")
    if not config.groq_api_key:
        missing_vars.append("GROQ_API_KEY")
    if not config.stream_name:
        missing_vars.append("STREAM")
    if not config.group_name:
        missing_vars.append("GROUP")
    if not config.consumer_name:
        missing_vars.append("CONSUMER")
    if not config.signal_stream:
        missing_vars.append("SIGNAL_STREAM")
    if not config.prompt_file:
        missing_vars.append("PROMPT_FILE")

    # Centrifugo is optional but needs both URL and API key if used
    if config.centrifugo_api_url and not config.centrifugo_api_key:
        missing_vars.append("CENTRIFUGO_API_KEY")
    elif config.centrifugo_api_key and not config.centrifugo_api_url:
        missing_vars.append("CENTRIFUGO_API_URL")

    if missing_vars:
        raise ValueError(
            f"Missing required environment variables: {', '.join(missing_vars)}"
        )

    return config


@asynccontextmanager
async def setup_redis(config: Config):
    """Set up Redis client with proper connection handling."""
    redis_client = redis.Redis(
        host=config.redis_addr.split(":")[0]
        if ":" in config.redis_addr
        else config.redis_addr,
        port=int(config.redis_addr.split(":")[1]) if ":" in config.redis_addr else 6379,
        password=config.redis_password,
        decode_responses=True,
    )

    try:
        await redis_client.ping()
        app_state.set_redis_connection_state(True)
        yield redis_client
    except Exception as e:
        logger.error(f"Redis connection error: {e}")
        app_state.set_redis_connection_state(False)
        app_state.record_error(f"Redis connection error: {str(e)}")
        raise
    finally:
        await redis_client.close()


@asynccontextmanager
async def setup_groq(config: Config):
    """Set up Groq client."""
    groq_client = AsyncGroq(api_key=config.groq_api_key)

    # Store the model name on the client for the ping function
    groq_client.model_name = config.groq_model_name

    # Initialize Groq status as disconnected until first successful call
    app_state.set_groq_connection_state(False)

    yield groq_client


@asynccontextmanager
async def setup_http_client():
    """Set up HTTP client for API calls."""
    async with aiohttp.ClientSession() as session:
        yield session


async def check_centrifugo_health(
    http_client: aiohttp.ClientSession, config: Config
) -> bool:
    """Check if Centrifugo is available by making a simple info request.

    Returns:
        bool: True if Centrifugo is available, False otherwise.
    """
    if not config.centrifugo_api_url or not config.centrifugo_api_key:
        # If not configured, return True (considered "healthy" as it's optional)
        return True

    try:
        headers = {
            "Content-Type": "application/json",
            "X-API-Key": config.centrifugo_api_key,  # Changed from Authorization header
        }

        data = {"method": "info", "params": {}}

        async with http_client.post(
            config.centrifugo_api_url,
            headers=headers,
            json=data,
            timeout=3.0,  # Short timeout for health check
        ) as response:
            if response.status != 200:
                logger.warning(
                    f"Centrifugo health check failed with status {response.status}"
                )
                return False

            result = await response.json()
            if "result" in result and not result.get("error"):
                logger.debug("Centrifugo health check successful")
                return True
            else:
                logger.warning(
                    f"Centrifugo returned error: {result.get('error', 'Unknown error')}"
                )
                return False
    except Exception as e:
        logger.warning(f"Centrifugo health check failed: {e}")
        return False


async def ping_groq(groq_client: AsyncGroq) -> bool:
    """
    Test Groq API connectivity with a minimal API call.
    Returns True if successful, False otherwise.
    """
    try:
        # Small, fast request to check connectivity
        _ = await groq_client.chat.completions.create(
            model=groq_client.model_name
            if hasattr(groq_client, "model_name")
            else "llama-3.1-8b-instant",
            messages=[{"role": "user", "content": "Hello"}],
            max_tokens=1,  # Only need a minimal response to verify connectivity
        )

        # If we got here, the connection was successful
        app_state.set_groq_connection_state(True)
        logger.info("Groq connectivity test successful")
        return True
    except Exception as e:
        logger.warning(f"Groq connectivity test failed: {e}")
        app_state.set_groq_connection_state(False)
        app_state.record_error(f"Groq connectivity test failed: {str(e)}")
        return False


async def publish_to_centrifugo(
    http_client: aiohttp.ClientSession, config: Config, message: Dict[str, Any]
) -> bool:
    """Publish a message to Centrifugo.

    Returns:
        bool: True if successful, False otherwise.
    """
    if not config.centrifugo_api_url or not config.centrifugo_api_key:
        logger.debug("Centrifugo not configured, skipping publish")
        return False

    try:
        # Prepare the publish request for Centrifugo
        headers = {
            "Content-Type": "application/json",
            "X-API-Key": config.centrifugo_api_key,  # Changed from Authorization header
        }

        data = {
            "method": "publish",
            "params": {"channel": config.centrifugo_channel, "data": message},
        }

        async with http_client.post(
            config.centrifugo_api_url, headers=headers, json=data, timeout=5.0
        ) as response:
            if response.status != 200:
                error_text = await response.text()
                logger.error(
                    f"Failed to publish to Centrifugo: HTTP {response.status}, {error_text}"
                )
                app_state.set_centrifugo_connection_state(False)
                return False

            result = await response.json()
            if result.get("error"):
                logger.error(f"Centrifugo error: {result.get('error')}")
                app_state.set_centrifugo_connection_state(False)
                return False

            # Successfully published
            app_state.set_centrifugo_connection_state(True)
            return True
    except Exception as e:
        logger.error(f"Error publishing to Centrifugo: {e}")
        app_state.set_centrifugo_connection_state(False)
        return False


async def ensure_group(redis_client: redis.Redis, stream: str, group: str) -> None:
    """Ensure the consumer group exists, creating it if needed."""
    try:
        await redis_client.xgroup_create(stream, group, id="$", mkstream=True)
        logger.info(f"Consumer group '{group}' created")
    except redis.ResponseError as e:
        if "BUSYGROUP" in str(e):
            logger.info(f"Consumer group '{group}' already exists")
        else:
            if "no such key" in str(e).lower():
                await redis_client.xadd(stream, {"init": "init"})
                await redis_client.xgroup_create(stream, group, id="$")
                logger.info(f"Consumer group '{group}' created with new stream")
            else:
                raise


def extract_decision(response: str) -> Tuple[int, str, str, str]:
    """Extract decision from the LLM response.

    Args:
        response: The text response from the LLM in the format:
                 <analysis>---<ticker>---<decision code>

    Returns:
        A tuple of (decision_code, signal_name, ticker, analysis)
    """
    if not response:
        return NO_SIGNAL, "no_signal", "NONE", ""

    # Try to split the response into parts
    try:
        parts = response.split("---")
        if len(parts) != 3:
            logger.warning(f"Malformed LLM response, expected 3 parts: {response}")
            return NO_SIGNAL, "no_signal", "NONE", response

        analysis, ticker, decision_code = parts

        # Clean up ticker
        ticker = ticker.strip().upper()
        if not ticker or ticker.lower() == "none":
            ticker = "NONE"

        # Parse decision code
        try:
            code = decision_code.strip()[
                -1
            ]  # Get the last character in case there's text
            if code == "1":
                return BUY, "buy", ticker, analysis.strip()
            elif code == "2":
                return SELL, "sell", ticker, analysis.strip()
            else:
                return NO_SIGNAL, "no_signal", ticker, analysis.strip()
        except IndexError:
            logger.warning(f"Empty decision code: {decision_code}")
            return NO_SIGNAL, "no_signal", ticker, analysis.strip()

    except Exception as e:
        logger.error(f"Error parsing LLM response: {e}, response: {response}")
        return NO_SIGNAL, "no_signal", "NONE", response


def get_string_field(values: Dict[str, Any], field: str) -> str:
    """Safely extract a string field from Redis message values."""
    value = values.get(field, "")
    return str(value) if value is not None else ""


async def process_entry(
    redis_client: redis.Redis,
    groq_client: AsyncGroq,
    http_client: aiohttp.ClientSession,
    groq_model_name: str,
    message: Dict[str, Any],
    prompt_template: str,
    stream: str,
    group: str,
    signal_stream: str,
    config: Config,
) -> None:
    """Process a single message from the stream."""
    start_time = time.time()

    try:
        # Extract post data from the message
        message_id = message["id"]
        values = message["data"]
        title = get_string_field(values, "title")
        url = get_string_field(values, "url")
        body = get_string_field(values, "body")
        author = get_string_field(values, "author")
        subreddit = get_string_field(values, "subreddit")
        created = get_string_field(values, "created")

        logger.info(f"Processing: {title} (ID: {message_id})")

        # Create prompt with the post data
        prompt = f"{prompt_template}\n\n---Post---\n{title}\n\n{body}"

        # Call Groq API
        try:
            completion = await groq_client.chat.completions.create(
                model=groq_model_name,
                messages=[{"role": "user", "content": prompt}],
                temperature=0.7,
                max_tokens=512,
                top_p=1.0,
            )

            response = completion.choices[0].message.content
            if not response:
                logger.error("Empty response from Groq")
                app_state.record_error("Empty response from Groq")
                await redis_client.xack(stream, group, message_id)
                return

            # Record successful Groq connection
            app_state.set_groq_connection_state(True)

        except Exception as e:
            logger.error(f"Groq API error: {e}")
            app_state.record_error(f"Groq API error: {str(e)}")
            app_state.set_groq_connection_state(False)
            await redis_client.xack(stream, group, message_id)
            return

        decision, signal_type, ticker, analysis = extract_decision(response)

        logger.info(
            f'Post: "{title}" → LLM: {signal_type.upper()} on {ticker} (took {time.time() - start_time:.2f}s)'
        )

        # If decision is Buy or Sell, add to signal stream
        if decision != NO_SIGNAL:
            # Build the signal data with original post nested
            signal_data = {
                "decision": signal_type,
                "ticker": ticker,
                "analysis": analysis,
                "src": message_id,
                "time": datetime.now().isoformat(),
                # Include all original post fields
                "post_title": title,
                "post_body": body,
                "post_url": url,
                "post_author": author,
                "post_subreddit": subreddit,
                "post_created": created,
            }

            # Add to Redis stream
            try:
                await redis_client.xadd(
                    signal_stream,
                    signal_data,
                )
                logger.info(
                    f"Signal pushed to Redis: {signal_type.upper()} on {ticker}"
                )
            except Exception as e:
                logger.error(f"Failed to add signal to Redis stream: {e}")
                app_state.record_error(
                    f"Failed to add signal to Redis stream: {str(e)}"
                )

            # Publish to Centrifugo for real-time updates if configured
            if config.centrifugo_api_url and config.centrifugo_api_key:
                success = await publish_to_centrifugo(http_client, config, signal_data)
                if success:
                    logger.info(
                        f"Signal published to Centrifugo: {signal_type.upper()} on {ticker}"
                    )
                else:
                    logger.error(
                        f"Failed to publish signal to Centrifugo: {signal_type.upper()} on {ticker}"
                    )
                    app_state.record_error(
                        f"Failed to publish to Centrifugo: {signal_type.upper()} on {ticker}"
                    )

        # Record successful message processing
        app_state.record_message_processed()

        # Acknowledge message
        try:
            await redis_client.xack(stream, group, message_id)
        except Exception as e:
            logger.error(f"Failed to acknowledge message: {e}")
            app_state.record_error(f"Failed to acknowledge message: {str(e)}")

    except Exception as e:
        logger.error(f"Error processing message: {e}")
        app_state.record_error(f"Error processing message: {str(e)}")


async def process_messages(
    redis_client: redis.Redis,
    groq_client: AsyncGroq,
    http_client: aiohttp.ClientSession,
    prompt_template: str,
    config: Config,
) -> None:
    """Process messages from the Redis stream continuously."""
    # Use exponential backoff for retries
    backoff = 1.0
    max_backoff = 30.0

    # For Centrifugo health checks
    last_centrifugo_check = 0
    centrifugo_check_interval = 30  # Check every 30 seconds

    # Record that we've started processing
    app_state.set_redis_connection_state(True)

    while True:
        try:
            # Periodically check Centrifugo health if configured
            current_time = time.time()
            if (
                config.centrifugo_api_url
                and config.centrifugo_api_key
                and (current_time - last_centrifugo_check > centrifugo_check_interval)
            ):
                centrifugo_healthy = await check_centrifugo_health(http_client, config)
                app_state.set_centrifugo_connection_state(centrifugo_healthy)
                last_centrifugo_check = current_time

                if centrifugo_healthy:
                    logger.debug("Centrifugo health check passed")
                else:
                    logger.warning("Centrifugo health check failed")

            # Read from stream with consumer group
            streams = {config.stream_name: ">"}
            result = await redis_client.xreadgroup(
                groupname=config.group_name,
                consumername=config.consumer_name,
                streams=streams,
                count=1,
                block=5000,  # 5 seconds
            )

            # Reset backoff on success
            backoff = 1.0

            # Update Redis connection status
            app_state.set_redis_connection_state(True)

            if not result:
                continue

            # Process each message
            for stream_name, messages in result:
                for message in messages:
                    await process_entry(
                        redis_client,
                        groq_client,
                        http_client,
                        config.groq_model_name,
                        {"id": message[0], "data": message[1]},
                        prompt_template,
                        config.stream_name,
                        config.group_name,
                        config.signal_stream,
                        config,
                    )

        except asyncio.CancelledError:
            # Handle graceful shutdown
            logger.info("Shutting down...")
            break

        except Exception as e:
            # Record the error
            error_msg = f"Error reading from stream: {e}"
            logger.error(f"{error_msg}, retrying in {backoff}s")
            app_state.record_error(error_msg)
            app_state.set_redis_connection_state(False)

            await asyncio.sleep(backoff)

            # Exponential backoff
            backoff = min(backoff * 2, max_backoff)


async def main() -> None:
    """Main entry point for the strategy worker."""
    config = load_config()

    # Start health check server on port 8080
    health_port = int(os.getenv("HEALTH_PORT", "8080"))
    health_server = health_check.start_health_server(port=health_port)

    if health_server:
        logger.info(f"Health check server started on port {health_port}")
    else:
        logger.warning(f"Failed to start health check server on port {health_port}")

    try:
        with open(config.prompt_file, "r") as f:
            prompt_template = f.read()
    except Exception as e:
        logger.error(f"Failed to read prompt file: {e}")
        app_state.record_error(f"Failed to read prompt file: {str(e)}")
        return

    try:
        async with (
            setup_redis(config) as redis_client,
            setup_groq(config) as groq_client,
            setup_http_client() as http_client,
        ):
            await ensure_group(redis_client, config.stream_name, config.group_name)

            logger.info(
                f"Starting strategy worker: stream={config.stream_name}, group={config.group_name}, consumer={config.consumer_name}"
            )

            # Add this: Test Groq connectivity during startup
            logger.info("Testing Groq API connectivity...")
            await ping_groq(groq_client)

            # Log Centrifugo status
            if config.centrifugo_api_url and config.centrifugo_api_key:
                # Perform initial Centrifugo health check
                centrifugo_healthy = await check_centrifugo_health(http_client, config)
                app_state.set_centrifugo_connection_state(centrifugo_healthy)

                status = "healthy" if centrifugo_healthy else "unhealthy"
                logger.info(
                    f"Centrifugo integration enabled: channel={config.centrifugo_channel}, status={status}"
                )
            else:
                logger.info("Centrifugo integration disabled")
                # Still mark as connected since it's optional
                app_state.set_centrifugo_connection_state(True)

            loop = asyncio.get_running_loop()
            stop_event = asyncio.Event()

            def handle_signal(sig: int, _: Any):
                logger.info(f"Received signal {sig}, shutting down...")
                stop_event.set()

            for sig in (signal.SIGINT, signal.SIGTERM):
                loop.add_signal_handler(sig, lambda s=sig: handle_signal(s))

            process_task = asyncio.create_task(
                process_messages(
                    redis_client, groq_client, http_client, prompt_template, config
                )
            )

            await stop_event.wait()

            process_task.cancel()

            try:
                await process_task
            except asyncio.CancelledError:
                pass

            logger.info("Shutdown complete")
    except Exception as e:
        logger.error(f"Application error: {e}")
        app_state.record_error(f"Application error: {str(e)}")


if __name__ == "__main__":
    asyncio.run(main())
