// Type definitions for trade signals

export interface TradeSignal {
  decision: "BUY" | "SELL";
  ticker: string;
  analysis: string;
  src: string;
  time: string;
  post_title: string;
  post_body: string;
  post_url: string;
  post_author: string;
  post_subreddit: string;
  post_created: string;
}

export interface CentrifugoConfig {
  websocketEndpoint: string;
  token: string;
  channel: string;
}
