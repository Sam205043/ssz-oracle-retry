#!/bin/bash
# SSZ n8n server - auto setup (Docker + n8n + Caddy HTTPS)
exec > /var/log/ssz-setup.log 2>&1
set -x
iptables -I INPUT 6 -m state --state NEW -p tcp --dport 80 -j ACCEPT
iptables -I INPUT 6 -m state --state NEW -p tcp --dport 443 -j ACCEPT
netfilter-persistent save || true
fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile && echo '/swapfile none swap sw 0 0' >> /etc/fstab
apt-get update -y
apt-get install -y ca-certificates curl openssl
curl -fsSL https://get.docker.com | sh
mkdir -p /opt/n8n/backups && cd /opt/n8n
KEY=$(openssl rand -hex 24)
cat > .env <<EOF
N8N_HOST=n8n.softskillzone.in
N8N_PROTOCOL=https
N8N_PORT=5678
WEBHOOK_URL=https://n8n.softskillzone.in/
N8N_EDITOR_BASE_URL=https://n8n.softskillzone.in/
N8N_PROXY_HOPS=1
GENERIC_TIMEZONE=Asia/Kolkata
TZ=Asia/Kolkata
N8N_ENCRYPTION_KEY=$KEY
N8N_RUNNERS_ENABLED=true
N8N_DIAGNOSTICS_ENABLED=false
EXECUTIONS_DATA_PRUNE=true
EXECUTIONS_DATA_MAX_AGE=168
EOF
chmod 600 .env
cat > Caddyfile <<'EOF'
n8n.softskillzone.in {
  reverse_proxy n8n:5678
}
EOF
cat > docker-compose.yml <<'EOF'
services:
  n8n:
    image: docker.n8n.io/n8nio/n8n:latest
    restart: always
    env_file: .env
    volumes:
      - n8n_data:/home/node/.n8n
  caddy:
    image: caddy:2
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
volumes:
  n8n_data:
  caddy_data:
EOF
docker compose up -d
cat > /opt/n8n/backup.sh <<'EOF'
#!/bin/bash
cd /opt/n8n
docker compose exec -T n8n n8n export:workflow --all --output=/home/node/.n8n/wf-backup.json
docker cp $(docker compose ps -q n8n):/home/node/.n8n/wf-backup.json backups/workflows-$(date +%F).json
cp .env backups/env-$(date +%F)
ls -t backups/workflows-*.json | tail -n +9 | xargs -r rm
EOF
chmod +x /opt/n8n/backup.sh
echo '0 3 * * 0 root /opt/n8n/backup.sh' > /etc/cron.d/n8n-backup
echo SETUP-DONE
