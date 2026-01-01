#!/usr/bin/env python3
"""
Export XLM-RoBERTa SentencePiece vocabulary to JSON for Swift consumption.
"""

import json
from pathlib import Path
import sentencepiece as spm

# Paths
SCRIPT_DIR = Path(__file__).parent
PROJECT_ROOT = SCRIPT_DIR.parent
BERT_DIR = PROJECT_ROOT / "ClinicalAnon" / "Resources" / "BERT"
SPM_MODEL_PATH = BERT_DIR / "sentencepiece.bpe.model"

# Also check tokenizer subdirectory
if not SPM_MODEL_PATH.exists():
    SPM_MODEL_PATH = BERT_DIR / "tokenizer" / "sentencepiece.bpe.model"

OUTPUT_PATH = BERT_DIR / "xlmr_vocab.json"

def main():
    print(f"Loading SentencePiece model from: {SPM_MODEL_PATH}")

    if not SPM_MODEL_PATH.exists():
        print(f"ERROR: SentencePiece model not found at {SPM_MODEL_PATH}")
        return

    # Load SentencePiece model
    sp = spm.SentencePieceProcessor()
    sp.load(str(SPM_MODEL_PATH))

    vocab_size = sp.get_piece_size()
    print(f"Vocabulary size: {vocab_size}")

    # Export vocabulary: piece -> id
    vocab = {}
    for i in range(vocab_size):
        piece = sp.id_to_piece(i)
        vocab[piece] = i

    # Save to JSON
    print(f"Saving vocabulary to: {OUTPUT_PATH}")
    with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
        json.dump(vocab, f, ensure_ascii=False, indent=None)

    # Print some stats
    file_size = OUTPUT_PATH.stat().st_size / (1024 * 1024)
    print(f"Vocabulary exported successfully!")
    print(f"  - File size: {file_size:.2f} MB")
    print(f"  - Total pieces: {len(vocab)}")

    # Show some example pieces
    print("\nSample vocabulary entries:")
    for i in [0, 1, 2, 3, 4, 100, 1000, 10000]:
        if i < vocab_size:
            piece = sp.id_to_piece(i)
            print(f"  [{i}] = '{piece}'")

    # Test tokenization
    print("\nTest tokenization:")
    test_texts = [
        "Hello world",
        "John Smith",
        "José García",
        "张伟",  # Chinese name
        "Krishnamurthy",
    ]

    for text in test_texts:
        pieces = sp.encode_as_pieces(text)
        ids = sp.encode_as_ids(text)
        print(f"  '{text}' -> {pieces} -> {ids}")

if __name__ == "__main__":
    main()
