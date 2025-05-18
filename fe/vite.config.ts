import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    // You can configure proxy settings here for local development
    proxy: {
      "/centrifugo": {
        target: "http://localhost:8000", // Assuming you'll port-forward Centrifugo to this port locally
        changeOrigin: true,
        ws: true, // Important for WebSocket connections
      },
    },
  },
});
