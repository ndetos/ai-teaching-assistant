#!/usr/bin/env python3
"""
AI Teaching Assistant - Universal Course Tutor
RAG-Powered Web Assistant for ANY course
"""

import os
import re
import pickle
import socket
import subprocess
from collections import defaultdict
from datetime import datetime
from pathlib import Path

import requests
from flask import Flask, render_template_string, request, jsonify

app = Flask(__name__)

# ============================================================
# TECHNICAL CONFIGURATION
# ============================================================

# Ollama configuration
OLLAMA_HOST = os.getenv("OLLAMA_HOST", "localhost")
OLLAMA_URL = f"http://{OLLAMA_HOST}:11434/api/generate"
MODEL = os.getenv("OLLAMA_MODEL", "qwen2.5:1.5b")

# ============================================================
# COURSE CONFIGURATION FROM ENVIRONMENT
# ============================================================

COURSE_CONFIG = {
    "tutor_name": os.getenv("TUTOR_NAME", "ndetos"),
    "tutor_full_name": os.getenv("TUTOR_FULL_NAME", "AI Tutor"),
    "course_code": os.getenv("COURSE_CODE", "Your Course"),
    "course_name": os.getenv("COURSE_NAME", "Your Course"),
    "instructor": os.getenv("INSTRUCTOR", "Your Instructor"),
    "institution": os.getenv("INSTITUTION", "Your Institution"),
    
    "greeting": os.getenv(
        "GREETING",
        "Welcome! I am ndetos, your AI tutor. I can answer questions about this course based on your instructor's materials."
    ),
    
    "system_prompt": os.getenv(
        "SYSTEM_PROMPT",
        """You are ndetos, an AI tutor for {course_code} {course_name} at {institution}, created by {instructor}.

**YOUR PURPOSE - YOU ANSWER QUESTIONS ABOUT:**
1. Course content (based on the materials provided)
2. Course logistics (assignments, deadlines, lab instructions)
3. Environment setup and tooling (if applicable)
4. Programming help related to this course

**RULES:**
- Base answers on the course materials provided.
- Reference the source when answering (e.g., "According to Lecture 4...")
- Never provide complete assignment solutions.
- If you cannot find the answer in course materials, say: "I don't have that in my course materials. Please check your notes or ask your instructor."
- Keep answers educational and concise (2-3 paragraphs)."""
    )
}

# Apply environment variables to system prompt
COURSE_CONFIG["system_prompt"] = COURSE_CONFIG["system_prompt"].format(
    course_code=COURSE_CONFIG["course_code"],
    course_name=COURSE_CONFIG["course_name"],
    institution=COURSE_CONFIG["institution"],
    instructor=COURSE_CONFIG["instructor"]
)

# ============================================================
# KNOWLEDGE BASE - LOAD FROM MOUNTED VOLUME
# ============================================================

# Knowledge base paths (search order)
KB_PATHS = [
    Path("/app/knowledge/knowledge_base.pkl"),  # Docker mount path
    Path("/knowledge/knowledge_base.pkl"),       # Legacy mount path
    Path(__file__).parent / "knowledge_base.pkl",  # Local (fallback)
]

KNOWLEDGE_BASE_FILE = None
for path in KB_PATHS:
    if path.exists():
        KNOWLEDGE_BASE_FILE = path
        break


