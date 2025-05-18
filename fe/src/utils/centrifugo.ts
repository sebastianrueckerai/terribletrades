import { Centrifuge } from "centrifuge";
import { CentrifugoConfig } from "../types";

// Keep track of active connections to prevent duplicates
const activeConnections: Record<string, Centrifuge> = {};

// This is a utility function to create and configure the Centrifuge client
export const createCentrifugeClient = (
  config: CentrifugoConfig
): Centrifuge => {
  // Create a unique key for this connection
  const connectionKey = `${config.websocketEndpoint}-${config.channel}`;

  // Close and clean up any existing connection with the same key
  if (activeConnections[connectionKey]) {
    try {
      console.log(`Cleaning up existing connection for ${connectionKey}`);
      activeConnections[connectionKey].disconnect();
      activeConnections[connectionKey].removeAllListeners();
      delete activeConnections[connectionKey];
    } catch (err) {
      console.error("Error cleaning up existing connection:", err);
    }
  }

  // Generate a unique client ID
  const clientID = `fe-${Date.now()}-${Math.random()
    .toString(36)
    .substring(2, 15)}`;

  // Create a new client instance with explicit configuration
  const centrifuge = new Centrifuge(config.websocketEndpoint, {
    token: config.token,
    getToken: null,
    name: clientID,
    minReconnectDelay: 1000, // Start with 1 second delay
    maxReconnectDelay: 20000, // Max 20 seconds between reconnects
    debug: true, // Enable debug logging (helpful for troubleshooting)
  });

  // Set up logging for development
  centrifuge.on("connecting", (ctx) => {
    console.log(`Connecting to Centrifugo with client ID ${clientID}...`, ctx);
  });

  centrifuge.on("connected", (ctx) => {
    console.log(`Connected to Centrifugo with client ID ${clientID}`, ctx);
  });

  centrifuge.on("disconnected", (ctx) => {
    console.log(`Disconnected from Centrifugo with client ID ${clientID}`, ctx);
  });

  // Handle transport errors
  centrifuge.on("error", (ctx) => {
    console.error(`Centrifugo client ${clientID} error:`, ctx);
  });

  // Store this connection for future reference
  activeConnections[connectionKey] = centrifuge;

  return centrifuge;
};
