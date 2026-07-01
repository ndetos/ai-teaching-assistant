#!/bin/bash
# ndetos AI Teaching Assistant - One-Command Installer
# ============================================================
# This script installs Docker (if needed), pulls the AI model,
# and runs the AI Tutor in the background.
# ============================================================
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================
# Helper Functions
# ============================================================
print_status() {
    echo -e "${BLUE}➜${NC} $1"
}

print_success() {
    echo -e "${GREEN}✅${NC} $1"
}

print_error() {
    echo -e "${RED}❌${NC} $1"
}

# ============================================================
# Main Script
# ============================================================

echo ""
echo "🚀 ndetos AI Teaching Assistant"
echo "=========================================="

# Detect OS
OS="$(uname -s)"
case "${OS}" in
    Linux*)     OS_TYPE="Linux";;
    Darwin*)    OS_TYPE="macOS";;
    CYGWIN*|MINGW*|MSYS*) OS_TYPE="Windows";;
    *)          OS_TYPE="UNKNOWN";;
esac

# ============================================================
# STEP 1: Check Docker
# ============================================================
print_status "Checking statu..."

if command -v docker &> /dev/null; then
    print_success "ok"
else
    print_status "Installing..."
    case "$OS_TYPE" in
        Linux)
            curl -fsSL https://get.docker.com | sh
            sudo usermod -aG docker $USER
            echo "   Please log out and back in, then run this script again."
            exit 0
            ;;
        macOS)
            echo "   Please install Docker Desktop from: https://docker.com"
            echo "   Press Enter after installation..."
            read
            ;;
        Windows)
            echo "   Please install Docker Desktop from: https://docker.com"
            echo "   Press Enter after installation..."
            read
            ;;
        *)
            print_error "Unsupported OS. Please install Docker manually."
            exit 1
            ;;
    esac
fi

# ============================================================
# STEP 2: Check Docker Compose
# ============================================================
if ! docker compose version &> /dev/null && ! command -v docker-compose &> /dev/null; then
    print_error "Docker Compose not found. It is included with Docker Desktop."
    exit 1
fi

# ============================================================
# STEP 3: Download and Start AI Tutor
# ============================================================
print_status "Installation in progress: please wait..."
echo "   This will take about 3-7 minutes depending on your network."

mkdir -p ~/ai-tutor
cd ~/ai-tutor

# Download docker-compose.yml
curl -fsSL https://raw.githubusercontent.com/ndetos/ai-teaching-assistant/master/docker-compose.yml -o docker-compose.yml > /dev/null 2>&1

# Get Host IP
HOST_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '^127\.' | grep -v '^172\.' | head -1)
if [ -z "$HOST_IP" ]; then
    HOST_IP=$(hostname -I | awk '{print $1}')
fi
export STUDENT_URL="http://$HOST_IP:5004"

# Start containers
docker compose up -d > /dev/null 2>&1

# ============================================================
# STEP 4: Wait for AI Tutor to be ready
# ============================================================
sleep 5

# Display the student URL
STUDENT_URL=$(docker compose logs ai-tutor 2>/dev/null | grep "STUDENTS CONNECT TO" | tail -1 | sed -E 's/.*(http:[^ ]*).*/\1/')
if [ -z "$STUDENT_URL" ]; then
    STUDENT_URL="http://$HOST_IP:5004"
fi

# ============================================================
# STEP 5: Pull AI Model (if needed)
# ============================================================
MODEL_EXISTS=$(docker exec ollama-server ollama list 2>/dev/null | grep "qwen2.5:1.5b" || true)
if [ -z "$MODEL_EXISTS" ]; then
    docker exec ollama-server ollama pull qwen2.5:1.5b > /dev/null 2>&1
fi

# ============================================================
# STEP 6: Desktop Shortcuts
# ============================================================
if [[ "$OS_TYPE" == "Linux" ]]; then
    cat > ~/Desktop/ai-tutor.desktop << EOF
[Desktop Entry]
Name=AI Tutor
Comment=Start the AI Teaching Assistant
Exec=gnome-terminal -- bash -c "cd ~/ai-tutor && docker compose up; exec bash"
Icon=utilities-terminal
Terminal=false
Type=Application
Categories=Education;
EOF
    chmod +x ~/Desktop/ai-tutor.desktop 2>/dev/null
fi

if [[ "$OS_TYPE" == "Windows" ]]; then
    cat > "$HOME/Desktop/start-ai-tutor.bat" << EOF
@echo off
echo Starting AI Teaching Assistant...
cd /d %USERPROFILE%\ai-tutor
docker compose up
pause
EOF
fi
# ============================================================
# customize the stop command
# ============================================================
# Create a stop script
cat > ~/ai-tutor/stop.sh << 'EOF'
#!/bin/bash
cd ~/ai-tutor
docker compose down 2>/dev/null
echo "✅ ndetos has stopped"
EOF
chmod +x ~/ai-tutor/stop.sh
# ============================================================
# STEP 7: Complete
# ============================================================
echo ""
echo "=========================================="
echo "✅ Installation Complete!"
echo "=========================================="
echo ""
echo "📚 Students connect to: $STUDENT_URL"
echo "💻 You connect to: http://localhost:5004"
echo ""
echo "🔧 To stop the AI Tutor:"
echo "   cd ~/ai-tutor && docker compose down"
echo ""
echo "📧 Support: john.wandeto@dkut.ac.ke"
echo "📱 WhatsApp: +254 783 808 800"
echo "=========================================="