class CourseKnowledgeBase:
    def __init__(self):
        self.knowledge_base = []
        self.load_knowledge_base()
    
    def load_knowledge_base(self):
        if KNOWLEDGE_BASE_FILE and KNOWLEDGE_BASE_FILE.exists():
            try:
                with open(KNOWLEDGE_BASE_FILE, 'rb') as f:
                    self.knowledge_base = pickle.load(f)
                print(f"📚 Loaded {len(self.knowledge_base)} items from course materials")
                self.show_weeks_loaded()
            except Exception as e:
                print(f"⚠️ Could not load knowledge base: {e}")
        else:
            print("📚 No knowledge base found.")
            print("   Please mount your course materials at /app/knowledge/")
    
    def show_weeks_loaded(self):
        weeks = {}
        for item in self.knowledge_base:
            week = item.get('week', 0)
            weeks[week] = weeks.get(week, 0) + 1
        if weeks:
            print(f"   Weeks loaded: {', '.join(f'Week {w}({c})' for w, c in sorted(weeks.items()))}")
    
    def search(self, question: str, max_results: int = 3) -> str:
        if not self.knowledge_base:
            return ""
        
        question_lower = question.lower()
        stopwords = {'what', 'how', 'why', 'when', 'where', 'which', 'the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for', 'of', 'with', 'by', 'is', 'are', 'was', 'were'}
        keywords = [w for w in re.findall(r'\b\w{3,}\b', question_lower) if w not in stopwords]
        
        scored_items = []
        for item in self.knowledge_base:
            content_lower = item.get('content', '').lower()
            score = sum(1 for kw in keywords if kw in content_lower)
            if score > 0:
                scored_items.append((score, item))
        
        scored_items.sort(key=lambda x: (-x[0], -x[1].get('week', 0)))
        
        if not scored_items:
            return ""
        
        context_parts = []
        for _, item in scored_items[:max_results]:
            week = item.get('week', '?')
            source = item.get('source', 'notes')
            content = item.get('content', '')[:1000]
            if week and week > 0:
                context_parts.append(f"[From Week {week} materials: {source}]\n{content}\n")
            else:
                context_parts.append(f"[From: {source}]\n{content}\n")
        
        return "\n---\n".join(context_parts)


knowledge = CourseKnowledgeBase()

# ============================================================
# SECURITY CONFIGURATION
# ============================================================

MAX_REQUESTS_PER_MINUTE = 5
MAX_REQUESTS_PER_HOUR = 30
request_tracker = defaultdict(list)

MAX_QUESTION_LENGTH = 500
MIN_QUESTION_LENGTH = 3

DANGEROUS_PATTERNS = [
    r'rm\s+-rf', r'sudo\s+', r'exec\s*\(', r'eval\s*\(',
    r'__import__', r'subprocess', r'os\.system', r'popen',
    r'<\/', r'<script', r'javascript:', r'onload=', r'onerror='
]


def is_rate_limited(ip: str) -> tuple:
    now = datetime.now()
    request_tracker[ip] = [t for t in request_tracker[ip] if (now - t).seconds < 3600]
    
    minute_requests = sum(1 for t in request_tracker[ip] if (now - t).seconds < 60)
    if minute_requests >= MAX_REQUESTS_PER_MINUTE:
        return (True, "Too many requests. Please wait a moment.")
    
    if len(request_tracker[ip]) >= MAX_REQUESTS_PER_HOUR:
        return (True, "Hourly limit reached. Please try later.")
    
    request_tracker[ip].append(now)
    return (False, "")


def validate_question(question: str) -> tuple:
    if not question or not isinstance(question, str):
        return (False, "Please enter a valid question.")
    if len(question) < MIN_QUESTION_LENGTH:
        return (False, f"Question too short (minimum {MIN_QUESTION_LENGTH} characters).")
    if len(question) > MAX_QUESTION_LENGTH:
        return (False, f"Question too long (maximum {MAX_QUESTION_LENGTH} characters).")
    
    for pattern in DANGEROUS_PATTERNS:
        if re.search(pattern, question, re.IGNORECASE):
            return (False, "Question contains disallowed content.")
    return (True, "")

# ============================================================
# HTML INTERFACE
# ============================================================

