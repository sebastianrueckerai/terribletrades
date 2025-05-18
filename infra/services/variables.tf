variable "kubeconfig_path" {
  description = "Path to kubeconfig file"
  type        = string
  default     = "../kubeconfig.yaml"
}

variable "ssh_priv_path" {
  type        = string
  description = "Path to local private SSH key"
}

variable "master_ip" {
  description = "IP address of the master node"
  type        = string
}

variable "redis_password" {
  description = "Password for Redis"
  type        = string
  sensitive   = true
}

# Reddit API credentials
variable "reddit_client_id" {
  description = "Reddit API Client ID"
  type        = string
  sensitive   = true
}

variable "reddit_client_secret" {
  description = "Reddit API Client Secret"
  type        = string
  sensitive   = true
}

variable "reddit_username" {
  description = "Reddit username"
  type        = string
  sensitive   = true
}

variable "reddit_password" {
  description = "Reddit password"
  type        = string
  sensitive   = true
}

variable "reddit_app_name" {
  description = "App name from https://www.reddit.com/prefs/apps"
  type        = string
}

variable "subreddits" {
  description = "comma-seperated subreddits"
  type        = string
}

variable "groq_api_key" {
  description = "API key for Groq LLM service"
  type        = string
  sensitive   = true
}

variable "groq_model_name" {
  description = "LLM - one of (https://console.groq.com/docs/models)"
  type        = string
  default     = "llama-3.3-70b-versatile"
}

variable "centrifugo_token_hmac_secret" {
  description = "Used to sign and verify JWTs for authenticating clients (users connecting via WebSocket)."
  type        = string
  sensitive   = true
}

variable "centrifugo_api_key" {
  description = "Used to authenticate HTTP API calls (e.g. publishing messages to channels)."
  type        = string
  sensitive   = true
}

variable "centrifugo_admin_password" {
  description = "For admin web UI - Password for logging in to the web dashboard."
  type        = string
  sensitive   = true
}

variable "centrifugo_admin_secret" {
  description = "For admin web UI - JWT signing secret for admin access."
  type        = string
  sensitive   = true
}

variable "domain_name" {
  description = "The domain name to use for the website"
  type        = string
}

variable "email_address" {
  description = "Email address for Let's Encrypt notifications"
  type        = string
}

variable "website_nodeport" {
  description = "NodePort for the website service"
  type        = number
  default     = 30080
}

variable "website_floating_ip" {
  description = "Floating IP address for the website domain"
  type        = string
}

variable "centrifugo_token" {
  description = "Token for Centrifugo authentication"
  type        = string
  sensitive   = true
}
