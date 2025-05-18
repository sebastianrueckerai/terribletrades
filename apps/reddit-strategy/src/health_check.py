import threading
import http.server
import socketserver
import json
import time
import logging
import os
from datetime import datetime, timedelta
from typing import List, Optional, Dict, Any

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)

# Global server instance for cleanup
_http_server = None


class AppState:
    """Class to track application state for health reporting."""

    def __init__(self):
        self.redis_connected = False
        self.groq_connected = False
        self.centrifugo_connected = False  # New field for Centrifugo
        self.last_message_processed: Optional[datetime] = None
        self.message_count = 0
        self.errors: List[Dict[str, Any]] = []
        self.error_limit = 100  # Only keep the most recent errors
        self._lock = threading.RLock()  # Thread-safe updates
        self.server_started = False

    def set_redis_connection_state(self, connected: bool) -> None:
        """Update Redis connection state."""
        with self._lock:
            self.redis_connected = connected

    def set_groq_connection_state(self, connected: bool) -> None:
        """Update Groq connection state."""
        with self._lock:
            self.groq_connected = connected

    def set_centrifugo_connection_state(self, connected: bool) -> None:
        """Update Centrifugo connection state."""
        with self._lock:
            self.centrifugo_connected = connected

    def record_message_processed(self) -> None:
        """Record that a message was successfully processed."""
        with self._lock:
            self.last_message_processed = datetime.now()
            self.message_count += 1

    def record_error(self, error_message: str) -> None:
        """Record an error with timestamp."""
        with self._lock:
            self.errors.append(
                {"timestamp": datetime.now().isoformat(), "message": error_message}
            )
            # Keep only the most recent errors
            if len(self.errors) > self.error_limit:
                self.errors = self.errors[-self.error_limit :]

    def set_server_started(self, started: bool) -> None:
        """Mark the server as started."""
        with self._lock:
            self.server_started = started

    def is_server_started(self) -> bool:
        """Check if the server is started."""
        with self._lock:
            return self.server_started

    def is_alive(self) -> bool:
        """Check if the application is alive (server is running)."""
        # For liveness, we only check if the app is running
        # This will return True as long as the HTTP server responds
        return True

    def is_ready(self) -> bool:
        """Check if the application is ready to receive traffic."""
        with self._lock:
            # Check if Centrifugo is configured but not connected
            centrifugo_check = True  # By default assume it's OK

            # Only consider Centrifugo in readiness if it's supposed to be used
            centrifugo_enabled = os.environ.get(
                "CENTRIFUGO_API_URL"
            ) and os.environ.get("CENTRIFUGO_API_KEY")
            if centrifugo_enabled:
                centrifugo_check = self.centrifugo_connected

            # Service is ready if critical dependencies are connected
            # Required: Redis and Groq
            # Optional: Centrifugo (only if configured)
            return self.redis_connected and self.groq_connected and centrifugo_check


# Create a singleton instance
app_state = AppState()


