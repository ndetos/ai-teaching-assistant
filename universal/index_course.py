#!/usr/bin/env python3
"""
index_course.py - Index course materials for AI Tutor
Usage: python3 index_course.py /path/to/course-materials/ -o knowledge_base.pkl
"""

import os
import sys
import pickle
import argparse
import re
from pathlib import Path

# Optional imports with fallbacks
try:
    import PyPDF2
except ImportError:
    PyPDF2 = None

try:
    import docx
except ImportError:
    docx = None


def extract_text_from_pdf(pdf_path):
    """Extract text from PDF file"""
    if not PyPDF2:
        return f"[PDF content from {pdf_path.name}]"
    
    text = []
    try:
        with open(pdf_path, 'rb') as f:
            reader = PyPDF2.PdfReader(f)
            for page in reader.pages:
                page_text = page.extract_text()
                if page_text:
                    text.append(page_text)
    except Exception as e:
        return f"[Could not read PDF: {e}]"
    return '\n'.join(text)


def extract_text_from_docx(docx_path):
    """Extract text from DOCX file"""
    if not docx:
        return f"[DOCX content from {docx_path.name}]"
    
    try:
        doc = docx.Document(docx_path)
        text = [paragraph.text for paragraph in doc.paragraphs]
        return '\n'.join(text)
    except Exception as e:
        return f"[Could not read DOCX: {e}]"


def extract_text_from_file(file_path):
    """Extract text from various file types"""
    ext = file_path.suffix.lower()
    
    if ext == '.pdf':
        return extract_text_from_pdf(file_path)
    elif ext == '.docx':
        return extract_text_from_docx(file_path)
    elif ext in ['.txt', '.md', '.py', '.ipynb', '.html', '.csv', '.json']:
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                return f.read()
        except UnicodeDecodeError:
            with open(file_path, 'r', encoding='latin-1') as f:
                return f.read()
        except Exception as e:
            return f"[Could not read file: {e}]"
    elif ext in ['.ppt', '.pptx']:
        return f"[PowerPoint content from {file_path.name}]"
    else:
        return f"[Content from {file_path.name}]"


def detect_week(filename, content):
    """Try to detect which week the material belongs to"""
    # Look for week patterns in filename or content
    week_patterns = [
        r'[Ww]eek\s*(\d+)',
        r'[Ll]esson\s*(\d+)',
        r'[Cc]hapter\s*(\d+)',
        r'[Mm]odule\s*(\d+)',
        r'[Ll]ecture\s*(\d+)',
        r'[Tt]opic\s*(\d+)',
    ]
    
    for pattern in week_patterns:
        # Check filename
        match = re.search(pattern, filename)
        if match:
            week_num = int(match.group(1))
            if 1 <= week_num <= 52:  # Sanity check
                return week_num
        
        # Check content (first 500 chars)
        match = re.search(pattern, content[:500])
        if match:
            week_num = int(match.group(1))
            if 1 <= week_num <= 52:
                return week_num
    
    return 0  # Unknown week


def chunk_content(content, filename, week, max_chunk_size=1500):
    """Split content into smaller chunks for better retrieval"""
    chunks = []
    
    # First try to split by headings or sections
    sections = re.split(r'\n\s*(?=#+\s|\d+\.\s|[A-Z][A-Z\s]+:)', content)
    
    if len(sections) > 1:
        for section in sections:
            section = section.strip()
            if len(section) > 100:
                chunks.append({
                    'week': week,
                    'source': filename,
                    'type': 'section',
                    'content': section[:2000]
                })
    else:
        # If no clear sections, split by paragraphs
        paragraphs = re.split(r'\n\s*\n+', content)
        current_chunk = ""
        for para in paragraphs:
            para = para.strip()
            if len(para) < 50:
                continue
            if len(current_chunk) + len(para) < max_chunk_size:
                current_chunk += "\n" + para
            else:
                if current_chunk:
                    chunks.append({
                        'week': week,
                        'source': filename,
                        'type': 'chunk',
                        'content': current_chunk.strip()[:2000]
                    })
                current_chunk = para
        
        if current_chunk and len(current_chunk) > 100:
            chunks.append({
                'week': week,
                'source': filename,
                'type': 'chunk',
                'content': current_chunk.strip()[:2000]
            })
    
    return chunks


