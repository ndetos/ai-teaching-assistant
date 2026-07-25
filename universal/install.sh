#!/bin/bash
# ndetos AI Teaching Assistant - Universal One-Command Installer (Slim)
# ============================================================
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
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
    Linux*) OS_TYPE="Linux";;
    Darwin*) OS_TYPE="macOS";;
    CYGWIN*|MINGW*|MSYS*) OS_TYPE="Windows";;
    *) [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || [[ -n "$WSLENV" ]] && OS_TYPE="Windows" || OS_TYPE="UNKNOWN";;
esac
grep -qi microsoft /proc/version 2>/dev/null && IS_WSL=true || IS_WSL=false

# Home directory
[[ "$OS_TYPE" == "Windows" ]] && AI_DIR="$USERPROFILE/ai-tutor" || AI_DIR="$HOME/ai-tutor"

# ============================================================
# STEP 1: Docker Installation
# ============================================================
print_status "Checking system requirements..."

if ! command -v docker &> /dev/null; then
    print_status "Installing Docker (this may take a moment)..."
    case "$OS_TYPE" in
        Linux) curl -fsSL https://get.docker.com | sh; sudo usermod -aG docker $USER; print_info "Please log out and back in, then run this script again"; exit 0 ;;
        macOS) brew install --cask docker 2>/dev/null || /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; print_info "Start Docker Desktop and run this script again"; exit 0 ;;
        Windows) print_info "Please install Docker Desktop from https://docker.com"; print_info "Enable WSL 2 integration"; read -p "Press Enter after installing Docker..."; exit 0 ;;
        *) print_error "Please install Docker from https://docker.com"; exit 1 ;;
    esac
fi

if ! docker info &> /dev/null; then
    print_info "Please start Docker and run this script again"
    [[ "$OS_TYPE" == "Linux" ]] && echo "   sudo systemctl start docker"
    [[ "$OS_TYPE" == "macOS" || "$OS_TYPE" == "Windows" ]] && echo "   Open Docker Desktop"
    exit 0
fi

# ============================================================
# STEP 2: Setup Directory
# ============================================================
mkdir -p "$AI_DIR"
cd "$AI_DIR"

# ============================================================
# STEP 3: Download Files
# ============================================================
print_status "Downloading AI Tutor configuration..."
curl -fsSL https://raw.githubusercontent.com/ndetos/ai-teaching-assistant/master/universal/docker-compose.yml -o docker-compose.yml
curl -fsSL https://raw.githubusercontent.com/ndetos/ai-teaching-assistant/master/universal/index_course.py -o index_course.py

# ============================================================
# STEP 4: Course Customization
# ============================================================
echo ""
echo "=========================================="
echo "📚 Course Customization"
echo "=========================================="
echo ""

exec 3< /dev/tty
read -p "Enter your course code (e.g., CIT 4104): " COURSE_CODE < /dev/tty
read -p "Enter your course name (e.g., Modeling and Simulation): " COURSE_NAME < /dev/tty
read -p "Enter your full name (as students will see it): " INSTRUCTOR_NAME < /dev/tty
read -p "Enter your institution name: " INSTITUTION_NAME < /dev/tty
mkdir -p "$AI_DIR/course-materials"
echo ""
print_info "Please copy your course materials into: $AI_DIR/course-materials/"
print_info "  - Lecture slides (PPT, PDF, PPTX)"
print_info "  - Lecture notes (DOC, DOCX, TXT, MD)"
print_info "  - Textbook chapters (PDF)"
read -p "Press Enter when you have copied your materials..." < /dev/tty
exec < /dev/stdin

# ============================================================
# STEP 5: Generate Custom ndetos_sim.py
# ============================================================
print_status "🔧 Creating your personalized AI Tutor..."
if [ -d "ndetos_sim.py" ]; then rm -rf ndetos_sim.py; fi

# Write the Python file using a heredoc with proper escaping
python3 << 'EOF' > ndetos_sim.py
#!/usr/bin/env python3
import os, re, pickle, requests
from pathlib import Path
from flask import Flask, request, jsonify
app = Flask(__name__)

