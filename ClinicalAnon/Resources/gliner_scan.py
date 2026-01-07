#!/usr/bin/env python3
"""
GLiNER PII Scanner
Runs GLiNER model to detect PII entities in text.
Called as subprocess from Swift app.

Usage:
    python gliner_scan.py --text "John Smith called from 415-555-1234"

Or via stdin:
    echo '{"text": "...", "labels": [...]}' | python gliner_scan.py --stdin

Output: JSON array of entities
"""

import sys
import os
import json
import argparse
import ssl
import certifi
from typing import List, Dict

# Fix SSL certificates for PyInstaller bundle
os.environ['SSL_CERT_FILE'] = certifi.where()
os.environ['REQUESTS_CA_BUNDLE'] = certifi.where()

# Default PII labels for GLiNER
DEFAULT_LABELS = [
    "person",
    "organization",
    "phone number",
    "email",
    "address",
    "date of birth",
    "social security number",
    "credit card number",
    "bank account number",
    "passport number",
    "driver license number",
    "health insurance id",
    "medical record number",
    "ip address",
    "url",
    "username",
    "password"
]

def get_model_cache_path():
    """Get the path where the model should be cached"""
    # Get directory containing this script
    script_dir = os.path.dirname(os.path.abspath(__file__))

    # Check multiple locations for the model
    cache_paths = [
        # Bundled with the Python bundle (same directory as script)
        os.path.join(script_dir, 'gliner_model'),
        # Bundled with PyInstaller binary (check _MEIPASS first)
        os.path.join(getattr(sys, '_MEIPASS', ''), 'gliner_model'),
        # User's cache directory (Swift app will put it here)
        os.path.expanduser("~/Library/Caches/GLiNER/gliner_model"),
        # Fallback to HuggingFace cache
        os.path.expanduser("~/.cache/huggingface/hub/models--knowledgator--gliner-pii-base-v1.0"),
    ]
    for path in cache_paths:
        if os.path.exists(path) and os.path.isdir(path):
            # Verify model files exist
            if os.path.exists(os.path.join(path, 'pytorch_model.bin')) or \
               os.path.exists(os.path.join(path, 'model.safetensors')):
                return path
    return None


# Global model cache
_model = None

def scan_text(text: str, labels: List[str] = None, threshold: float = 0.5) -> List[Dict]:
    """
    Scan text for PII using GLiNER.

    Args:
        text: The text to scan
        labels: Entity labels to search for (default: DEFAULT_LABELS)
        threshold: Confidence threshold (default: 0.5)

    Returns:
        List of entity dictionaries with text, label, start, end, confidence
    """
    global _model
    from gliner import GLiNER

    if labels is None:
        labels = DEFAULT_LABELS

    # Load model (cached after first load)
    if _model is None:
        cache_path = get_model_cache_path()
        if cache_path:
            print(f"Loading model from cache: {cache_path}", file=sys.stderr)
            _model = GLiNER.from_pretrained(cache_path, local_files_only=True)
        else:
            print("Downloading model from HuggingFace...", file=sys.stderr)
            try:
                _model = GLiNER.from_pretrained("knowledgator/gliner-pii-base-v1.0")
            except Exception as e:
                # Try with SSL verification disabled as last resort
                import urllib3
                urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
                os.environ['CURL_CA_BUNDLE'] = ''
                _model = GLiNER.from_pretrained("knowledgator/gliner-pii-base-v1.0")

    # Run prediction
    entities = _model.predict_entities(text, labels, threshold=threshold)

    # Format output
    results = []
    for entity in entities:
        results.append({
            "text": entity["text"],
            "label": entity["label"],
            "start": entity["start"],
            "end": entity["end"],
            "confidence": float(entity["score"])
        })

    return results


def main():
    parser = argparse.ArgumentParser(description="GLiNER PII Scanner")
    parser.add_argument("--text", type=str, help="Text to scan")
    parser.add_argument("--stdin", action="store_true", help="Read JSON from stdin")
    parser.add_argument("--threshold", type=float, default=0.5, help="Confidence threshold")
    parser.add_argument("--labels", type=str, help="Comma-separated list of labels")

    args = parser.parse_args()

    if args.stdin:
        # Read JSON from stdin
        input_data = json.loads(sys.stdin.read())
        text = input_data.get("text", "")
        labels = input_data.get("labels", DEFAULT_LABELS)
        threshold = input_data.get("threshold", args.threshold)
    elif args.text:
        text = args.text
        labels = args.labels.split(",") if args.labels else DEFAULT_LABELS
        threshold = args.threshold
    else:
        parser.print_help()
        sys.exit(1)

    try:
        entities = scan_text(text, labels, threshold)
        print(json.dumps(entities))
    except Exception as e:
        print(json.dumps({"error": str(e)}), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
