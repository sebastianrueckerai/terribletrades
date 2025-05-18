#!/bin/bash
set -e
set -x

echo "Updating package lists"
apt-get update

echo "Installing nginx and certbot"
apt-get install -y nginx certbot python3-certbot-nginx

echo "Creating nginx site configuration"
cat > /etc/nginx/sites-available/terribletrades.com << 'EOFNGINX'
server {
    listen 80;
    server_name terribletrades.com www.terribletrades.com;

    location / {
        proxy_pass http://localhost:30080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
EOFNGINX

echo "Enabling site configuration"
ln -sf /etc/nginx/sites-available/terribletrades.com /etc/nginx/sites-enabled/
systemctl reload nginx

echo "Getting SSL certificate"
certbot --nginx --non-interactive --agree-tos --email mail@sebastianruecker.com -d terribletrades.com -d www.terribletrades.com

echo "Setup complete"
