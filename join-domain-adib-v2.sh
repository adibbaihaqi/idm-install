#!/bin/bash
# IdM Client Installation Script for Ubuntu

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "This script must be run as root (use sudo)"
    exit 1
fi

# IdM configuration
IDM_DOMAIN="baihaqiproject.web.id"
IDM_SERVER="idm.baihaqiproject.web.id"
IDM_REALM="BAIHAQIPROJECT.WEB.ID"
IDM_SERVER_IP="108.136.240.181"

# Get inputs
read -p "Enter hostname (e.g., pc-test-1): " CLIENT_HOSTNAME
read -p "Enter principal username: " PRINCIPAL_USER

# Validate inputs
if [ -z "$CLIENT_HOSTNAME" ] || [ -z "$PRINCIPAL_USER" ]; then
    echo "Hostname and principal cannot be empty"
    exit 1
fi

# Construct FQDN
CLIENT_FQDN="${CLIENT_HOSTNAME}.${IDM_DOMAIN}"

echo ""
echo "Will configure:"
echo "  Hostname: $CLIENT_FQDN"
echo "  Principal: $PRINCIPAL_USER"
echo ""
read -p "Continue? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Cancelled"
    exit 0
fi

# Update and install
echo "Installing packages..."
apt update -qq
apt install -y freeipa-client

# Set hostname
echo "Setting hostname..."
hostnamectl set-hostname "$CLIENT_FQDN"

# Update /etc/hosts
echo "Updating /etc/hosts..."
CLIENT_IP=$(hostname -I | awk '{print $1}')
sed -i "/$CLIENT_FQDN/d" /etc/hosts
sed -i "/$CLIENT_HOSTNAME/d" /etc/hosts
echo "$CLIENT_IP $CLIENT_FQDN $CLIENT_HOSTNAME" >> /etc/hosts

# Add IdM server to /etc/hosts
if ! grep -q "$IDM_SERVER" /etc/hosts; then
    echo "$IDM_SERVER_IP $IDM_SERVER idm" >> /etc/hosts
fi

# Enable home directory creation
echo "Configuring home directory creation..."
pam-auth-update --enable mkhomedir --force

# Join to IdM
echo "Joining to IdM domain..."
echo "You will be prompted for the password..."
ipa-client-install \
    --domain=$IDM_DOMAIN \
    --server=$IDM_SERVER \
    --realm=$IDM_REALM \
    --principal=$PRINCIPAL_USER \
    --mkhomedir \
    --ntp-server=$IDM_SERVER \
    --force-join

echo ""
echo "Installation complete!"
