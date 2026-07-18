#!/bin/bash
# ndetos AI Teaching Assistant - One-Command Installer
# ============================================================
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${BLUE}➜${NC} $1"; }
print_success() { echo -e "${GREEN}✅${NC} $1"; }
print_error() { echo -e "${RED}❌${NC} $1"; }
print_info() { echo -e "${YELLOW}ℹ️${NC} $1"; }

echo ""
echo "🚀 ndetos AI Teaching Assistant"
echo "=========================================="

# Detect OS
OS="$(uname -s 2>/dev/null || echo "Windows")"
case "${OS}" in
    Linux*)     OS_TYPE="Linux";;
    Darwin*)    OS_TYPE="macOS";;
    CYGWIN*|MINGW*|MSYS*) OS_TYPE="Windows";;
    *)          
        if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || [[ -n "$WSLENV" ]]; then
            OS_TYPE="Windows"
        else
            OS_TYPE="UNKNOWN"
        fi
        ;;
esac

# Check WSL
IS_WSL=false
grep -qi microsoft /proc/version 2>/dev/null && IS_WSL=true

# ============================================================
# STEP 1: Docker Installation (Auto)
# ============================================================
print_status "Checking system requirements..."

if ! command -v docker &> /dev/null; then
    print_status "Installing Docker (this may take a moment)..."
    
    case "$OS_TYPE" in
        Linux)
            curl -fsSL https://get.docker.com | sh
            if $IS_WSL; then
                sudo usermod -aG docker $USER
                print_info "WSL: Please restart your WSL terminal, then run this script again"
            else
                sudo usermod -aG docker $USER
                print_info "Please log out and back in, then run this script again"
            fi
            exit 0
            ;;
        macOS)
            if ! command -v brew &> /dev/null; then
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            fi
            brew install --cask docker
            echo ""
            print_info "To start Docker Desktop on macOS:"
            echo "   1. Open Finder → Applications → Docker.app"
            echo "   2. Or click the Docker icon in Launchpad"
            echo "   3. Wait for the Docker whale icon to appear in menu bar"
            echo ""
            print_info "Once Docker is running, run this script again"
            exit 0
            ;;
        Windows)
            powershell.exe -Command "
                \$installer = '\$env:TEMP\docker-installer.exe';
                Invoke-WebRequest -Uri 'https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe' -OutFile \$installer;
                Start-Process -FilePath \$installer -ArgumentList 'install', '--quiet' -Wait;
            " 2>/dev/null
            echo ""
            print_info "To complete Docker Desktop setup on Windows:"
            echo "   1. Docker Desktop installer will open - follow the wizard"
            echo "   2. IMPORTANT: Check 'Use WSL 2 instead of Hyper-V' when prompted"
            echo "   3. Restart your computer when installation completes"
            echo "   4. After restart, launch Docker Desktop from Start Menu"
            echo "   5. Wait for the Docker whale icon in system tray to stop animating"
            echo ""
            print_info "Once Docker is running, run this script again"
            exit 0
            ;;
        *)
            print_error "Please install Docker from https://docker.com"
            exit 1
            ;;
    esac
fi

# Ensure Docker is running
if ! docker info &> /dev/null; then
    case "$OS_TYPE" in
        Linux)
            if $IS_WSL; then
                echo ""
                print_info "To start Docker in WSL:"
                echo "   sudo service docker start"
                echo "   # Or: sudo systemctl start docker"
                echo ""
                print_info "Once Docker is running, run this script again"
            else
                echo ""
                print_info "To start Docker on Linux:"
                echo "   sudo systemctl start docker"
                echo "   # Or: sudo service docker start"
                echo "   # To auto-start on boot: sudo systemctl enable docker"
                echo ""
                print_info "Once Docker is running, run this script again"
            fi
            exit 0
            ;;
        macOS)
            echo ""
            print_info "To start Docker Desktop on macOS:"
            echo "   1. Open Finder → Applications → Docker.app"
            echo "   2. Or click the Docker icon in Launchpad"
            echo "   3. Wait for the Docker whale icon to appear in menu bar"
            echo ""
            print_info "Once Docker is running, run this script again"
            exit 0
            ;;
        Windows)
            echo ""
            print_info "To start Docker Desktop on Windows:"
            echo "   1. Click Start Menu and type 'Docker Desktop'"
            echo "   2. Click to launch Docker Desktop"
            echo "   3. Wait for the Docker whale icon in system tray to stop animating"
            echo "   4. If using WSL, ensure WSL integration is enabled in Docker settings"
            echo ""
            print_info "Once Docker is running, run this script again"
            exit 0
            ;;
    esac
fi

# ============================================================
# STEP 2: Setup and Install
# ============================================================
# Determine home directory
if [[ "$OS_TYPE" == "Windows" ]]; then
    AI_DIR="$USERPROFILE/ai-tutor"
else
    AI_DIR="$HOME/ai-tutor"
fi

