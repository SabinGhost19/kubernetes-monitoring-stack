#!/bin/bash
# Script MINIMAL pentru Fluentd prerequisites
# Doar NTP + File Descriptors

set -e

echo "=== Configurare Fluentd Minimal - $(hostname) ==="
echo ""

# 1. INSTALARE NTP (chrony)
echo "[1/2] Instalare și configurare chrony pentru NTP..."
sudo apt-get update -qq
sudo apt-get install -y chrony

sudo systemctl restart chrony
sudo systemctl enable chrony

echo "✓ Chrony instalat și pornit"
sleep 2
chronyc tracking | grep "System time"
echo ""

# 2. FILE DESCRIPTORS
echo "[2/2] Configurare File Descriptors la 65536..."

# Backup
sudo cp /etc/security/limits.conf /etc/security/limits.conf.bak 2>/dev/null || true

# Adaugă doar dacă nu există
if ! grep -q "# Fluentd" /etc/security/limits.conf; then
    sudo tee -a /etc/security/limits.conf > /dev/null <<EOF

# Fluentd file descriptors
root soft nofile 65536
root hard nofile 65536
* soft nofile 65536
* hard nofile 65536
EOF
    echo "✓ File descriptors configurat în /etc/security/limits.conf"
else
    echo "✓ File descriptors deja configurat"
fi

echo ""
echo "=== COMPLETAT ==="
echo "Valoare curentă ulimit: $(ulimit -n)"
echo "După REBOOT va fi: 65536"
echo ""
echo "Următorii pași:"
echo "1. Rulează pe celălalt nod"
echo "2. sudo reboot (pe ambele noduri)"
echo "3. Verifică: ulimit -n"