#!/usr/bin/env bash
# ==============================================================================
# CloudStripper Automated Security & SSL Engine
# License: MIT
# ==============================================================================

set -euo pipefail

TARGET_DOMAIN="example.com"  # Dynamically extracted from AGI manifest
CONTACT_EMAIL="security@squarespace-overhaul-ref.com"

log_sec() {
    echo -e "\033[1;36m[CloudStripper Security]\033[0m $1"
}

error_sec() {
    echo -e "\033[1;31m[SECURITY ERROR]\033[0m $1" >&2
    exit 1
}

# 1. Automated Firewall Hardening
log_sec "Hardening host firewall rules..."
if command -v ufw &> /dev/null; then
    sudo ufw allow 80/tcp comment 'CloudStripper HTTP Gateway' > /dev/null
    sudo ufw allow 443/tcp comment 'CloudStripper HTTPS Gateway' > /dev/null
    sudo ufw --force enable > /dev/null
fi

# 2. Pre-Flight Domain Validation
log_sec "Verifying DNS resolution for $TARGET_DOMAIN..."
PUBLIC_IP=$(curl -s https://ipify.org)
RESOLVED_IP=$(dig +short "$TARGET_DOMAIN" | tail -n1)

if [[ "$PUBLIC_IP" != "$RESOLVED_IP" ]]; then
    log_sec "WARNING: $TARGET_DOMAIN does not resolve to this server's public IP ($PUBLIC_IP)."
    log_sec "DNS currently points to: $RESOLVED_IP. SSL generation may fail."
fi

# 3. Automated Let's Encrypt SSL Generation
log_sec "Requesting automated SSL certificate via standalone ACME validation..."

# We run Certbot inside a temporary, isolated Docker container to avoid host pollution
sudo docker run --rm -it \
  -v "/etc/letsencrypt:/etc/letsencrypt" \
  -v "/var/lib/letsencrypt:/var/lib/letsencrypt" \
  -p 80:80 \
  certbot/certbot certonly \
  --standalone \
  --non-interactive \
  --agree-tos \
  --email "$CONTACT_EMAIL" \
  -d "$TARGET_DOMAIN"

# 4. Verifying Cryptographic Assets
if [[ -d "/etc/letsencrypt/live/$TARGET_DOMAIN" ]]; then
    log_sec "SSL Certificates successfully provisioned for https://$TARGET_DOMAIN"
    log_sec "Setting up automated 12-hour cron job for zero-touch certificate renewal..."
    
    (crontab -l 2>/dev/null; echo "0 */12 * * * docker run --rm -v '/etc/letsencrypt:/etc/letsencrypt' -v '/var/lib/letsencrypt:/var/lib/letsencrypt' p 80:80 certbot/certbot renew --quiet") | crontab -
else
    error_sec "Cryptographic handshake failed. Check network routing and DNS propagation."
fi
