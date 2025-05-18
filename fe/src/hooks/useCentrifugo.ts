import { useState, useEffect, useRef } from "react";
import { Centrifuge, PublicationContext, SubscribedContext } from "centrifuge";
import { TradeSignal, CentrifugoConfig } from "../types";
import { createCentrifugeClient } from "../utils/centrifugo";

export const useCentrifugo = (config: CentrifugoConfig) => {
  const [signals, setSignals] = useState<TradeSignal[]>([]);
  const [isConnected, setIsConnected] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [reconnectAttempts, setReconnectAttempts] = useState(0);
  const MAX_RECONNECT_ATTEMPTS = 5;

  // Reference to the Centrifuge client
  const centrifugeRef = useRef<Centrifuge | null>(null);
  const subscriptionRef = useRef<any>(null);
  const reconnectTimeoutRef = useRef<number | null>(null);

  // Generate a unique key for this connection
  const connectionKey = useRef<string>(
    `${config.websocketEndpoint}-${config.channel}-${Date.now()}`
  );

  // Clean function to properly disconnect and clean up
  const cleanupConnection = () => {
    console.log("Cleaning up Centrifugo connection...");

    // Clear any pending reconnection timeout
    if (reconnectTimeoutRef.current) {
      window.clearTimeout(reconnectTimeoutRef.current);
      reconnectTimeoutRef.current = null;
    }

    // Unsubscribe from the channel
    if (subscriptionRef.current) {
      try {
        subscriptionRef.current.unsubscribe();
        subscriptionRef.current.removeAllListeners();
        subscriptionRef.current = null;
      } catch (err) {
        console.error("Error unsubscribing:", err);
      }
    }

    // Disconnect from the server
    if (centrifugeRef.current) {
      try {
        centrifugeRef.current.disconnect();
        centrifugeRef.current.removeAllListeners();
        centrifugeRef.current = null;
      } catch (err) {
        console.error("Error disconnecting:", err);
      }
    }

    // Reset connection state
    setIsConnected(false);
    setReconnectAttempts(0);
  };

  // Function to establish a fresh connection
  const establishConnection = () => {
    // Clean up any existing connection first
    cleanupConnection();

    // Create a fresh connection key
    connectionKey.current = `${config.websocketEndpoint}-${
      config.channel
    }-${Date.now()}`;

    // Create a fresh Centrifuge client
    console.log("Creating new Centrifugo client with config:", {
      ...config,
      token: config.token.substring(0, 5) + "...", // Hide full token
    });

    const centrifuge = createCentrifugeClient(config);
    centrifugeRef.current = centrifuge;

    // Make sure the channel includes the namespace
    const channelName = config.channel.includes(":")
      ? config.channel
      : `trading:${config.channel}`;

    console.log("Setting up subscription to channel:", channelName);

    // Set up the subscription to the trade signals channel
    const subscription = centrifuge.newSubscription(channelName);
    subscriptionRef.current = subscription;

    // Handle new publications (trade signals)
    subscription.on("publication", (ctx: PublicationContext) => {
      try {
        console.log("Received signal:", ctx.data);
        const newSignal = ctx.data as TradeSignal;

        // Add the new signal to the beginning of our array
        setSignals((prev) => [newSignal, ...prev]);
      } catch (err) {
        console.error("Error processing incoming signal:", err);
      }
    });

    // Handle subscription error
    subscription.on("error", (ctx) => {
      console.error("Subscription error:", ctx);
      setError(`Subscription error: ${ctx.error}`);
    });

    // Handle successful subscription
    subscription.on("subscribed", (ctx: SubscribedContext) => {
      console.log("Subscribed to channel:", channelName);

      // If history is available in the subscription response, use it
      if (
        ctx.data &&
        ctx.data.publications &&
        ctx.data.publications.length > 0
      ) {
        console.log(
          `Received ${ctx.data.publications.length} historical signals from subscription`
        );
        const historySignals = ctx.data.publications.map(
          (pub: { data: TradeSignal }) => pub.data as TradeSignal
        );
        setSignals(historySignals);
      }
    });

    // Handle connection state changes
    centrifuge.on("connecting", () => {
      console.log("Connecting to Centrifugo...");
    });

    centrifuge.on("connected", async () => {
      console.log("Connected to Centrifugo server");
      setIsConnected(true);
      setError(null);
      setReconnectAttempts(0); // Reset reconnect attempts on successful connection

      // Fetch history
      try {
        console.log("Fetching history for channel:", channelName);
        const historyResult = await centrifuge.history(channelName, {
          limit: 100,
        });

        console.log("History result:", historyResult);

        if (
          historyResult.publications &&
          historyResult.publications.length > 0
        ) {
          console.log(
            `Received ${historyResult.publications.length} historical signals`
          );

          // Extract signals from publications and add them to state
          const historySignals = historyResult.publications.map(
            (pub) => pub.data as TradeSignal
          );
          setSignals(historySignals);
        } else {
          console.log("No history available for channel");
        }
      } catch (err) {
        console.error("Error fetching history:", err);
        setError(`Failed to fetch history: ${err}`);
      }
    });

    centrifuge.on("disconnected", (ctx) => {
      console.log("Disconnected from Centrifugo:", ctx);
      setIsConnected(false);

      // Implement exponential backoff for reconnection
      const shouldAttemptReconnect = reconnectAttempts < MAX_RECONNECT_ATTEMPTS;

      if (shouldAttemptReconnect) {
        const backoffTime = Math.min(
          1000 * Math.pow(2, reconnectAttempts),
          30000
        );
        console.log(
          `Will attempt to reconnect in ${backoffTime}ms (attempt ${
            reconnectAttempts + 1
          }/${MAX_RECONNECT_ATTEMPTS})...`
        );

        // Schedule reconnection attempt
        reconnectTimeoutRef.current = window.setTimeout(() => {
          setReconnectAttempts((prev) => prev + 1);

          if (centrifugeRef.current) {
            console.log("Attempting to reconnect...");
            try {
              centrifugeRef.current.connect();
            } catch (err) {
              console.error("Error during reconnect:", err);
              // If reconnect fails immediately, clean up and try fresh connection
              if (reconnectAttempts >= MAX_RECONNECT_ATTEMPTS - 1) {
                console.log(
                  "Max reconnect attempts reached, establishing fresh connection..."
                );
                establishConnection();
              }
            }
          } else {
            console.log(
              "Centrifuge client no longer exists, creating fresh connection..."
            );
            establishConnection();
          }
        }, backoffTime);
      } else {
        console.log(
          "Max reconnect attempts reached, manual reconnection required"
        );
        setError(
          "Connection lost. Max reconnect attempts reached. Please try reconnecting."
        );
      }
    });

    centrifuge.on("error", (ctx) => {
      console.error("Centrifugo error:", ctx);
      setError(`Connection error: ${ctx.error}`);
    });

    // Start the subscription
    subscription.subscribe();

    // Connect to the Centrifugo server
    console.log("Connecting to Centrifugo server...");
    centrifuge.connect();
  };

  // Initialize or reset connection when config changes
  useEffect(() => {
    console.log("Config changed, establishing fresh connection");
    establishConnection();

    // Clean up on unmount or config change
    return cleanupConnection;
  }, [config.websocketEndpoint, config.token, config.channel]);

  // Function to manually force reconnection
  const reconnect = () => {
    console.log("Manual reconnection requested");
    establishConnection();
  };

  return {
    signals,
    isConnected,
    error,
    reconnect,
  };
};