OLLAMA_HOST = os.getenv("OLLAMA_HOST", "ollama")
OLLAMA_URL = f"http://{OLLAMA_HOST}:11434/api/generate"
MODEL = os.getenv("OLLAMA_MODEL", "qwen2.5:1.5b")

# Course configuration - will be replaced by install.sh
COURSE_CONFIG = {
    "tutor_name": "ndetos",
    "tutor_full_name": "AI Tutor",
    "course_code": "Your Course",
    "course_name": "Your Course",
    "instructor": "Your Instructor",
    "institution": "Your Institution",
    "greeting": "Welcome! I am ndetos, your AI tutor.",
    "system_prompt": "You are ndetos, the AI tutor. Answer questions based ONLY on course materials."
}

class KnowledgeBase:
    def __init__(self):
        self.kb = []
        self.load()
    def load(self):
        for p in [Path("/app/knowledge/knowledge_base.pkl"), Path("/app/knowledge_base.pkl")]:
            if p.exists():
                try:
                    with open(p, 'rb') as f:
                        d = pickle.load(f)
                    self.kb = d.get('chunks', []) if isinstance(d, dict) and 'chunks' in d else d if isinstance(d, list) else []
                    print(f"📚 Loaded {len(self.kb)} chunks")
                    return
                except:
                    pass
        print("📚 No knowledge base found")
    def search(self, q, n=3):
        if not self.kb:
            return ""
        ql = q.lower()
        kw = [w for w in re.findall(r'\b\w{3,}\b', ql) if w not in ['what','how','why','when','where','which','the','a','an','and','or','but']]
        scored = []
        for item in self.kb:
            c = item if isinstance(item, str) else item.get('content', '')
            if isinstance(item, dict):
                c = item.get('content', '')
            if c and isinstance(c, str):
                s = sum(1 for k in kw if k in c.lower())
                if s > 0:
                    scored.append((s, c))
        scored.sort(key=lambda x: -x[0])
        if scored:
            return "\n---\n".join([f"[From your course materials]\n{c[:1000]}" for _, c in scored[:n]])
        return ""

knowledge = KnowledgeBase()

HTML = '''<!DOCTYPE html>
<html><head><title>AI Tutor</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>*{box-sizing:border-box;}body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Arial,sans-serif;max-width:800px;margin:0 auto;padding:20px;background:linear-gradient(135deg,#1a1a2e 0%,#16213e 100%);min-height:100vh;}.chat-container{background:white;border-radius:20px;overflow:hidden;box-shadow:0 4px 6px rgba(0,0,0,0.1);}.header{background:#1a73e8;color:white;padding:20px;text-align:center;}.header h1{margin:0;font-size:1.5rem;}.scope-badge{text-align:center;font-size:11px;background:#e8f5e9;color:#2e7d32;padding:5px;margin:10px;border-radius:20px;}#chat{height:400px;overflow-y:auto;padding:15px;background:#f8f9fa;}.message{margin-bottom:12px;padding:8px 12px;border-radius:18px;max-width:85%;word-wrap:break-word;}.user{background:#1a73e8;color:white;margin-left:auto;text-align:right;border-bottom-right-radius:4px;}.assistant{background:#e9ecef;color:#333;margin-right:auto;border-bottom-left-radius:4px;}.system{background:#fff3cd;color:#856404;text-align:center;font-style:italic;margin:10px auto;max-width:90%;}.input-area{display:flex;padding:15px;gap:10px;border-top:1px solid #e0e0e0;background:white;}input{flex:1;padding:12px;border:1px solid #ddd;border-radius:24px;font-size:16px;outline:none;}button{padding:12px 24px;background:#1a73e8;color:white;border:none;border-radius:24px;font-size:16px;cursor:pointer;}button:hover{background:#1557b0;}.footer{text-align:center;padding:15px;font-size:11px;color:rgba(255,255,255,0.7);}</style>
</head><body>
<div class="chat-container"><div class="header"><h1>🎓 AI Tutor</h1><div class="scope-badge">👨🏫 AI Tutor</div></div>
<div id="chat"><div class="message system">Welcome to the AI Tutor!</div></div>
<div class="input-area"><input type="text" id="question" placeholder="Ask about your course..." autofocus><button onclick="ask()">Send</button></div></div>
<div class="footer">💡 Questions are answered using YOUR course materials only</div>
<script>
let loading=false;
function escapeHtml(t){let d=document.createElement("div");d.textContent=t;return d.innerHTML.replace(/\\n/g,"<br>");}
function addMessage(t,type){let c=document.getElementById("chat");let d=document.createElement("div");d.className="message "+type;d.innerHTML=(type==="user"?"👤 ":(type==="assistant"?"🤖 ":""))+escapeHtml(t);c.appendChild(d);c.scrollTop=c.scrollHeight;}
function addLoading(){let c=document.getElementById("chat");let d=document.createElement("div");d.id="loading";d.className="message assistant loading";d.innerHTML="🤖 ndetos is thinking...";c.appendChild(d);c.scrollTop=c.scrollHeight;}
function removeLoading(){let l=document.getElementById("loading");if(l)l.remove();}
async function ask(){if(loading)return;let i=document.getElementById("question");let q=i.value.trim();if(!q)return;addMessage(q,"user");i.value="";addLoading();loading=true;try{let r=await fetch("/ask",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({question:q})});let d=await r.json();removeLoading();if(d.error)addMessage("Error: "+d.error,"system");else addMessage(d.answer,"assistant");}catch(err){removeLoading();addMessage("Connection error: "+err.message,"system");}loading=false;i.focus();}
document.getElementById("question").addEventListener("keypress",function(e){if(e.key==="Enter")ask();});document.getElementById("question").focus();
</script>
</body></html>'''

