#!/usr/bin/env python3
"""
index_course.py - Index course materials with sentence-transformers + faiss-cpu
Usage: python3 index_course.py /path/to/course-materials/ -o knowledge_base.pkl
"""

import os
import sys
import re
import pickle
import argparse
from pathlib import Path

# Import sentence-transformers (will download all-MiniLM-L6-v2 on first use)
try:
    from sentence_transformers import SentenceTransformer
except ImportError:
    print("❌ sentence-transformers not installed. Run: pip install sentence-transformers")
    sys.exit(1)

try:
    import numpy as np
except ImportError:
    print("❌ numpy not installed. Run: pip install numpy")
    sys.exit(1)

try:
    import faiss
except ImportError:
    print("❌ faiss-cpu not installed. Run: pip install faiss-cpu")
    sys.exit(1)

# Optional imports for file parsing
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
    week_patterns = [
        r'[Ww]eek\s*(\d+)',
        r'[Ll]esson\s*(\d+)',
        r'[Cc]hapter\s*(\d+)',
        r'[Mm]odule\s*(\d+)',
        r'[Ll]ecture\s*(\d+)',
        r'[Tt]opic\s*(\d+)',
    ]
    
    for pattern in week_patterns:
        match = re.search(pattern, filename)
        if match:
            week_num = int(match.group(1))
            if 1 <= week_num <= 52:
                return week_num
        
        match = re.search(pattern, content[:500])
        if match:
            week_num = int(match.group(1))
            if 1 <= week_num <= 52:
                return week_num
    
    return 0


def chunk_content(content, filename, week, max_chunk_size=1500):
    """Split content into smaller chunks for better retrieval"""
    chunks = []
    chunk_metadata = []
    
    # Try to split by headings or sections
    sections = re.split(r'\n\s*(?=#+\s|\d+\.\s|[A-Z][A-Z\s]+:)', content)
    
    if len(sections) > 1:
        for section in sections:
            section = section.strip()
            if len(section) > 100:
                chunks.append(section[:2000])
                chunk_metadata.append({
                    'week': week,
                    'source': filename,
                    'type': 'section'
                })
    else:
        # Split by paragraphs
        paragraphs = re.split(r'\n\s*\n+', content)
        current_chunk = ""
        for para in paragraphs:
            para = para.strip()
            if len(para) < 50:
                continue
            if len(current_chunk) + len(para) < max_chunk_size:
                current_chunk += "\n" + para
            else:
                if current_chunk and len(current_chunk) > 100:
                    chunks.append(current_chunk.strip()[:2000])
                    chunk_metadata.append({
                        'week': week,
                        'source': filename,
                        'type': 'chunk'
                    })
                current_chunk = para
        
        if current_chunk and len(current_chunk) > 100:
            chunks.append(current_chunk.strip()[:2000])
            chunk_metadata.append({
                'week': week,
                'source': filename,
                'type': 'chunk'
            })
    
    return chunks, chunk_metadata


def index_course_materials(materials_path, output_path, course_info=None):
    """Index course materials using sentence-transformers + faiss-cpu"""
    materials_path = Path(materials_path)
    
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
    
    # Store all chunks and metadata
    all_chunks = []
    all_metadata = []
    file_count = 0
    
    # Process each file
    for i, file_path in enumerate(files, 1):
        print(f"   [{i}/{len(files)}] Processing: {file_path.name}")
        
        try:
            content = extract_text_from_file(file_path)
        except Exception as e:
            print(f"      ⚠️  Error reading file: {e}")
            continue
        
        if not content or len(content) < 50:
            print(f"      ⚠️  Skipping (insufficient content)")
            continue
        
        week = detect_week(file_path.name, content)
        file_count += 1
        
        # Chunk the content
        chunks, metadata = chunk_content(content, file_path.name, week)
        
        # Also add the full document as one entry
        chunks.append(content[:3000])
        metadata.append({
            'week': week,
            'source': file_path.name,
            'type': 'document'
        })
        
        all_chunks.extend(chunks)
        all_metadata.extend(metadata)
    
    if not all_chunks:
        print("❌ No content extracted from files")
        return
    
    print(f"\n🧠 Generating embeddings for {len(all_chunks)} chunks...")
    print("   ⏳ This will download ~420 MB model on first run")
    
    # Load the embedding model (downloads all-MiniLM-L6-v2 on first use)
    model = SentenceTransformer('all-MiniLM-L6-v2')
    
    # Create embeddings for all chunks
    embeddings = model.encode(all_chunks, show_progress_bar=True)
    
    print(f"🏗️  Building FAISS index...")
    dimension = embeddings.shape[1]
    index = faiss.IndexFlatL2(dimension)
    index.add(embeddings.astype('float32'))
    
    # Save everything
    data = {
        'chunks': all_chunks,
        'metadata': all_metadata,
        'embeddings': embeddings,
        'index': index,
        'model_name': 'all-MiniLM-L6-v2',
        'course_info': course_info
    }
    
    with open(output_path, 'wb') as f:
        pickle.dump(data, f)
    
    # Show summary
    weeks = {}
    for meta in all_metadata:
        w = meta.get('week', 0)
        weeks[w] = weeks.get(w, 0) + 1
    
    print(f"\n✅ Indexed {len(all_chunks)} chunks from {file_count} files")
    print(f"   Weeks: {', '.join(f'Week {w}({c})' for w, c in sorted(weeks.items()))}")
    print(f"📚 Saved to: {output_path}")
    print(f"🔍 Model: all-MiniLM-L6-v2 (semantic search)")


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Index course materials with semantic search')
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
