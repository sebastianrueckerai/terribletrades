// TradeSignalList.tsx
import React from "react";
import { TradeSignal } from "../types";

interface TradeSignalListProps {
  signals: TradeSignal[];
  isConnected: boolean;
  error: string | null;
  onReconnect?: () => void;
}

// Enhanced relative time utility that also returns if the post is recent
const getRelativeTime = (
  timestamp: string
): { text: string; isRecent: boolean } => {
  const now = new Date();
  const pastDate = new Date(timestamp);
  const diffMs = now.getTime() - pastDate.getTime();

  // Convert to seconds, minutes, hours, days
  const diffSec = Math.floor(diffMs / 1000);
  const diffMin = Math.floor(diffSec / 60);
  const diffHours = Math.floor(diffMin / 60);
  const diffDays = Math.floor(diffHours / 24);

  // Check if post is recent (< 120 seconds old)
  const isRecent = diffSec < 120;

  if (diffSec < 60)
    return {
      text: `${diffSec} ${diffSec === 1 ? "second" : "seconds"} ago`,
      isRecent,
    };
  if (diffMin < 60)
    return {
      text: `${diffMin} ${diffMin === 1 ? "minute" : "minutes"} ago`,
      isRecent,
    };
  if (diffHours < 24)
    return {
      text: `${diffHours} ${diffHours === 1 ? "hour" : "hours"} ago`,
      isRecent,
    };
  if (diffDays < 30)
    return {
      text: `${diffDays} ${diffDays === 1 ? "day" : "days"} ago`,
      isRecent,
    };

  // Fallback to date for older posts
  return { text: pastDate.toLocaleDateString(), isRecent: false };
};

const TradeSignalList: React.FC<TradeSignalListProps> = ({
  signals,
  isConnected,
  error,
  onReconnect,
}) => {
  // Format the timestamp to be more readable
  const formatTimestamp = (timestamp: string): string => {
    return new Date(timestamp).toLocaleString();
  };

  // Add CSS for dark mode and monospace font
  React.useEffect(() => {
    // Add dark mode stylesheet
    const style = document.createElement("style");
    style.textContent = `
      :root {
        color-scheme: dark;
        --bg-color: #121212;
        --text-color: #e4e4e4;
        --accent-color: #bb86fc;
        --border-color: #333;
        --success-color: #4caf50;
        --error-color: #f44336;
        --warning-color: #ff9800;
      }
      
      body {
        background-color: var(--bg-color);
        color: var(--text-color);
        font-family: Menlo, Monaco, "Courier New", monospace;
        line-height: 1.5;
        margin: 0;
        padding: 16px;
      }
      
      h1 {
        color: var(--accent-color);
      }
      
      a {
        color: var(--accent-color);
        text-decoration: none;
      }
      
      a:hover {
        text-decoration: underline;
      }
      
      hr {
        border: none;
        border-top: 1px solid var(--border-color);
        margin: 16px 0;
      }
      
      ul {
        list-style: none;
        padding: 0;
      }
      
      li {
        border-bottom: 1px solid var(--border-color);
        padding: 16px 0;
      }
      
      .connected {
        color: var(--success-color);
      }
      
      .disconnected {
        color: var(--error-color);
      }
      
      .connecting {
        color: var(--warning-color);
      }
      
      .timestamp {
        color: #999;
        font-size: 0.9em;
      }
      
      .recent-timestamp {
        color: #ffffff;
        font-weight: bold;
      }
      
      .buy {
        color: #4caf50;
        font-weight: bold;
      }
      
      .sell {
        color: #f44336;
        font-weight: bold;
      }
      
      details {
        border: 1px solid var(--border-color);
        padding: 8px;
        margin-bottom: 16px;
        border-radius: 4px;
      }
      
      form div {
        margin-bottom: 8px;
      }
      
      input {
        background: #333;
        border: 1px solid var(--border-color);
        color: var(--text-color);
        padding: 4px 8px;
        font-family: inherit;
        width: 100%;
      }
      
      button {
        background: var(--accent-color);
        border: none;
        color: #000;
        padding: 8px 16px;
        font-family: inherit;
        cursor: pointer;
        border-radius: 4px;
        margin-right: 8px;
      }
      
      .status-bar {
        display: flex;
        justify-content: space-between;
        align-items: center;
        margin-bottom: 16px;
        padding: 8px;
        border: 1px solid var(--border-color);
        border-radius: 4px;
      }
    `;
    document.head.appendChild(style);

    return () => {
      document.head.removeChild(style);
    };
  }, []);

  return (
    <div>
      <div className="status-bar">
        <div>
          Connection status:{" "}
          {isConnected ? (
            <span className="connected">🟢 Connected</span>
          ) : (
            <span className="disconnected">🔴 Disconnected</span>
          )}
        </div>
        {!isConnected && onReconnect && (
          <div>
            <button onClick={onReconnect}>Reconnect Now</button>
          </div>
        )}
      </div>

      {error && (
        <div style={{ color: "var(--error-color)", marginBottom: "16px" }}>
          Error: {error}
        </div>
      )}

      {signals.length === 0 ? (
        <div>No trading signals received yet. Waiting for new signals...</div>
      ) : (
        <ul>
          {[...signals].reverse().map((signal, index) => {
            const relativeTime = getRelativeTime(signal.time);
            return (
              <li key={index}>
                <div>
                  <strong>{signal.ticker}</strong> -{" "}
                  <span className={signal.decision.toLowerCase()}>
                    {signal.decision}
                  </span>
                </div>
                <div
                  className={`timestamp ${
                    relativeTime.isRecent ? "recent-timestamp" : ""
                  }`}
                >
                  {formatTimestamp(signal.time)} ({relativeTime.text})
                </div>
                <div>
                  <strong>Source:</strong> r/{signal.post_subreddit} by u/
                  {signal.post_author}
                </div>
                {/* Post comes before Analysis now */}
                <div>
                  <strong>Post:</strong> {signal.post_title}
                </div>
                <div>
                  <strong>Analysis:</strong> {signal.analysis}
                </div>
                {signal.post_url && (
                  <div>
                    <a
                      href={signal.post_url}
                      target="_blank"
                      rel="noopener noreferrer"
                    >
                      View original post
                    </a>
                  </div>
                )}
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
};

export default TradeSignalList;
