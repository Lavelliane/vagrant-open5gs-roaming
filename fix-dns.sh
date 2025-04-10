#!/bin/bash
# Script to fix DNS resolution issues in the VM

echo "Fixing DNS resolution issues..."

# Check current DNS settings
echo "Current DNS settings:"
cat /etc/resolv.conf

# Add Google DNS servers temporarily
echo "Adding Google DNS servers to /etc/resolv.conf..."
sudo bash -c 'echo "nameserver 8.8.8.8" >> /etc/resolv.conf'
sudo bash -c 'echo "nameserver 8.8.4.4" >> /etc/resolv.conf'

# Also configure systemd-resolved if it's being used
if systemctl is-active systemd-resolved >/dev/null 2>&1; then
  echo "Configuring systemd-resolved..."
  sudo mkdir -p /etc/systemd/resolved.conf.d/
  sudo bash -c 'cat > /etc/systemd/resolved.conf.d/dns_servers.conf << EOF
[Resolve]
DNS=8.8.8.8 8.8.4.4
EOF'
  sudo systemctl restart systemd-resolved
fi

# Test DNS resolution
echo "Testing DNS resolution..."
ping -c 2 google.com
ping -c 2 docker.io
ping -c 2 auth.docker.io

echo "DNS configuration complete. Try running the setup script again."

# If Docker is running, restart it to pick up the new DNS settings
if systemctl is-active docker >/dev/null 2>&1; then
  echo "Restarting Docker service..."
  sudo systemctl restart docker
fi