def index_course_materials(materials_path, output_path, course_info=None):
    """Index all course materials in a directory"""
    materials_path = Path(materials_path)
    knowledge_base = []
    
    if not materials_path.exists():
        print(f"❌ Error: Path '{materials_path}' does not exist")
        return
    
    print(f"📁 Scanning: {materials_path}")
    
    # Supported file extensions
    extensions = ['.pdf', '.docx', '.txt', '.md', '.py', '.ipynb', '.html', '.csv', '.json']
    
    files = []
    for ext in extensions:
        files.extend(materials_path.glob(f'*{ext}'))
        files.extend(materials_path.glob(f'*{ext.upper()}'))
    
    if not files:
        print("⚠️  No supported files found!")
        print(f"   Supported formats: {', '.join(extensions)}")
        return
    
    print(f"📄 Found {len(files)} files to process...")
    
    # Add course info as a knowledge item
    if course_info:
        knowledge_base.append({
            'week': 0,
            'source': 'course_info',
            'type': 'metadata',
            'content': f"Course: {course_info.get('course_code', 'Unknown')} - {course_info.get('course_name', 'Unknown')}\nInstructor: {course_info.get('instructor', 'Unknown')}\nInstitution: {course_info.get('institution', 'Unknown')}"
        })
    
    for i, file_path in enumerate(files, 1):
        print(f"   [{i}/{len(files)}] Processing: {file_path.name}")
        
        # Extract text content
        try:
            content = extract_text_from_file(file_path)
        except Exception as e:
            print(f"      ⚠️  Error reading file: {e}")
            continue
        
        # Detect week
        week = detect_week(file_path.name, content)
        
        # Skip if no content
        if not content or len(content) < 50:
            print(f"      ⚠️  Skipping (insufficient content)")
            continue
        
        # Add the full file as one entry
        knowledge_base.append({
            'week': week,
            'source': file_path.name,
            'type': 'document',
            'content': content[:3000],
            'filename': str(file_path)
        })
        
        # Also add chunks for better retrieval
        chunks = chunk_content(content, file_path.name, week)
        knowledge_base.extend(chunks)
    
    # Save the knowledge base
    with open(output_path, 'wb') as f:
        pickle.dump(knowledge_base, f)
    
    # Show summary
    weeks = {}
    for item in knowledge_base:
        w = item.get('week', 0)
        weeks[w] = weeks.get(w, 0) + 1
    
    print(f"\n✅ Indexed {len(knowledge_base)} items from {len(files)} files")
    print(f"   Weeks: {', '.join(f'Week {w}({c})' for w, c in sorted(weeks.items()))}")
    print(f"📚 Saved to: {output_path}")


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Index course materials for AI Tutor')
    parser.add_argument('materials_path', help='Path to course materials directory')
    parser.add_argument('-o', '--output', default='knowledge_base.pkl', 
                        help='Output file path for knowledge base')
    parser.add_argument('--course-code', help='Course code (e.g., CIT 4104)')
    parser.add_argument('--course-name', help='Course name (e.g., Modeling and Simulation)')
    parser.add_argument('--instructor', help='Instructor name')
    parser.add_argument('--institution', help='Institution name')
    
    args = parser.parse_args()
    
    course_info = {}
    if args.course_code:
        course_info['course_code'] = args.course_code
    if args.course_name:
        course_info['course_name'] = args.course_name
    if args.instructor:
        course_info['instructor'] = args.instructor
    if args.institution:
        course_info['institution'] = args.institution
    
    index_course_materials(args.materials_path, args.output, course_info)
