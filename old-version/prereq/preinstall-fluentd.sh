#!/bin/bash
#  Fluentd prerequisites

set -e

echo "=== Configurare Fluentd Minimal - $(hostname) ==="
echo ""

echo "[1/2] Instalation and configuration for NTP..."
sudo apt-get update -qq
sudo apt-get install -y chrony

sudo systemctl restart chrony
sudo systemctl enable chrony

echo "✓ Chrony installed and started."
sleep 2
chronyc tracking | grep "System time"
echo ""

echo "[2/2] File Descriptors Configuration at 65536..."

sudo cp /etc/security/limits.conf /etc/security/limits.conf.bak 2>/dev/null || true

if ! grep -q "# Fluentd" /etc/security/limits.conf; then
    sudo tee -a /etc/security/limits.conf > /dev/null <<EOF

# Fluentd file descriptors
root soft nofile 65536
root hard nofile 65536
* soft nofile 65536
* hard nofile 65536
EOF
    echo "✓ File descriptors configured in /etc/security/limits.conf"
else
    echo "✓ File descriptors already configured in /etc/security/limits.conf"
fi

echo "=== COMPLETE ==="
echo "ulimit: $(ulimit -n)"
