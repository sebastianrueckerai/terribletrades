import { useState, useEffect } from "react";
import { useCentrifugo } from "./hooks/useCentrifugo";
import TradeSignalList from "./components/TradeSignalList";
import { CentrifugoConfig } from "./types";

// Declare window.CONFIG interface
declare global {
  interface Window {
    CONFIG?: {
      centrifugoUrl: string;
      centrifugoToken: string;
      centrifugoChannel: string;
    };
  }
}

function App() {
  // Generate a unique session ID to prevent cache issues
  const [sessionId] = useState<string>(`session-${Date.now()}`);

  // Get config from window.CONFIG (production) or fallback to env vars (dev)
  const [config, setConfig] = useState<CentrifugoConfig>({
    websocketEndpoint:
      window.CONFIG?.centrifugoUrl ||
      import.meta.env.VITE_CENTRIFUGO_ENDPOINT ||
      "ws://localhost:8000/connection/websocket",
    token:
      window.CONFIG?.centrifugoToken ||
      import.meta.env.VITE_CENTRIFUGO_TOKEN ||
      "",
    channel:
      window.CONFIG?.centrifugoChannel ||
      import.meta.env.VITE_CENTRIFUGO_CHANNEL ||
      "trading:trade-signals",
  });

  // Log current config for debugging
  useEffect(() => {
    console.log("Current Centrifugo config:", {
      websocketEndpoint: config.websocketEndpoint,
      token: config.token?.substring(0, 5) + "...", // Show only first 5 chars for security
      channel: config.channel,
      sessionId: sessionId,
    });
  }, [config, sessionId]);

  // For development, allow overriding the config via localStorage
  useEffect(() => {
    const storedConfig = localStorage.getItem("centrifugoConfig");
    if (storedConfig) {
      try {
        setConfig(JSON.parse(storedConfig));
      } catch (e) {
        console.error("Failed to parse stored config", e);
      }
    }
  }, []);

  // Add cache busting parameter to the websocket endpoint
  const effectiveConfig = {
    ...config,
    websocketEndpoint: `${config.websocketEndpoint}${
      config.websocketEndpoint.includes("?") ? "&" : "?"
    }cache=${sessionId}`,
  };

  // Use our custom hook to connect to Centrifugo
  const { signals, isConnected, error, reconnect } =
    useCentrifugo(effectiveConfig);

  // Simple form to update connection settings during development
  const handleConfigUpdate = (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    const formData = new FormData(e.currentTarget);

    // Clean the endpoint of any existing cache params
    let endpoint = (formData.get("websocketEndpoint") as string).split("?")[0];

    const newConfig = {
      websocketEndpoint: endpoint,
      token: formData.get("token") as string,
      channel: formData.get("channel") as string,
    };

    localStorage.setItem("centrifugoConfig", JSON.stringify(newConfig));
    setConfig(newConfig);

    // Force refresh connection after a short delay
    setTimeout(() => {
      reconnect();
    }, 100);
  };

  // Function to force reconnection
  const handleForceReconnect = () => {
    console.log("Force reconnection requested");
    // Generate a new session ID to ensure a fresh connection
    const newSessionId = `session-${Date.now()}`;
    (window as any)._sessionId = newSessionId; // Store for debugging

    // Clear any problematic local storage
    localStorage.removeItem("centrifugo_last_id");

    reconnect();
  };

  return (
    <div>
      <h1>Signals, Sort Of</h1>

      {/* Development-only config form */}
      <details>
        <summary>Connection Settings (Development Only)</summary>
        <form onSubmit={handleConfigUpdate}>
          <div>
            <label htmlFor="websocketEndpoint">Centrifugo Endpoint:</label>
            <input
              type="text"
              id="websocketEndpoint"
              name="websocketEndpoint"
              defaultValue={config.websocketEndpoint.split("?")[0]} // Remove any query params
            />
          </div>
          <div>
            <label htmlFor="token">Authentication Token:</label>
            <input
              type="text"
              id="token"
              name="token"
              defaultValue={config.token}
            />
          </div>
          <div>
            <label htmlFor="channel">Channel:</label>
            <input
              type="text"
              id="channel"
              name="channel"
              defaultValue={config.channel}
            />
          </div>
          <div>
            <button type="submit">Update Connection</button>
            <button type="button" onClick={handleForceReconnect}>
              Force Reconnect
            </button>
          </div>
        </form>
      </details>

      <TradeSignalList
        signals={signals}
        isConnected={isConnected}
        error={error}
        onReconnect={handleForceReconnect}
      />
    </div>
  );
}

export default App;
