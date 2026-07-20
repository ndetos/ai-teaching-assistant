#!/bin/bash
# ndetos AI Teaching Assistant - Complete Uninstaller
# ============================================================
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${BLUE}➜${NC} $1"; }
print_success() { echo -e "${GREEN}✅${NC} $1"; }
print_info() { echo -e "${YELLOW}ℹ️${NC} $1"; }

echo ""
echo "🗑️  ndetos AI Teaching Assistant - Uninstaller"
echo "=========================================="

# Detect OS
OS="$(uname -s)"
case "${OS}" in
    Linux*)     OS_TYPE="Linux";;
    Darwin*)    OS_TYPE="macOS";;
    *)          OS_TYPE="UNKNOWN";;
esac

# Check if WSL
IS_WSL=false
grep -qi microsoft /proc/version 2>/dev/null && IS_WSL=true

# ============================================================
# STEP 1: Stop and remove containers
# ============================================================
print_status "Removing AI Tutor..."

if [ -d "$HOME/ai-tutor" ]; then
    cd "$HOME/ai-tutor" 2>/dev/null
    docker compose down -v 2>/dev/null || true
fi

# ============================================================
# STEP 2: Remove Docker images, volumes, networks
# ============================================================
docker rmi ndetos/ai-tutor-sim:latest 2>/dev/null || true
docker rmi ollama/ollama:latest 2>/dev/null || true
docker rmi qwen2.5:1.5b 2>/dev/null || true

docker volume ls -q | grep -E "(ollama|ndetos|ai-tutor)" | xargs -r docker volume rm -f 2>/dev/null || true
docker network ls -q | grep -E "(ndetos|ai-tutor)" | xargs -r docker network rm 2>/dev/null || true

# ============================================================
# STEP 3: Remove files and shortcuts
# ============================================================
rm -rf "$HOME/ai-tutor" 2>/dev/null
rm -f "$HOME/Desktop/ai-tutor.desktop" 2>/dev/null
rm -f "$HOME/Desktop/start-ai-tutor.command" 2>/dev/null

print_success "AI Tutor removed"

# ============================================================
# STEP 4: Ask about Docker removal (FIXED - reads from /dev/tty)
# ============================================================
if command -v docker &> /dev/null; then
    echo ""
    echo "Do you want to uninstall Docker too?"
    echo "  1) Yes, remove everything including Docker"
    echo "  2) No, keep Docker"
    echo ""
    
    # Read from /dev/tty to ensure interactive input works with curl | bash
    if [ -t 0 ]; then
        # Script is running interactively
        read -p "Enter choice (1 or 2): " choice
    else
        # Script is piped (curl | bash) - read from terminal directly
        read -p "Enter choice (1 or 2): " choice < /dev/tty
    fi

    if [ "$choice" = "1" ]; then
        print_status "Removing Docker..."
        echo ""
        case "$OS_TYPE" in
            Linux)
                if $IS_WSL; then
                    echo "Run these commands to remove Docker from WSL:"
                    echo "  sudo apt-get remove docker-ce docker-ce-cli containerd.io"
                    echo "  sudo apt-get autoremove"
                    echo "  sudo rm -rf /var/lib/docker /etc/docker"
                else
                    echo "Run these commands to remove Docker from Linux:"
                    echo "  sudo apt-get purge docker-ce docker-ce-cli containerd.io"
                    echo "  sudo apt-get autoremove"
                    echo "  sudo rm -rf /var/lib/docker /etc/docker /var/lib/containerd"
                fi
                ;;
            macOS)
                echo "To uninstall Docker Desktop on macOS:"
                echo "  1. Drag Docker.app from Applications to Trash"
                echo "  2. Run: rm -rf ~/Library/Containers/com.docker.docker"
                echo "  3. Run: rm -rf ~/.docker"
                ;;
            *)
                echo "Please uninstall Docker manually using your system's package manager"
                ;;
        esac
    else
        print_info "Keeping Docker installed"
    fi
fi

echo ""
echo "=========================================="
echo "✅ Uninstall complete!"
echo "Thank you for trying the AI Teaching Assistant."
echo "=========================================="
