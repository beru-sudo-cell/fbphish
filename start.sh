#!/bin/bash

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Store process IDs
NODE_PID=""
TUNNEL_PID=""

print_status() {
    echo -e "${2}${1}${NC}"
}

LOG_FILE="/tmp/cloudflared_install.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== Cloudflared Installation Script ==="
echo "Started at: $(date)"

# Function to check if cloudflared is already installed
is_cloudflared_installed() {
    if command -v cloudflared &> /dev/null; then
        CURRENT_VERSION=$(cloudflared --version 2>/dev/null | head -n1)
        print_status "✅ cloudflared is already installed: $CURRENT_VERSION" "$GREEN"
        return 0
    else
        return 1
    fi
}

# Function to check and install dependencies
install_dependencies() {
    local deps=("wget")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            print_status "Installing $dep..." "$YELLOW"
            sudo apt-get update && sudo apt-get install -y "$dep"
        fi
    done
}

# Function to cleanup on failure during installation
install_cleanup() {
    print_status "Cleaning up installation..." "$RED"
    sudo rm -f /usr/local/bin/cloudflared
    exit 1
}

# Function to cleanup services
service_cleanup() {
    print_status "" "$NC"
    print_status "🛑 Shutting down services..." "$YELLOW"
    [ ! -z "$NODE_PID" ] && kill $NODE_PID 2>/dev/null
    [ ! -z "$TUNNEL_PID" ] && kill $TUNNEL_PID 2>/dev/null
    exit 0
}

# Check if cloudflared is installed
if ! is_cloudflared_installed; then
    print_status "ℹ️  cloudflared not found. Proceeding with installation..." "$YELLOW"
    
    # Set trap for installation cleanup
    trap install_cleanup ERR
    
    # Main installation
    install_dependencies

    print_status "Downloading cloudflared..." "$YELLOW"
    sudo wget --progress=bar:force https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -O /usr/local/bin/cloudflared

    print_status "Setting permissions..." "$YELLOW"
    sudo chmod +x /usr/local/bin/cloudflared

    print_status "Verifying installation..." "$YELLOW"
    if is_cloudflared_installed; then
        print_status "✅ Installation completed successfully!" "$GREEN"
    else
        print_status "❌ Installation failed!" "$RED"
        exit 1
    fi
else
    print_status "ℹ️  cloudflared is already installed. Skipping installation." "$GREEN"
fi

print_status "=== Cloudflared installation completed ===" "$GREEN"
print_status "Finished at: $(date)" "$GREEN"

# Now check Node.js dependencies
print_status "" "$NC"
print_status "=== Checking Node.js Application ===" "$YELLOW"

# Check if package.json exists
if [ ! -f "package.json" ]; then
    print_status "❌ package.json not found!" "$RED"
    exit 1
fi

# Check Node.js and npm
if ! command -v node &> /dev/null; then
    print_status "❌ Node.js is not installed!" "$RED"
    exit 1
fi

if ! command -v npm &> /dev/null; then
    print_status "❌ npm is not installed!" "$RED"
    exit 1
fi

print_status "📋 Checking Node.js dependencies..." "$YELLOW"

# Function to check if a specific package is installed
check_package() {
    local package=$1
    if npm list "$package" | grep -q "$package@"; then
        return 0  # Package is installed
    else
        return 1  # Package is not installed
    fi
}

# Check if node_modules exists
if [ ! -d "node_modules" ]; then
    print_status "🚀 node_modules not found - installing all dependencies..." "$YELLOW"
    npm install
else
    # Check for common Express.js packages
    print_status "🔍 Checking specific packages..." "$YELLOW"
    
    # List of common Express dependencies to check
    packages=("express" "cors" "body-parser" "dotenv" "mongoose" "axios")
    
    missing_packages=()
    
    for package in "${packages[@]}"; do
        # Check if package is in package.json dependencies
        if grep -q "\"$package\"" package.json; then
            if check_package "$package"; then
                print_status "   ✅ $package" "$GREEN"
            else
                print_status "   ❌ $package" "$RED"
                missing_packages+=("$package")
            fi
        fi
    done
    
    # Install if any packages are missing
    if [ ${#missing_packages[@]} -gt 0 ]; then
        echo ""
        print_status "🚀 Installing ${#missing_packages[@]} missing packages..." "$YELLOW"
        npm install
    else
        echo ""
        print_status "✅ All dependencies are properly installed!" "$GREEN"
    fi
fi

# Verify installation
echo ""
print_status "🔍 Running dependency verification..." "$YELLOW"
if npm ls --depth=0 &> /dev/null; then
    print_status "✅ All dependencies are correctly installed!" "$GREEN"
else
    print_status "❌ There are dependency issues. Running npm audit..." "$RED"
    npm audit fix
fi

print_status "🎉 Node.js dependencies check complete!" "$GREEN"

# Set trap for Ctrl+C for service cleanup
trap service_cleanup INT TERM

print_status "🚀 Starting Node.js server..." "$YELLOW"
sleep 1
print_status "📍 Local:    http://localhost:3000" "$GREEN"
sleep 1
print_status "🚀 Server started successfully!" "$GREEN"
sleep 1

# Start Cloudflare tunnel in background
print_status "🌐 Starting Cloudflare tunnel..." "$YELLOW"
cloudflared tunnel --url 127.0.0.1:3000 2>&1 | while IFS= read -r line; do
    if [[ "$line" == *"https://"*".trycloudflare.com"* ]]; then
        if [[ "$line" == *"https://api.trycloudflare.com"* ]]; then
            print_status "Something went wrong check your Internet" "$RED"
        else
            url=$(echo "$line" | sed 's/|//g' | xargs)
            print_status "========================================" "$GREEN"
            print_status "✅ Your Link is available at:" "$GREEN"
            print_status "   $url" "$GREEN"
            print_status "========================================" "$GREEN"
        fi
    fi
done &
TUNNEL_PID=$!

# Wait for tunnel to initialize
sleep 5

# Start Node.js server in foreground (this blocks until Ctrl+C)
node server.js &
NODE_PID=$!

# Wait for both processes
print_status "Services are running. Press Ctrl+C to stop..." "$YELLOW"
wait
