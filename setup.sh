#!/bin/bash

# === CONFIGURATION ===
DOMAIN="odoo.yourdomain.com"
EMAIL="admin@yourdomain.com"
REPO_URL="https://github.com/your-org/your-custom-odoo-modules.git"

# === INSTALL DOCKER & DOCKER COMPOSE ===
echo "Installing Docker and Docker Compose..."
apt update && apt upgrade -y
apt install -y docker.io docker-compose git
systemctl enable docker && systemctl start docker

# === PROJECT SETUP ===
mkdir -p ~/odoo16-docker/{addons,nginx,certbot/{conf,www}}
cd ~/odoo16-docker

# === CLONE CUSTOM MODULES (Optional) ===
git clone $REPO_URL addons/custom_modules || echo "Skipping Git clone..."

# === CREATE docker-compose.yml ===
cat > docker-compose.yml <<EOF
version: '3.8'

services:
  odoo:
    image: odoo:16
    depends_on:
      - db
    environment:
      - HOST=db
      - USER=odoo
      - PASSWORD=odoo
    volumes:
      - odoo-web-data:/var/lib/odoo
      - ./addons:/mnt/extra-addons
    expose:
      - "8069"
    restart: always

  db:
    image: postgres:13
    environment:
      - POSTGRES_DB=postgres
      - POSTGRES_USER=odoo
      - POSTGRES_PASSWORD=odoo
    volumes:
      - odoo-db-data:/var/lib/postgresql/data
    restart: always

  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx:/etc/nginx/conf.d
      - ./certbot/www:/var/www/certbot
      - ./certbot/conf:/etc/letsencrypt
    depends_on:
      - odoo
    restart: always

  certbot:
    image: certbot/certbot
    volumes:
      - ./certbot/www:/var/www/certbot
      - ./certbot/conf:/etc/letsencrypt
    entrypoint: "/bin/sh -c 'trap exit TERM; while :; do sleep 6h & wait \$${!}; certbot renew; done'"
    restart: always

volumes:
  odoo-web-data:
  odoo-db-data:
EOF

# === CREATE NGINX CONFIG ===
cat > nginx/odoo.conf <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    location / {
        proxy_pass http://odoo:8069;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# === START CONTAINERS ===
echo "Starting containers (initial setup)..."
docker-compose up -d

# === ISSUE SSL CERTIFICATE ===
echo "Issuing Let's Encrypt certificate..."
docker-compose run --rm certbot certonly \
  --webroot --webroot-path=/var/www/certbot \
  --email $EMAIL \
  --agree-tos --no-eff-email \
  -d $DOMAIN

# === RESTART EVERYTHING ===
echo "Restarting all services with SSL..."
docker-compose down
docker-compose up -d

echo ""
echo "✅ Odoo 16 is now live at: https://$DOMAIN"
