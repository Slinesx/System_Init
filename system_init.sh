#!/usr/bin/env bash
set -euo pipefail

# ─── Error handling ────────────────────────────────────────────────────────────────
trap 'echo "❌ Error on line $LINENO: \`$BASH_COMMAND\`" >&2; exit 1' ERR
trap 'echo "🔪 Interrupted." >&2; exit 1' INT

echo "🚀 Starting system initialization..."

# Check if script is run with sudo
if [ "$EUID" -ne 0 ] && [ -z "$SUDO_USER" ]; then
  echo "❌ Please run with sudo!" >&2
  exit 1
fi

# ─── 1) Docker Installation ────────────────────
echo "🐳 Installing Docker..."

# Add Docker's GPG key and repository
sudo install -m 0755 -d /etc/apt/keyrings > /dev/null
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc > /dev/null
sudo chmod a+r /etc/apt/keyrings/docker.asc > /dev/null

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker packages
sudo apt-get update -qq > /dev/null
sudo apt-get install -y -qq ca-certificates curl docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin > /dev/null

# Configure Docker
sudo usermod -aG docker $USER > /dev/null
sudo systemctl enable docker.service > /dev/null
sudo systemctl enable containerd.service > /dev/null
newgrp docker > /dev/null

echo "✅ Docker setup complete!"

# ─── 2) Xray Installation ────────────────────
echo "📡 Installing Xray..."
bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install > /dev/null
echo "✅ Xray setup complete!"