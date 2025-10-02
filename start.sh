#!/bin/bash



#!/bin/bash

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${2}${1}${NC}"
}

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
# Store process IDs
NODE_PID=""
TUNNEL_PID=""

# Cleanup function
cleanup() {
    echo ""
    echo "🛑 Shutting down services..."
    [ ! -z "$NODE_PID" ] && kill $NODE_PID 2>/dev/null
    [ ! -z "$TUNNEL_PID" ] && kill $TUNNEL_PID 2>/dev/null
    exit 0
}

# Set trap for Ctrl+C
trap cleanup INT TERM

echo "🚀 Starting Node.js server..."
sleep 1
echo "📍 Local:    http://localhost:3000"
sleep 1
echo "🚀 Server started successfully!"
sleep 1

# Start Cloudflare tunnel in background
echo "🌐 Starting Cloudflare tunnel..."
cloudflared tunnel --url 127.0.0.1:3000 2>&1 | while IFS= read -r line; do
    if [[ "$line" == *"https://"*".trycloudflare.com"* ]]; then
        url=$(echo "$line" | sed 's/|//g' | xargs)
        echo "========================================"
        echo "✅ Your app is available at:"
        echo "   $url"
        echo "========================================"

    fi
done &
TUNNEL_PID=$!

# Wait for tunnel to initialize
sleep 5

# Start Node.js server in foreground (this blocks until Ctrl+C)

node server.js &
NODE_PID=$!

# Wait for both processes
echo "Services are running. Press Ctrl+C to stop..."
wait