HTML = f'''
<!DOCTYPE html>
<html>
<head>
    <title>{COURSE_CONFIG['course_code']} - {COURSE_CONFIG['course_name']} AI Tutor</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        * {{ box-sizing: border-box; }}
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Arial, sans-serif;
            max-width: 800px;
            margin: 0 auto;
            padding: 20px;
            background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
            min-height: 100vh;
        }}
        .chat-container {{
            background: white;
            border-radius: 20px;
            overflow: hidden;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }}
        .header {{
            background: #1a73e8;
            color: white;
            padding: 20px;
            text-align: center;
        }}
        .header h1 {{
            margin: 0;
            font-size: 1.5rem;
        }}
        .header .course-code {{
            font-size: 0.8rem;
            opacity: 0.9;
            margin-top: 5px;
        }}
        .scope-badge {{
            text-align: center;
            font-size: 11px;
            background: #e8f5e9;
            color: #2e7d32;
            padding: 5px;
            margin: 10px;
            border-radius: 20px;
        }}
        #chat {{
            height: 400px;
            overflow-y: auto;
            padding: 15px;
            background: #f8f9fa;
        }}
        .message {{
            margin-bottom: 12px;
            padding: 8px 12px;
            border-radius: 18px;
            max-width: 85%;
            word-wrap: break-word;
        }}
        .user {{
            background: #1a73e8;
            color: white;
            margin-left: auto;
            text-align: right;
            border-bottom-right-radius: 4px;
        }}
        .assistant {{
            background: #e9ecef;
            color: #333;
            margin-right: auto;
            border-bottom-left-radius: 4px;
        }}
        .system {{
            background: #fff3cd;
            color: #856404;
            text-align: center;
            font-style: italic;
            margin: 10px auto;
            max-width: 90%;
        }}
        .input-area {{
            display: flex;
            padding: 15px;
            gap: 10px;
            border-top: 1px solid #e0e0e0;
            background: white;
        }}
        input {{
            flex: 1;
            padding: 12px;
            border: 1px solid #ddd;
            border-radius: 24px;
            font-size: 16px;
            outline: none;
        }}
        button {{
            padding: 12px 24px;
            background: #1a73e8;
            color: white;
            border: none;
            border-radius: 24px;
            font-size: 16px;
            cursor: pointer;
        }}
        button:hover {{ background: #1557b0; }}
        .footer {{
            text-align: center;
            padding: 15px;
            font-size: 11px;
            color: rgba(255,255,255,0.7);
        }}
    </style>
</head>
<body>
    <div class="chat-container">
        <div class="header">
            <h1>🎓 {COURSE_CONFIG['course_code']} {COURSE_CONFIG['course_name']}</h1>
            <div class="course-code">👨‍🏫 {COURSE_CONFIG['instructor']} | 🤖 Tutor: {COURSE_CONFIG['tutor_name']}</div>
        </div>
        <div class="scope-badge">
            📚 I answer questions based on your course materials
        </div>
        <div id="chat">
            <div class="message system">{COURSE_CONFIG['greeting']}</div>
        </div>
        <div class="input-area">
            <input type="text" id="question" placeholder="Ask about your course..." autofocus>
            <button onclick="ask()">Send</button>
        </div>
    </div>
    <div class="footer">
        💡 Ask about course concepts, assignments, or technical setup
    </div>

    <script>
        let loading = false;
        
        function escapeHtml(text) {{
            let div = document.createElement('div');
            div.textContent = text;
            return div.innerHTML.replace(/\\n/g, '<br>');
        }}
        
        function addMessage(text, type) {{
            let chat = document.getElementById('chat');
            let div = document.createElement('div');
            div.className = 'message ' + type;
            div.innerHTML = (type === 'user' ? '👤 ' : (type === 'assistant' ? '🤖 ' : '')) + escapeHtml(text);
            chat.appendChild(div);
            chat.scrollTop = chat.scrollHeight;
        }}
        
        function addLoading() {{
            let chat = document.getElementById('chat');
            let div = document.createElement('div');
            div.id = 'loading';
            div.className = 'message assistant loading';
            div.innerHTML = '🤖 Thinking...';
            chat.appendChild(div);
            chat.scrollTop = chat.scrollHeight;
        }}
        
        function removeLoading() {{
            let loading = document.getElementById('loading');
            if (loading) loading.remove();
        }}
        
        async function ask() {{
            if (loading) return;
            
            let input = document.getElementById('question');
            let question = input.value.trim();
            if (!question) return;
            
            addMessage(question, 'user');
            input.value = '';
            addLoading();
            loading = true;
            
            try {{
                let response = await fetch('/ask', {{
                    method: 'POST',
                    headers: {{ 'Content-Type': 'application/json' }},
                    body: JSON.stringify({{ question: question }})
                }});
                
                let data = await response.json();
                removeLoading();
                
                if (data.error) {{
                    addMessage('Error: ' + data.error, 'system');
                }} else {{
                    addMessage(data.answer, 'assistant');
                }}
            }} catch (err) {{
                removeLoading();
                addMessage('Connection error: ' + err.message, 'system');
            }}
            loading = false;
            input.focus();
        }}
        
        document.getElementById('question').addEventListener('keypress', function(e) {{
            if (e.key === 'Enter') ask();
        }});
        document.getElementById('question').focus();
    </script>
</body>
</html>
'''

