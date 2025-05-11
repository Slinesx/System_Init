#!/usr/bin/env bash
set -euo pipefail

# ─── Error handling ────────────────────────────────────────────────────────────────
trap 'echo "❌ Error on line $LINENO: \`$BASH_COMMAND\`" >&2; exit 1' ERR
trap 'echo "🔪 Interrupted." >&2; exit 1' INT

echo "🚀 Starting system initialization..."

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run as root!" >&2
  exit 1
fi

# ─── 1) Docker Installation ────────────────────
echo "🐳 Installing Docker..."

# Add Docker's GPG key and repository
install -m 0755 -d /etc/apt/keyrings > /dev/null
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc > /dev/null
chmod a+r /etc/apt/keyrings/docker.asc > /dev/null

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker packages
apt-get update -qq > /dev/null
apt-get install -y -qq ca-certificates curl docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin > /dev/null

# Ask for username to add to docker group
echo -n "Enter username to add to docker group: "
read DOCKER_USER

# Configure Docker
usermod -aG docker $DOCKER_USER > /dev/null
systemctl enable docker.service > /dev/null
systemctl enable containerd.service > /dev/null

echo "✅ Docker setup complete!"

# ─── 2) Xray Installation ────────────────────
echo "📡 Installing Xray..."
bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install > /dev/null

# Configure Xray
echo "🔧 Configuring Xray..."
# Get public IP address
PUBLIC_IP=$(curl -s https://api.ipify.org)
# Generate random port for Xray
XRAY_PORT=$(shuf -i 10000-65000 -n 1)
# Generate password
XRAY_PASSWORD=$(openssl rand -base64 16)

# Download and modify config file
curl -fsSL https://raw.githubusercontent.com/Slinesx/System_Init/main/xray_server.conf -o /usr/local/etc/xray/config.json > /dev/null
# Update config with IP, port, and password
sed -i "s/\"listen\": \"\"/\"listen\": \"$PUBLIC_IP\"/" /usr/local/etc/xray/config.json
sed -i "s/\"port\": [0-9]*/\"port\": $XRAY_PORT/" /usr/local/etc/xray/config.json
sed -i "s/\"password\": \"\"/\"password\": \"$XRAY_PASSWORD\"/" /usr/local/etc/xray/config.json

# Restart Xray service
systemctl restart xray > /dev/null

echo "✅ Xray setup complete! Listening on $PUBLIC_IP:$XRAY_PORT with password: $XRAY_PASSWORD"

# ─── 3) Realm Installation ────────────────────
echo "🌐 Installing Realm..."

# Download latest Realm release
LATEST_RELEASE_URL=$(curl -s https://api.github.com/repos/zhboner/realm/releases/latest | 
                    grep "browser_download_url.*realm-x86_64-unknown-linux-gnu.tar.gz" | 
                    cut -d '"' -f 4)

# Create directories
mkdir -p /usr/local/etc/realm > /dev/null

# Download and install Realm
curl -fsSL "$LATEST_RELEASE_URL" -o /tmp/realm.tar.gz > /dev/null
tar -xzf /tmp/realm.tar.gz -C /tmp > /dev/null
install -m 755 /tmp/realm /usr/local/bin/realm > /dev/null
rm -f /tmp/realm.tar.gz /tmp/realm > /dev/null

# Download Realm config from GitHub
curl -fsSL https://raw.githubusercontent.com/Slinesx/System_Init/main/realm_server.toml -o /usr/local/etc/realm/config.toml > /dev/null

# Generate random port for realm
REALM_PORT=$(shuf -i 10000-65000 -n 1)

# Ask for remote IP address and SNI
echo -n "Enter remote IP address for Realm: "
read REMOTE_IP
echo -n "Enter SNI for remote_transport: "
read REMOTE_SNI

# Configure Realm
sed -i "s/listen = \"0.0.0.0:[0-9]*\"/listen = \"$PUBLIC_IP:$REALM_PORT\"/" /usr/local/etc/realm/config.toml
sed -i "s/remote = \":[0-9]*\"/remote = \"$REMOTE_IP:40945\"/" /usr/local/etc/realm/config.toml

# Update remote_transport SNI
sed -i "s/remote_transport = \"tls;sni=\"/remote_transport = \"tls;sni=$REMOTE_SNI\"/" /usr/local/etc/realm/config.toml

# Download and create systemd service file
curl -fsSL https://raw.githubusercontent.com/Slinesx/System_Init/main/realm.service -o /etc/systemd/system/realm.service > /dev/null

# Enable and start Realm service
systemctl daemon-reload > /dev/null
systemctl enable realm > /dev/null
systemctl start realm > /dev/null

echo "✅ Realm setup complete! Listening on $PUBLIC_IP:$REALM_PORT"