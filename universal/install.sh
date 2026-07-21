#!/bin/bash
# ndetos AI Teaching Assistant - Universal One-Command Installer
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

IS_WSL=false
grep -qi microsoft /proc/version 2>/dev/null && IS_WSL=true

# ============================================================
# STEP 1: Docker Installation
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
                echo ""
                print_info "Once Docker is running, run this script again"
            fi
            exit 0
            ;;
        macOS|Windows)
            echo ""
            print_info "Please start Docker Desktop and run this script again"
            exit 0
            ;;
    esac
fi

# ============================================================
# STEP 2: Setup Directory
# ============================================================
if [[ "$OS_TYPE" == "Windows" ]]; then
    AI_DIR="$USERPROFILE/ai-tutor"
else
    AI_DIR="$HOME/ai-tutor"
fi

mkdir -p "$AI_DIR"
cd "$AI_DIR"

# ============================================================
# STEP 3: Download Configuration Files
# ============================================================
print_status "Downloading AI Tutor configuration..."

# Download docker-compose.yml
curl -fsSL https://raw.githubusercontent.com/ndetos/ai-teaching-assistant/master/universal/docker-compose.yml -o docker-compose.yml

# Download index_course.py
curl -fsSL https://raw.githubusercontent.com/ndetos/ai-teaching-assistant/master/universal/index_course.py -o index_course.py

# Download ndetos_sim_template.py
curl -fsSL https://raw.githubusercontent.com/ndetos/ai-teaching-assistant/master/universal/ndetos_sim_template.py -o ndetos_sim_template.py

# ============================================================
# STEP 4: Course Customization
# ============================================================
echo ""
echo "=========================================="
echo "📚 Course Customization"
echo "=========================================="
echo ""

# Get course information
read -p "Enter your course code (e.g., CIT 4104): " COURSE_CODE
read -p "Enter your course name (e.g., Modeling and Simulation): " COURSE_NAME
read -p "Enter your full name (as students will see it): " INSTRUCTOR_NAME
read -p "Enter your institution name: " INSTITUTION_NAME

# Create course materials folder
mkdir -p ~/ai-tutor/course-materials

echo ""
print_info "Please copy your course materials into: ~/ai-tutor/course-materials/"
print_info "  - Lecture slides (PPT, PDF, PPTX)"
print_info "  - Lecture notes (DOC, DOCX, TXT, MD)"
print_info "  - Textbook chapters (PDF)"
print_info "  - Any other course materials"
echo ""
read -p "Press Enter when you have copied your materials..."

# ============================================================
# STEP 5: Generate Custom ndetos_sim.py
# ============================================================
print_status "🔧 Creating your personalized AI Tutor..."

# Export variables so Python can access them
export COURSE_CODE
export COURSE_NAME
export INSTRUCTOR_NAME
export INSTITUTION_NAME

python3 << 'EOF'
import re
import os

# Get variables from environment
course_code = os.environ.get('COURSE_CODE', '')
course_name = os.environ.get('COURSE_NAME', '')
instructor_name = os.environ.get('INSTRUCTOR_NAME', '')
institution_name = os.environ.get('INSTITUTION_NAME', '')

with open('ndetos_sim_template.py', 'r') as f:
    content = f.read()

# Replace course configuration
content = re.sub(
    r'COURSE_CONFIG = \{.*?\}',
    f'''COURSE_CONFIG = {{
    "tutor_name": "ndetos",
    "tutor_full_name": "AI Tutor by {instructor_name}",
    "course_code": "{course_code}",
    "course_name": "{course_name}",
    "instructor": "{instructor_name}",
    "institution": "{institution_name}",
    "greeting": "Welcome to {course_code} {course_name}! I am ndetos, your AI tutor.",
    "system_prompt": \"\"\"You are ndetos, the AI tutor for {course_code} {course_name} at {institution_name}, created by {instructor_name}.

**CRITICAL INSTRUCTION: You must ONLY answer questions based on the provided course materials.**

**YOUR PURPOSE:**
1. Answer questions about {course_name} using ONLY the course materials provided
2. Help with course logistics (assignments, deadlines, lab instructions)
3. Assist with environment setup and tooling (uv, pip, Jupyter, Docker)
4. Provide programming help related to this course

**STRICT RULES - FOLLOW EXACTLY:**
- ALWAYS base your answer on the \"Course material from your notes\" section provided
- If the answer is in the materials, cite it: \"According to your Week X materials...\"
- If the answer is NOT in the materials, say: \"I don't have that in my course materials. Please check your notes or ask your instructor.\"
- NEVER provide complete assignment solutions - only hints and guidance
- Keep answers educational and concise (2-3 paragraphs)
- Reference the specific week/source when answering

**ABSOLUTELY FORBIDDEN:**
- Do NOT use external knowledge or general internet information
- Do NOT answer questions about topics outside the course
- Do NOT provide complete code solutions for assignments
- Do NOT speculate about content not in the provided materials

**Remember: You are a teaching assistant, not a general AI. Your knowledge is LIMITED to the course materials provided.**\"\"\"
}}''',
    content,
    flags=re.DOTALL
)

