# System-Init

A single-command installer for Docker, Xray, and Realm networking tools with automatic configuration.

## Quickstart

### Install / Configure

Run as root to install and configure:

```bash
bash -c "$(curl -H 'Cache-Control: no-cache, no-store' -fsSL https://raw.githubusercontent.com/Slinesx/System_Init/main/system_init.sh)"
```

## Repository Contents

- **system_init.sh**  
  System-wide installer:
  - Installs Docker CE and adds specified user to docker group
  - Installs Xray with random port and auto-generated password
  - Installs Realm network relay tool from GitHub releases
  - Configures system services for both Xray and Realm
  - Sets up firewall exceptions automatically

- **xray_server.conf**  
  Xray configuration template with Shadowsocks protocol, auto-configured with your server's public IP.

- **realm_server.toml**  
  Realm configuration template for network relay, automatically configured during installation.

- **realm.service**  
  Systemd service configuration for Realm to ensure automatic startup on boot.

## Required Inputs

During installation, you'll need to provide:

1. Username to add to Docker group
2. Remote IP address for Realm relay
3. SNI value for Realm TLS configuration

The script will handle all other configuration automatically. 