@app.route('/')
def index():
    return HTML

@app.route('/ask', methods=['POST'])
def ask():
    d = request.get_json()
    if not d or not d.get('question'):
        return jsonify({'error': 'Invalid request'})
    q = d['question'].strip()
    ctx = knowledge.search(q)
    if ctx:
        p = f"{COURSE_CONFIG['system_prompt']}\n\nCourse material:\n{ctx}\n\nQuestion: {q}\n\nAnswer based ONLY on course materials."
        try:
            r = requests.post(OLLAMA_URL, json={"model": MODEL, "prompt": p, "stream": False, "temperature": 0.2, "num_predict": 512}, timeout=90)
            if r.status_code == 200:
                return jsonify({'answer': r.json().get('response', 'No response')})
            else:
                return jsonify({'error': f"Error: {r.status_code}"})
        except Exception as e:
            return jsonify({'error': str(e)})
    return jsonify({'answer': "I don't have that in my course materials. Please check your notes or ask your instructor."})

if __name__ == '__main__':
    print("\n" + "=" * 60)
    print(f"🎓 {COURSE_CONFIG['course_code']} - {COURSE_CONFIG['course_name']}")
    print("=" * 60)
    print(f"🤖 Tutor: {COURSE_CONFIG['tutor_name']}")
    print(f"📚 Knowledge base: {len(knowledge.kb)} items")
    print(f"\n🌐 STUDENTS CONNECT TO: {os.getenv('STUDENT_URL', 'http://localhost:5004')}")
    print("\n⏹️  Press Ctrl+C to stop")
    print("=" * 60 + "\n")
    app.run(host='0.0.0.0', port=5004, debug=False, threaded=True)
EOF