mkdir -p "$AI_DIR"
cd "$AI_DIR"

# Download compose file
print_status "Downloading AI Tutor..."
curl -fsSL https://raw.githubusercontent.com/ndetos/ai-teaching-assistant/master/docker-compose.yml -o docker-compose.yml

# Get host IP (cross-platform)
if [[ "$OS_TYPE" == "Windows" ]]; then
    HOST_IP=$(powershell.exe -Command "Get-NetIPAddress -AddressFamily IPv4 | Where-Object {\$_.IPAddress -notmatch '^127\.'} | Select-Object -First 1 | ForEach-Object {\$_.IPAddress}" 2>/dev/null | tr -d '\r\n')
    [ -z "$HOST_IP" ] && HOST_IP=$(ipconfig | grep -i "IPv4" | grep -v "127.0.0.1" | head -1 | awk -F: '{print $2}' | xargs)
else
    HOST_IP=$(ip -4 addr show 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '^127\.' | head -1)
    [ -z "$HOST_IP" ] && HOST_IP=$(ifconfig 2>/dev/null | grep "inet " | grep -v 127.0.0.1 | head -1 | awk '{print $2}')
fi
[ -z "$HOST_IP" ] && HOST_IP="localhost"

export STUDENT_URL="http://$HOST_IP:5004"

# ============================================================
# Start containers with CLEAN PROGRESS (hiding technical details)
# ============================================================
print_status "Starting up ndetosAI components (this may take a few minutes)..."

start_time=$(date +%s)

# Redirect ALL output to /dev/null (both stdout AND stderr)
docker compose up -d 2>&1 > /dev/null &
pid=$!

while kill -0 $pid 2>/dev/null; do
    current_time=$(date +%s)
    elapsed=$((current_time - start_time))
    printf "\r   ⏳ %d seconds elapsed... " "$elapsed"
    sleep 1
done

wait $pid 2>/dev/null
exit_code=$?

printf "\r   "
if [ $exit_code -eq 0 ]; then
    current_time=$(date +%s)
    elapsed=$((current_time - start_time))
    printf "✅ Containers started in %d seconds   \n" "$elapsed"
else
    printf "❌ Failed to start containers   \n"
    # Show the error by running compose up without suppression
    docker compose up -d 2>&1
    exit $exit_code
fi
}

# Run docker compose up with output suppressed, but show errors if any
docker compose up -d 2>&1 | grep -v "Pulling\|Pulled\|Image\|Digest\|Status\|Download\|Extracting" &
show_spinner $!

# ============================================================
# Pull model with CLEAN PROGRESS
# ============================================================
print_status "Downloading the AI model (3.2GB - may take 5-15 minutes)..."
docker exec ollama-server ollama pull qwen2.5:1.5b 2>&1 | while IFS= read -r line; do
     # Extract percentage (e.g., "1%", "45%")
    if [[ $line =~ ([0-9]+)% ]]; then
        percent=${BASH_REMATCH[1]}
        # Use \r to return to start of line, overwrite with new percentage
        printf "\r   %3d%% complete" "$percent"
    fi
done

# ============================================================
# Verify everything is running
# ============================================================
print_status "Verifying installation..."
sleep 3

if curl -s -o /dev/null -w "%{http_code}" "http://localhost:5004" | grep -q "200\|302\|301"; then
    print_success "AI Tutor is running!"
else
    print_warning "Service may still be starting. Check: $STUDENT_URL"
fi

# ============================================================
# STEP 3: Create Shortcuts
# ============================================================
if [[ "$OS_TYPE" == "Linux" ]] && [ -d "$HOME/Desktop" ]; then
    cat > "$HOME/Desktop/ai-tutor.desktop" << EOF
[Desktop Entry]
Name=AI Tutor
Exec=gnome-terminal -- bash -c "cd $AI_DIR && docker compose up; exec bash"
Type=Application
Categories=Education;
EOF
    chmod +x "$HOME/Desktop/ai-tutor.desktop" 2>/dev/null
fi

if [[ "$OS_TYPE" == "Windows" ]]; then
    cat > "$USERPROFILE/Desktop/start-ai-tutor.bat" << EOF
@echo off
cd /d "%USERPROFILE%\ai-tutor"
docker compose up
pause
EOF
fi

# Create stop script
cat > "$AI_DIR/stop.sh" << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
docker compose down 2>/dev/null
echo "✅ ndetos stopped"
EOF
chmod +x "$AI_DIR/stop.sh" 2>/dev/null

# ============================================================
# STEP 4: Done
# ============================================================
echo ""
echo "=========================================="
echo "✅ Installation Complete!"
echo "=========================================="
echo ""
echo "📚 Students connect to: $STUDENT_URL"
echo "💻 You connect to: http://localhost:5004"
echo ""
echo "🔧 To stop: cd $AI_DIR && ./stop.sh"
echo "📧 Support: john.wandeto@dkut.ac.ke"
echo "=========================================="
