#!/bin/bash
# AI Teaching Assistant - One-Command Installer
# ============================================================
# This script installs Docker (if needed) and runs the AI Tutor.
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "🚀 AI Teaching Assistant Installer"
echo "=========================================="
echo ""

# ============================================================
# STEP 1: Detect OS
# ============================================================

OS="$(uname -s)"
case "${OS}" in
    Linux*)     OS_TYPE="Linux";;
    Darwin*)    OS_TYPE="macOS";;
    CYGWIN*|MINGW*|MSYS*) OS_TYPE="Windows";;
    *)          OS_TYPE="UNKNOWN";;
esac
echo "📋 Detected OS: $OS_TYPE"
echo ""

# ============================================================
# STEP 2: Check Docker
# ============================================================

echo "📦 Checking Docker..."

if command -v docker &> /dev/null; then
    echo "   ✅ Docker already installed: $(docker --version)"
else
    echo "   🔧 Docker is required but not found."
    echo ""
    case "$OS_TYPE" in
        Linux)
            echo "   Installing Docker on Linux..."
            curl -fsSL https://get.docker.com | sh
            sudo usermod -aG docker $USER
            echo "   ✅ Docker installed. Please log out and back in."
            echo "   Then run this script again."
            exit 0
            ;;
        macOS)
            echo "   📥 Please install Docker Desktop for macOS:"
            echo "   → Download from: https://docker.com"
            echo "   → Or run: brew install --cask docker"
            echo ""
            read -p "   Press Enter after you have installed Docker..."
            ;;
        Windows)
            echo "   📥 Please install Docker Desktop for Windows:"
            echo "   → Download from: https://docker.com"
            echo "   → Run the installer and restart your computer."
            echo ""
            read -p "   Press Enter after you have installed Docker..."
            ;;
        *)
            echo "   ❌ Unsupported OS. Please install Docker manually."
            exit 1
            ;;
    esac
fi

echo ""

# ============================================================
# STEP 3: Check Docker Compose
# ============================================================

echo "📦 Checking Docker Compose..."

if docker compose version &> /dev/null; then
    echo "   ✅ Docker Compose available"
elif command -v docker-compose &> /dev/null; then
    echo "   ✅ Docker Compose available (old version)"
else
    echo "   ❌ Docker Compose not found."
    echo "   It is included with Docker Desktop."
    exit 1
fi

echo ""

# ============================================================
# STEP 4: Download docker-compose.yml
# ============================================================

echo "📥 Downloading AI Tutor configuration..."

mkdir -p ~/ai-tutor
cd ~/ai-tutor

# Download the docker-compose.yml from GitHub
curl -fsSL https://raw.githubusercontent.com/ndetos/ai-teaching-assistant/master/docker-compose.yml -o docker-compose.yml

echo "   ✅ Configuration downloaded to ~/ai-tutor"
echo ""

# ============================================================
# STEP 5: Optional Desktop Shortcut (Linux)
# ============================================================

if [[ "$OS_TYPE" == "Linux" ]]; then
    echo "🖥️ Creating desktop shortcut..."
    cat > ~/Desktop/ai-tutor.desktop << EOF
[Desktop Entry]
Name=AI Tutor
Comment=Start the AI Teaching Assistant
Exec=gnome-terminal -- bash -c "cd ~/ai-tutor && docker-compose up"
Icon=utilities-terminal
Terminal=false
Type=Application
Categories=Education;
EOF
    chmod +x ~/Desktop/ai-tutor.desktop 2>/dev/null || echo "   ⚠️ Could not create desktop shortcut"
fi

echo ""

# ============================================================
# STEP 6: Run the AI Tutor
# ============================================================

echo "=========================================="
echo "✅ Installation Complete!"
echo "=========================================="
echo ""
echo "Your AI Tutor is ready to run."
echo ""
echo "To start it now, run:"
echo "   cd ~/ai-tutor && docker-compose up"
echo ""
echo "Once running, open your browser to:"
echo "   http://localhost:5004"
echo ""
echo "📧 Support: john.wandeto@dkut.ac.ke"
echo "📱 WhatsApp: +254 783 808 800"
echo ""
echo "=========================================="

read -p "Do you want to start the AI Tutor now? (y/n) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🚀 Starting AI Tutor..."
    cd ~/ai-tutor
    docker-compose up
else
    echo "To start later, run: cd ~/ai-tutor && docker-compose up"
fi
