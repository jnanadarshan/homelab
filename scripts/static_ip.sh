#!/bin/bash

# Raspberry Pi Static IP Setup Script
# This script configures a static IP address for the LAN interface

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    print_error "This script should not be run as root. Please run as a regular user with sudo privileges."
    exit 1
fi

# Check if sudo is available
if ! command -v sudo &> /dev/null; then
    print_error "sudo is required but not found. Please install sudo or run as root."
    exit 1
fi

print_status "Raspberry Pi Static IP Configuration Script"
echo "=========================================="

# Get current network information
print_status "Current network configuration:"
ip addr show eth0 2>/dev/null || echo "eth0 interface not found"
echo

# Prompt for network configuration
read -p "Enter the static IP address (e.g., 192.168.1.100): " STATIC_IP
read -p "Enter the subnet mask in CIDR notation (e.g., 24 for /24): " SUBNET
read -p "Enter the gateway IP address (e.g., 192.168.1.1): " GATEWAY
read -p "Enter primary DNS server (e.g., 192.168.1.1): " DNS1
read -p "Enter secondary DNS server (e.g., 8.8.8.8): " DNS2
read -p "Enter interface name (default: eth0): " INTERFACE
INTERFACE=${INTERFACE:-eth0}

# Validate IP addresses (basic validation)
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    else
        return 1
    fi
}

if ! validate_ip "$STATIC_IP"; then
    print_error "Invalid static IP address format"
    exit 1
fi

if ! validate_ip "$GATEWAY"; then
    print_error "Invalid gateway IP address format"
    exit 1
fi

if ! validate_ip "$DNS1"; then
    print_error "Invalid primary DNS address format"
    exit 1
fi

if ! validate_ip "$DNS2"; then
    print_error "Invalid secondary DNS address format"
    exit 1
fi

# Confirm configuration
echo
print_warning "Configuration Summary:"
echo "Interface: $INTERFACE"
echo "Static IP: $STATIC_IP/$SUBNET"
echo "Gateway: $GATEWAY"
echo "DNS Servers: $DNS1, $DNS2"
echo

read -p "Do you want to apply this configuration? (y/N): " CONFIRM
if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
    print_status "Configuration cancelled."
    exit 0
fi

# Backup existing configuration
print_status "Creating backup of current dhcpcd.conf..."
sudo cp /etc/dhcpcd.conf /etc/dhcpcd.conf.backup.$(date +%Y%m%d_%H%M%S)

# Check if interface configuration already exists
if grep -q "^interface $INTERFACE" /etc/dhcpcd.conf; then
    print_warning "Existing configuration found for $INTERFACE interface."
    print_warning "This will be commented out and new configuration will be added."
    
    # Comment out existing configuration
    sudo sed -i "/^interface $INTERFACE/,/^$/s/^/#/" /etc/dhcpcd.conf
fi

# Add new static IP configuration
print_status "Adding static IP configuration to /etc/dhcpcd.conf..."
sudo tee -a /etc/dhcpcd.conf > /dev/null <<EOF

# Static IP configuration added by setup script
interface $INTERFACE
static ip_address=$STATIC_IP/$SUBNET
static routers=$GATEWAY
static domain_name_servers=$DNS1 $DNS2
EOF

print_status "Configuration added successfully."

# Restart networking service
print_status "Restarting dhcpcd service..."
sudo systemctl restart dhcpcd

# Wait a moment for the interface to come up
sleep 3

# Verify the configuration
print_status "Verifying new configuration..."
NEW_IP=$(ip addr show $INTERFACE | grep -oP 'inet \K[\d.]+' | head -1)

if [[ "$NEW_IP" == "$STATIC_IP" ]]; then
    print_status "SUCCESS: Static IP $STATIC_IP has been configured successfully!"
else
    print_warning "The IP address may not have changed yet. Current IP: $NEW_IP"
    print_status "Try running: ip addr show $INTERFACE"
fi

# Test connectivity
print_status "Testing connectivity..."
if ping -c 1 -W 3 "$GATEWAY" &> /dev/null; then
    print_status "Gateway connectivity: OK"
else
    print_warning "Gateway connectivity: FAILED"
fi

if ping -c 1 -W 3 8.8.8.8 &> /dev/null; then
    print_status "Internet connectivity: OK"
else
    print_warning "Internet connectivity: FAILED"
fi

print_status "Configuration complete!"
print_status "Your backup configuration is saved as: /etc/dhcpcd.conf.backup.*"
print_warning "Please reboot your system to ensure all changes take effect:"
print_warning "sudo reboot"

echo
print_status "To verify the configuration after reboot, run:"
echo "ip addr show $INTERFACE"
echo "ping $GATEWAY"