# Save the customized file
with open('ndetos_sim.py', 'w') as f:
    f.write(content)

print("✅ Customized ndetos_sim.py created")
EOF

# ============================================================
# STEP 6: Get Host IP
# ============================================================
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
# STEP 7: Start Docker Containers
# ============================================================
print_status "🚀 Starting your personalized AI Tutor..."

# Run docker compose up with visible output
docker compose up -d

# Check if it succeeded
if [ $? -eq 0 ]; then
    print_success "✅ Containers started successfully"
else
    print_error "❌ Failed to start containers"
    exit 1
fi

# ============================================================
# STEP 8: Index Course Materials (INSIDE DOCKER - NOW CONTAINER EXISTS)
# ============================================================
print_status "🔍 Indexing your course materials (this may take a few minutes)..."

# Wait for container to be fully ready
sleep 5

# Create the course materials directory in the container
docker exec ai-tutor mkdir -p /app/course-materials

# Copy course materials from host to container
docker cp ~/ai-tutor/course-materials/. ai-tutor:/app/course-materials/

# Copy the index_course.py script to the container
docker cp index_course.py ai-tutor:/app/

# Run the indexing inside the container
docker exec ai-tutor python3 /app/index_course.py /app/course-materials/ -o /app/knowledge_base.pkl

# Copy the generated knowledge base back to the host
docker cp ai-tutor:/app/knowledge_base.pkl ~/ai-tutor/knowledge_base.pkl

print_success "✅ Course indexed successfully!"

# ============================================================
# STEP 9: Pull AI Model
# ============================================================
print_status "Downloading the AI model (3.2GB - may take 5-15 minutes)..."

docker exec ollama-server ollama pull qwen2.5:1.5b 2>&1 | while IFS= read -r line; do
    if [[ $line =~ ([0-9]+)% ]]; then
        percent=${BASH_REMATCH[1]}
        printf "\r   %3d%% complete" "$percent"
    fi
done
echo ""

# ============================================================
# STEP 10: Verify Installation
# ============================================================
print_status "Verifying installation..."
sleep 5

if curl -s -o /dev/null -w "%{http_code}" "http://localhost:5004" | grep -q "200\|302\|301"; then
    print_success "AI Tutor is running!"
else
    print_warning "Service may still be starting. Check: $STUDENT_URL"
fi

# ============================================================
# STEP 11: Create Desktop Shortcuts
# ============================================================
if [[ "$OS_TYPE" == "Linux" ]] && [ -d "$HOME/Desktop" ]; then
    cat > "$HOME/Desktop/ai-tutor.desktop" << EOF
[Desktop Entry]
Name=AI Tutor - $COURSE_CODE
Comment=$COURSE_NAME
Exec=gnome-terminal -- bash -c "cd $AI_DIR && docker compose up; exec bash"
Icon=utilities-terminal
Terminal=false
Type=Application
Categories=Education;
EOF
    chmod +x "$HOME/Desktop/ai-tutor.desktop" 2>/dev/null
fi

if [[ "$OS_TYPE" == "Windows" ]]; then
    cat > "$USERPROFILE/Desktop/start-ai-tutor.bat" << EOF
@echo off
echo Starting $COURSE_CODE AI Tutor...
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
# STEP 12: Done
# ============================================================
echo ""
echo "=========================================="
echo "✅ Installation Complete!"
echo "=========================================="
echo ""
echo "📚 Course: $COURSE_CODE - $COURSE_NAME"
echo "👨🏫 Instructor: $INSTRUCTOR_NAME"
echo "🏛️  Institution: $INSTITUTION_NAME"
echo ""
echo "📚 Students connect to: $STUDENT_URL"
echo "💻 You connect to: http://localhost:5004"
echo ""
echo "📁 Files saved in: $AI_DIR"
echo ""
echo "🔧 To stop: cd $AI_DIR && ./stop.sh"
echo "📧 Support: john.wandeto@dkut.ac.ke"
echo "=========================================="