# ============================================================
# FLASK ROUTES
# ============================================================

@app.after_request
def add_security_headers(response):
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['X-Frame-Options'] = 'DENY'
    response.headers['X-XSS-Protection'] = '1; mode=block'
    return response


@app.route('/')
def index():
    return render_template_string(HTML)


@app.route('/ask', methods=['POST'])
def ask():
    client_ip = request.remote_addr
    
    limited, limit_msg = is_rate_limited(client_ip)
    if limited:
        return jsonify({'error': limit_msg})
    
    data = request.get_json()
    if not data:
        return jsonify({'error': 'Invalid request format.'})
    
    question = data.get('question', '').strip()
    valid, validation_msg = validate_question(question)
    if not valid:
        return jsonify({'error': validation_msg})
    
    print(f"\n📝 Question: {question[:80]}...")
    
    # Search course materials
    course_context = knowledge.search(question)
    
    if course_context:
        print(f"   📚 Found relevant course material")
        prompt = f"""{COURSE_CONFIG['system_prompt']}

Course material from your notes:
{course_context}

Student question: {question}

INSTRUCTIONS:
1. Base your answer on the course material above
2. Reference which week/material the answer comes from
3. Give hints, not complete solutions
4. If the material doesn't fully answer, supplement with your general knowledge

{COURSE_CONFIG['tutor_name']}:"""
    else:
        print(f"   📚 No course material found")
        return jsonify({
            'answer': "I don't have that in my course materials. Please check your notes or ask your instructor."
        })
    
    try:
        response = requests.post(
            OLLAMA_URL,
            json={
                "model": MODEL,
                "prompt": prompt,
                "stream": False,
                "temperature": 0.3,
                "num_predict": 512,
            },
            timeout=90
        )
        
        if response.status_code == 200:
            answer = response.json().get("response", "No response generated.")
            answer = re.sub(r'<script.*?>.*?</script>', '', answer, flags=re.DOTALL)
            print(f"   ✅ Answer sent")
            return jsonify({'answer': answer})
        else:
            return jsonify({'error': f"Ollama error: HTTP {response.status_code}"})
            
    except requests.exceptions.Timeout:
        return jsonify({'error': "Request timed out. Please try a simpler question."})
    except Exception as e:
        return jsonify({'error': str(e)})


# ============================================================
# STARTUP
# ============================================================

def get_local_ip():
    """Get the host machine's IP address for students to connect."""
    try:
        result = subprocess.run(['hostname', '-I'], capture_output=True, text=True)
        ips = result.stdout.strip().split()
        if ips:
            for ip in ips:
                if not ip.startswith('172.') and not ip.startswith('192.168.'):
                    return ip
            return ips[0]
    except:
        pass
    
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except:
        pass
    
    return "127.0.0.1"


if __name__ == '__main__':
    student_url = os.getenv("STUDENT_URL", None)
    if student_url is None:
        local_ip = get_local_ip()
        student_url = f"http://{local_ip}:5004"
    
    print("\n" + "=" * 60)
    print(f"🎓 {COURSE_CONFIG['course_code']} - {COURSE_CONFIG['course_name']}")
    print("=" * 60)
    print(f"👨‍🏫 Instructor: {COURSE_CONFIG['instructor']}")
    print(f"🏫 Institution: {COURSE_CONFIG['institution']}")
    print(f"🤖 Tutor: {COURSE_CONFIG['tutor_name']}")
    print(f"📚 Knowledge base: {len(knowledge.knowledge_base)} items")
    print(f"\n🌐 STUDENTS CONNECT TO: {student_url}")
    print("\n⏹️  Press Ctrl+C to stop")
    print("=" * 60 + "\n")
    
    app.run(host='0.0.0.0', port=5004, debug=False, threaded=True)