# Now replace the COURSE_CONFIG with the actual values
sed -i "s/\"course_code\": \"Your Course\"/\"course_code\": \"$COURSE_CODE\"/" ndetos_sim.py
sed -i "s/\"course_name\": \"Your Course\"/\"course_name\": \"$COURSE_NAME\"/" ndetos_sim.py
sed -i "s/\"instructor\": \"Your Instructor\"/\"instructor\": \"$INSTRUCTOR_NAME\"/" ndetos_sim.py
sed -i "s/\"institution\": \"Your Institution\"/\"institution\": \"$INSTITUTION_NAME\"/" ndetos_sim.py
sed -i "s/\"greeting\": \"Welcome! I am ndetos, your AI tutor.\"/\"greeting\": \"Welcome to $COURSE_CODE $COURSE_NAME! I am ndetos, your AI tutor.\"/" ndetos_sim.py
sed -i "s/\"system_prompt\": \"You are ndetos, the AI tutor. Answer questions based ONLY on course materials.\"/\"system_prompt\": \"You are ndetos, the AI tutor for $COURSE_NAME. Answer questions based ONLY on course materials.\"/" ndetos_sim.py

# Update the HTML title and header
sed -i "s/<title>AI Tutor<\/title>/<title>$COURSE_CODE - $COURSE_NAME AI Tutor<\/title>/" ndetos_sim.py
sed -i "s/<h1>🎓 AI Tutor<\/h1>/<h1>🎓 $COURSE_CODE $COURSE_NAME<\/h1>/" ndetos_sim.py
sed -i "s/<div class=\"scope-badge\">👨🏫 AI Tutor<\/div>/<div class=\"scope-badge\">👨🏫 $INSTRUCTOR_NAME | 🤖 Tutor: ndetos<\/div>/" ndetos_sim.py

# Validate
if python3 -m py_compile ndetos_sim.py 2>/dev/null; then
    print_success "✅ ndetos_sim.py syntax valid"
else
    print_error "❌ Syntax error"
    exit 1
fi

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
docker compose up -d
[ $? -eq 0 ] && print_success "✅ Containers started successfully" || { print_error "❌ Failed to start containers"; exit 1; }

# ============================================================
# STEP 8: Index Course Materials
# ============================================================
print_status "🔍 Indexing your course materials (this may take a few minutes)..."
sleep 5
mkdir -p "$AI_DIR/knowledge"
docker exec ai-tutor mkdir -p /tmp/indexing
docker cp "$AI_DIR/course-materials/." ai-tutor:/tmp/indexing/course-materials/ 2>/dev/null || docker cp course-materials/. ai-tutor:/tmp/indexing/course-materials/
docker cp index_course.py ai-tutor:/tmp/indexing/
docker exec ai-tutor python3 /tmp/indexing/index_course.py /tmp/indexing/course-materials/ -o /tmp/indexing/knowledge_base.pkl
docker cp ai-tutor:/tmp/indexing/knowledge_base.pkl "$AI_DIR/knowledge/knowledge_base.pkl"
docker exec ai-tutor rm -rf /tmp/indexing
print_success "✅ Course indexed successfully!"

# ============================================================
# STEP 9: Pull AI Model
# ============================================================
print_status "Downloading the AI model (3.2GB - may take 5-15 minutes)..."
docker exec ollama-server ollama pull qwen2.5:1.5b 2>&1 | while IFS= read -r line; do
    if [[ $line =~ ([0-9]+)% ]]; then
        printf "\r   %3d%% complete" "${BASH_REMATCH[1]}"
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
    print_info "Service may still be starting. Check: $STUDENT_URL"
fi

# ============================================================
# STEP 11: Restart and Finalize
# ============================================================
print_status "Restarting ai-tutor to load your course configuration..."
docker restart ai-tutor
sleep 5

# ============================================================
# STEP 12: Done
# ============================================================
echo ""
echo "=========================================="
echo "✅ Installation Complete!"
echo "=========================================="
echo ""
echo "📚 Course: ${COURSE_CODE} - ${COURSE_NAME}"
echo "👨🏫 Instructor: ${INSTRUCTOR_NAME}"
echo "🏛️  Institution: ${INSTITUTION_NAME}"
echo ""
echo "📚 Students connect to: ${STUDENT_URL}"
echo "💻 You connect to: http://localhost:5004"
echo ""
echo "📁 Files saved in: ${AI_DIR}"
echo ""
echo "🔧 To stop: cd ${AI_DIR} && ./stop.sh"
echo "📧 Support: john.wandeto@dkut.ac.ke"
echo "=========================================="