class HealthCheckHandler(http.server.SimpleHTTPRequestHandler):
    """HTTP request handler for health checks."""

    def log_message(self, format, *args):
        # Only log errors
        if args[1].startswith("4") or args[1].startswith("5"):
            logger.warning(format % args)

    def do_GET(self):
        """Handle GET requests."""
        # Log all incoming requests for debugging
        logger.debug(f"Health request received: {self.path}")

        # Handle different endpoints
        if self.path == "/livez":
            self.handle_liveness_check()
        elif self.path == "/readyz":
            self.handle_readiness_check()
        else:  # Default /health route
            self.handle_health_check()

    def handle_liveness_check(self):
        """Handle /livez endpoint for liveness probes."""
        # Always return 200 if the server is responding
        self.send_response(200)
        self.send_header("Content-type", "application/json")
        self.end_headers()

        response = json.dumps({"status": "alive"})
        self.wfile.write(response.encode("utf-8"))

    def handle_readiness_check(self):
        """Handle /readyz endpoint for readiness probes."""
        # Check if the app is ready to receive traffic
        is_ready = app_state.is_ready()

        if is_ready:
            self.send_response(200)
        else:
            self.send_response(503)  # Service Unavailable

        self.send_header("Content-type", "application/json")
        self.end_headers()

        # Check if Centrifugo is configured
        centrifugo_enabled = os.environ.get("CENTRIFUGO_API_URL") and os.environ.get(
            "CENTRIFUGO_API_KEY"
        )

        response = {
            "status": "ready" if is_ready else "not_ready",
            "redis": app_state.redis_connected,
            "groq": app_state.groq_connected,
        }

        # Only include Centrifugo status if it's configured
        if centrifugo_enabled:
            response["centrifugo"] = app_state.centrifugo_connected

        self.wfile.write(json.dumps(response).encode("utf-8"))

    def handle_health_check(self):
        """Handle /health endpoint for full health status."""
        # Check for recent activity
        recent_threshold = datetime.now() - timedelta(minutes=5)
        recent_activity = (
            app_state.last_message_processed is not None
            and app_state.last_message_processed > recent_threshold
        )

        # Determine overall health status
        is_healthy = app_state.is_ready() and recent_activity

        if is_healthy:
            self.send_response(200)
        else:
            self.send_response(503)  # Service Unavailable

        self.send_header("Content-type", "application/json")
        self.end_headers()

        # Check if Centrifugo is configured
        centrifugo_enabled = os.environ.get("CENTRIFUGO_API_URL") and os.environ.get(
            "CENTRIFUGO_API_KEY"
        )

        # Build detailed response
        response = {
            "status": "healthy" if is_healthy else "unhealthy",
            "uptime": {
                "server_started": app_state.is_server_started(),
            },
            "connections": {
                "redis_connected": app_state.redis_connected,
                "groq_connected": app_state.groq_connected,
            },
            "activity": {
                "message_count": app_state.message_count,
                "last_processed": app_state.last_message_processed.isoformat()
                if app_state.last_message_processed
                else None,
                "recent_activity": recent_activity,
            },
            "errors": {
                "count": len(app_state.errors),
                "recent": app_state.errors[-5:] if app_state.errors else [],
            },
        }

        # Only include Centrifugo info if it's configured
        if centrifugo_enabled:
            response["connections"]["centrifugo_connected"] = (
                app_state.centrifugo_connected
            )
            response["connections"]["centrifugo_enabled"] = True
        else:
            response["connections"]["centrifugo_enabled"] = False

        self.wfile.write(json.dumps(response, indent=2).encode("utf-8"))


# Global server instance for tracking
_http_server = None


def start_health_server(port=8080):
    """Start the health check HTTP server in a separate thread."""
    global _http_server

    # If server is already running, just return it
    if _http_server is not None:
        logger.info(f"Health check server already running on port {port}")
        return _http_server

    logger.info(f"Starting health check server on port {port}...")

    try:
        # This is more robust - create a custom server class
        class ThreadedTCPServer(socketserver.ThreadingTCPServer):
            allow_reuse_address = True

        # Make sure to bind to 0.0.0.0 - very important for Kubernetes
        _http_server = ThreadedTCPServer(("0.0.0.0", port), HealthCheckHandler)

        # Start server in a separate thread
        server_thread = threading.Thread(target=_http_server.serve_forever)
        server_thread.daemon = True  # Thread will exit when main thread exits

        logger.info("Starting health check thread...")
        server_thread.start()

        # Mark the server as started for health tracking
        app_state.set_server_started(True)

        # Sleep briefly to ensure server starts
        time.sleep(1)
        logger.info("Health check server started successfully!")

        return _http_server
    except Exception as e:
        logger.error(f"Failed to start health check server: {e}", exc_info=True)
        app_state.record_error(f"Health server start failed: {str(e)}")
        # Don't raise an exception - let the app continue
        return None


# Ensure the health check server starts automatically when module is imported
# This is important for Kubernetes probes!
def _auto_start_server():
    try:
        port = int(os.environ.get("HEALTH_PORT", "8080"))
        logger.info(f"Auto-starting health check server on port {port}...")
        start_health_server(port=port)
    except Exception as e:
        logger.error(f"Failed to auto-start health server: {e}", exc_info=True)


# Run the auto-start function if this module is imported
_auto_start_server()
