#!/usr/bin/env bash
set -euo pipefail

# ─── Error handling ────────────────────────────────────────────────────────────────
trap 'echo "❌ Error on line $LINENO: \`$BASH_COMMAND\`" >&2; exit 1' ERR
trap 'echo "🔪 Interrupted." >&2; exit 1' INT

echo "🧹 Starting system cleanup..."

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run as root!" >&2
  exit 1
fi

# ─── 1) Restore SSH configuration ────────────────────────────────────────────
echo "🔒 Restoring SSH configuration..."

# Restore SSH config from backup if it exists
if [ -f /etc/ssh/sshd_config.bak ]; then
  cp /etc/ssh/sshd_config.bak /etc/ssh/sshd_config
  systemctl restart sshd > /dev/null 2>&1 || true
  echo "  ↳ SSH configuration restored"
else
  # If no backup exists, manually restore default settings
  if [ -f /etc/ssh/sshd_config ]; then
    sed -i 's/^PermitRootLogin no/PermitRootLogin yes/' /etc/ssh/sshd_config
    sed -i 's/^PasswordAuthentication no/#PasswordAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/^PubkeyAuthentication yes/#PubkeyAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/^UsePAM no/UsePAM yes/' /etc/ssh/sshd_config
    systemctl restart sshd > /dev/null 2>&1 || true
    echo "  ↳ SSH configuration reset to defaults"
  fi
fi

echo "✅ SSH configuration restored!"

# ─── 2) Remove Created User ────────────────────
echo "👤 Removing created user..."

# Prompt for username to remove
read -p "Enter username to remove: " USERNAME_TO_REMOVE

if id "$USERNAME_TO_REMOVE" &>/dev/null; then
  # Kill user processes
  pkill -u "$USERNAME_TO_REMOVE" > /dev/null 2>&1 || true
  
  # Remove user and home directory
  userdel -r "$USERNAME_TO_REMOVE" > /dev/null 2>&1 || true
  echo "  ↳ User $USERNAME_TO_REMOVE removed"
else
  echo "  ↳ User $USERNAME_TO_REMOVE not found"
fi

echo "✅ User cleanup complete!"

# ─── 3) Remove Realm ────────────────────
echo "🌐 Removing Realm..."
# Stop and disable the service
systemctl stop realm > /dev/null 2>&1 || true
systemctl disable realm > /dev/null 2>&1 || true
# Remove service file
rm -f /etc/systemd/system/realm.service > /dev/null 2>&1 || true
# Remove binary and config
rm -f /usr/local/bin/realm > /dev/null 2>&1 || true
rm -rf /usr/local/etc/realm > /dev/null 2>&1 || true
systemctl daemon-reload > /dev/null 2>&1 || true

echo "✅ Realm removed!"

# ─── 4) Remove Xray ────────────────────
echo "📡 Removing Xray..."
# Use Xray's official uninstaller if available
if [ -f /usr/local/bin/xray ]; then
  bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge > /dev/null 2>&1 || true
else
  # Manual fallback cleanup
  systemctl stop xray > /dev/null 2>&1 || true
  systemctl disable xray > /dev/null 2>&1 || true
  rm -f /etc/systemd/system/xray.service > /dev/null 2>&1 || true
  rm -f /etc/systemd/system/xray@.service > /dev/null 2>&1 || true
  rm -f /usr/local/bin/xray > /dev/null 2>&1 || true
  rm -rf /usr/local/etc/xray > /dev/null 2>&1 || true
  rm -rf /usr/local/share/xray > /dev/null 2>&1 || true
  rm -rf /var/log/xray > /dev/null 2>&1 || true
fi
systemctl daemon-reload > /dev/null 2>&1 || true

echo "✅ Xray removed!"

# ─── 5) Remove Docker ────────────────────
echo "🐳 Removing Docker..."
# Stop and disable Docker services
systemctl stop docker.service > /dev/null 2>&1 || true
systemctl stop docker.socket > /dev/null 2>&1 || true
systemctl stop containerd.service > /dev/null 2>&1 || true
systemctl disable docker.service > /dev/null 2>&1 || true
systemctl disable docker.socket > /dev/null 2>&1 || true
systemctl disable containerd.service > /dev/null 2>&1 || true

# Uninstall Docker packages
apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin > /dev/null 2>&1 || true
apt-get autoremove -y > /dev/null 2>&1 || true

# Remove Docker configuration files
rm -rf /var/lib/docker > /dev/null 2>&1 || true
rm -rf /var/lib/containerd > /dev/null 2>&1 || true
rm -f /etc/apt/sources.list.d/docker.list > /dev/null 2>&1 || true
rm -f /etc/apt/keyrings/docker.asc > /dev/null 2>&1 || true

# Remove users from docker group and delete the group
echo "👥 Removing docker group and users..."
if getent group docker > /dev/null 2>&1; then
  # Get all users in docker group
  DOCKER_USERS=$(getent group docker | cut -d: -f4 | tr ',' ' ')
  
  # Remove each user from the docker group
  for user in $DOCKER_USERS; do
    gpasswd -d "$user" docker > /dev/null 2>&1 || true
    echo "   User '$user' removed from docker group"
  done
  
  # Delete the docker group
  groupdel docker > /dev/null 2>&1 || true
  echo "   Docker group removed"
fi

echo "✅ Docker removed!"

# Refresh package cache
apt-get update -qq > /dev/null 2>&1 || true

echo "🎉 System cleanup complete!"