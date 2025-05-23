#!/usr/bin/env bash
set -euo pipefail

# ─── Error handling ────────────────────────────────────────────────────────────────
trap 'echo "❌ Error on line $LINENO: \`$BASH_COMMAND\`" >&2; exit 1' ERR
trap 'echo "🔪 Interrupted." >&2; exit 1' INT

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run as root!" >&2
  exit 1
fi

# Check for authorized_keys
if [ ! -f /root/.ssh/authorized_keys ]; then
  echo "❌ ssh authorized_keys does not exist!" >&2
  exit 1
fi

echo "🚀 Starting system initialization..."

# ─── 1) Create new user with sudo privileges ─────────────────────────────────────
echo "👤 Creating a new sudo user..."
read -p "Enter username: " NEW_USER
useradd -m -G sudo "$NEW_USER"
passwd "$NEW_USER"

echo "✅ User $NEW_USER created and added to sudo group!"

# ─── 2) Secure SSH configuration ─────────────────────────────────────────────────
echo "🔒 Configuring SSH security..."

# Create SSH directory for new user if it doesn't exist
USER_SSH_DIR="/home/$NEW_USER/.ssh"
mkdir -p "$USER_SSH_DIR"

# Transfer authorized_keys
cp /root/.ssh/authorized_keys "$USER_SSH_DIR/" 

# Set proper ownership and permissions
chown -R "$NEW_USER:$NEW_USER" "$USER_SSH_DIR"
chmod 700 "$USER_SSH_DIR"
[ -f "$USER_SSH_DIR/authorized_keys" ] && chmod 600 "$USER_SSH_DIR/authorized_keys"

# Update SSH configuration based on the default file structure
# Make backup of original config
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

# Simply modify the lines directly from default config
sed -i 's/^PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^UsePAM yes/UsePAM no/' /etc/ssh/sshd_config

# Restart SSH service
systemctl restart sshd

echo "✅ SSH security configured!"

# ─── 3) Kernel parameters optimization ─────────────────────────────────────────
echo "🔧 Updating sysctl settings..."

# Append sysctl.conf content to system configuration
cat /root/System_Init/sysctl.conf >> /etc/sysctl.conf

# Apply the changes
sysctl -p > /dev/null

# Configure file descriptor limits
echo "🔧 Configuring file descriptor limits..."
cat << EOF >> /etc/security/limits.conf

# Increased file descriptor limits
* soft nofile 51200
* hard nofile 51200

# for server running in root:
root soft nofile 51200
root hard nofile 51200
EOF

# Set the current session limit
ulimit -n 51200

echo "✅ Network parameters optimized!"

# ─── 4) Docker Installation ────────────────────
echo "🐳 Installing Docker..."

# Add Docker's GPG key and repository
install -m 0755 -d /etc/apt/keyrings > /dev/null
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc > /dev/null
chmod a+r /etc/apt/keyrings/docker.asc > /dev/null

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker packages
apt-get update -qq > /dev/null
apt-get install -y -qq ca-certificates curl docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin > /dev/null

# Configure Docker - use the newly created user
usermod -aG docker "$NEW_USER" > /dev/null
systemctl enable docker.service
systemctl enable containerd.service

echo "✅ Docker setup complete!"

# ─── 5) Vim Installation ──────────────────────
echo "📝 Installing Vim..."
apt-get update -qq > /dev/null
apt-get install -y -qq vim > /dev/null
echo "✅ Vim installed!"

# ─── 6) Realm Installation ────────────────────
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

# Get local IP address from the primary network interface
HOST_IP=$(ip -4 addr show scope global | grep -oP '(?<=inet\s)[\d.]+' | head -n1)
# Get public IP address from external service
PUBLIC_IP=$(curl -s https://api.ipify.org)

# Ask for remote host (IP:PORT), listen port, and SNI
echo -n "Enter remote host for Realm (IP:PORT): "
read REMOTE_HOST
echo -n "Enter listen port for Realm: "
read REALM_LISTEN_PORT
echo -n "Enter SNI for remote_transport: "
read REMOTE_SNI

# Configure Realm - using exact format from realm_server.toml
sed -i "s|listen = \".*\"|listen = \"$HOST_IP:$REALM_LISTEN_PORT\"|" /usr/local/etc/realm/config.toml
sed -i "s|remote = \".*\"|remote = \"$REMOTE_HOST\"|" /usr/local/etc/realm/config.toml

# Update remote_transport SNI
sed -i "s|remote_transport = \"tls;sni=.*\"|remote_transport = \"tls;sni=$REMOTE_SNI\"|" /usr/local/etc/realm/config.toml

# Download and create systemd service file
curl -fsSL https://raw.githubusercontent.com/Slinesx/System_Init/main/realm.service -o /etc/systemd/system/realm.service > /dev/null

# Enable and start Realm service
systemctl daemon-reload > /dev/null
systemctl enable realm > /dev/null
systemctl start realm > /dev/null

echo "✅ Realm setup complete! Listening on $PUBLIC_IP:$REALM_LISTEN_PORT"

# ─── 7) Xray Installation ────────────────────
echo "📡 Installing Xray..."
bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install > /dev/null

# Configure Xray
echo "🔧 Configuring Xray..."
# Use the same HOST_IP and PUBLIC_IP as above

# Find an available port for Xray
while :; do
  XRAY_PORT=$(shuf -i20000-65000 -n1)
  ss -tln | awk '{print $4}' | grep -q ":${XRAY_PORT}$" || break
done

# Generate password
XRAY_PASSWORD=$(openssl rand -base64 16)

# Download and modify config file
curl -fsSL https://raw.githubusercontent.com/Slinesx/System_Init/main/xray_server.conf -o /usr/local/etc/xray/config.json > /dev/null
# Update config with IP, port, and password
sed -i "s/\"listen\": \"\"/\"listen\": \"$HOST_IP\"/" /usr/local/etc/xray/config.json
sed -i "s/\"port\": [0-9]*/\"port\": $XRAY_PORT/" /usr/local/etc/xray/config.json
sed -i "s/\"password\": \"\"/\"password\": \"$XRAY_PASSWORD\"/" /usr/local/etc/xray/config.json

# Restart Xray service
systemctl restart xray > /dev/null

echo "✅ Xray setup complete! Listening on $PUBLIC_IP:$XRAY_PORT with password: $XRAY_PASSWORD"