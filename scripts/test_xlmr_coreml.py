#!/usr/bin/env python3
"""
Test XLM-RoBERTa CoreML model directly to diagnose prediction issues.
"""

import os
import json
import numpy as np
from pathlib import Path

# Configuration
SCRIPT_DIR = Path(__file__).parent
PROJECT_ROOT = SCRIPT_DIR.parent
BERT_DIR = PROJECT_ROOT / "ClinicalAnon" / "Resources" / "BERT"
MODEL_PATH = BERT_DIR / "XLMRobertaNER.mlpackage"
VOCAB_PATH = BERT_DIR / "xlmr_vocab.json"
CONFIG_PATH = BERT_DIR / "xlmr_config.json"

# Label mapping
ID2LABEL = {
    0: "O",
    1: "B-DATE",
    2: "I-DATE",
    3: "B-PER",
    4: "I-PER",
    5: "B-ORG",
    6: "I-ORG",
    7: "B-LOC",
    8: "I-LOC"
}

# Special tokens for XLM-R
CLS_TOKEN_ID = 0   # <s>
SEP_TOKEN_ID = 2   # </s>
PAD_TOKEN_ID = 1   # <pad>
MAX_SEQ_LENGTH = 512

def load_vocab():
    """Load the vocabulary JSON."""
    print(f"Loading vocabulary from: {VOCAB_PATH}")
    with open(VOCAB_PATH, "r", encoding="utf-8") as f:
        vocab = json.load(f)
    print(f"Loaded {len(vocab)} vocabulary entries")
    return vocab

def simple_tokenize(text, vocab, max_length=512):
    """Simple BPE tokenization matching Swift implementation."""
    word_prefix = "▁"  # Unicode U+2581
    unk_id = vocab.get("<unk>", 0)

    input_ids = [CLS_TOKEN_ID]
    token_to_char = [(-1, -1)]  # CLS has no char mapping

    words = []
    char_offset = 0
    current_word_start = -1
    current_word = ""

    # Split into words and track positions
    for i, char in enumerate(text):
        if char.isspace():
            if current_word:
                words.append((current_word, current_word_start, i))
                current_word = ""
                current_word_start = -1
        else:
            if current_word_start == -1:
                current_word_start = i
            current_word += char

    if current_word:
        words.append((current_word, current_word_start, len(text)))

    # Tokenize each word
    for word, word_start, word_end in words:
        remaining = word
        current_offset = word_start
        is_first = True

        while remaining:
            # For first subword, try with ▁ prefix
            prefixed = (word_prefix + remaining) if is_first else remaining

            found = False
            # Try longest to shortest
            for length in range(len(prefixed), 0, -1):
                candidate = prefixed[:length]
                if candidate in vocab:
                    token_id = vocab[candidate]
                    actual_length = (length - 1) if is_first else length

                    input_ids.append(token_id)
                    token_to_char.append((current_offset, current_offset + actual_length))

                    if actual_length > 0:
                        remaining = remaining[actual_length:]
                        current_offset += actual_length
                    else:
                        remaining = ""

                    is_first = False
                    found = True
                    break

            if not found:
                # Use UNK for first character
                char_piece = (word_prefix + remaining[0]) if is_first else remaining[0]
                token_id = vocab.get(char_piece, vocab.get(remaining[0], unk_id))

                input_ids.append(token_id)
                token_to_char.append((current_offset, current_offset + 1))

                remaining = remaining[1:]
                current_offset += 1
                is_first = False

        if len(input_ids) >= max_length - 1:
            break

    # Add SEP token
    input_ids.append(SEP_TOKEN_ID)
    token_to_char.append((-1, -1))

    # Pad to max length
    attention_mask = [1] * len(input_ids) + [0] * (max_length - len(input_ids))
    input_ids = input_ids + [PAD_TOKEN_ID] * (max_length - len(input_ids))
    token_to_char = token_to_char + [(-1, -1)] * (max_length - len(token_to_char))

    return input_ids[:max_length], attention_mask[:max_length], token_to_char[:max_length]

def test_with_transformers():
    """Test using HuggingFace transformers as baseline."""
    print("\n=== Testing with HuggingFace Transformers (baseline) ===")

    try:
        from transformers import AutoModelForTokenClassification, AutoTokenizer
        import torch

        model_name = "Davlan/xlm-roberta-base-ner-hrl"
        print(f"Loading model: {model_name}")

        model = AutoModelForTokenClassification.from_pretrained(model_name)
        tokenizer = AutoTokenizer.from_pretrained(model_name)
        model.eval()

        # Test texts
        test_texts = [
            "John Smith lives in New York.",
            "Dr. Praneer Patel works at Stanford Hospital.",
            "The patient Zhang Wei was referred by Dr. Garcia.",
        ]

        for text in test_texts:
            print(f"\nText: '{text}'")

            inputs = tokenizer(text, return_tensors="pt", padding="max_length", max_length=512, truncation=True)

            with torch.no_grad():
                outputs = model(**inputs)

            logits = outputs.logits
            predictions = torch.argmax(logits, dim=-1)[0]

            # Decode tokens and show predictions
            tokens = tokenizer.convert_ids_to_tokens(inputs["input_ids"][0])

            print("Predictions:")
            for i, (token, pred) in enumerate(zip(tokens, predictions)):
                if token in ["<s>", "</s>", "<pad>"]:
                    continue
                label = ID2LABEL.get(pred.item(), f"UNK({pred.item()})")
                if label != "O":
                    print(f"  [{i}] {token} -> {label}")

            # Show extracted entities
            print("Entities found by HuggingFace:")
            current_entity = None
            for i, (token, pred) in enumerate(zip(tokens, predictions)):
                label = ID2LABEL.get(pred.item(), "O")
                if label.startswith("B-"):
                    if current_entity:
                        print(f"  - {current_entity['type']}: '{current_entity['text']}'")
                    current_entity = {"type": label[2:], "text": token.replace("▁", " ").strip()}
                elif label.startswith("I-") and current_entity:
                    current_entity["text"] += token.replace("▁", " ")
                else:
                    if current_entity:
                        print(f"  - {current_entity['type']}: '{current_entity['text']}'")
                        current_entity = None
            if current_entity:
                print(f"  - {current_entity['type']}: '{current_entity['text']}'")

    except ImportError:
        print("transformers not installed. Skipping baseline test.")
        print("Install with: pip install transformers torch")
    except Exception as e:
        print(f"Error: {e}")

def test_with_coreml():
    """Test using CoreML model."""
    print("\n=== Testing with CoreML Model ===")

    try:
        import coremltools as ct

        print(f"Loading CoreML model from: {MODEL_PATH}")
        if not MODEL_PATH.exists():
            print(f"ERROR: Model not found at {MODEL_PATH}")
            return

        model = ct.models.MLModel(str(MODEL_PATH))
        print(f"Model loaded successfully")

        # Check model spec
        spec = model.get_spec()
        print(f"Model type: {spec.WhichOneof('Type')}")

        # Print input/output info
        print("\nInputs:")
        for inp in spec.description.input:
            print(f"  - {inp.name}: {inp.type}")

        print("\nOutputs:")
        for out in spec.description.output:
            print(f"  - {out.name}: {out.type}")

        # Load vocab
        vocab = load_vocab()

        # Test texts
        test_texts = [
            "John Smith lives in New York.",
            "Dr. Praneer Patel works at Stanford Hospital.",
            "The patient Zhang Wei was referred by Dr. Garcia.",
        ]

        for text in test_texts:
            print(f"\n--- Text: '{text}' ---")

            # Tokenize
            input_ids, attention_mask, token_to_char = simple_tokenize(text, vocab)

            # Show first 20 tokens
            print("\nTokens (first 20):")
            reverse_vocab = {v: k for k, v in vocab.items()}
            for i in range(min(20, len(input_ids))):
                if input_ids[i] == PAD_TOKEN_ID:
                    break
                token = reverse_vocab.get(input_ids[i], f"<id:{input_ids[i]}>")
                char_range = token_to_char[i]
                print(f"  [{i}] id={input_ids[i]:6d} '{token}' chars={char_range}")

            # Create numpy arrays
            input_ids_np = np.array([input_ids], dtype=np.int32)
            attention_mask_np = np.array([attention_mask], dtype=np.int32)

            # Run inference
            print("\nRunning CoreML inference...")
            output = model.predict({
                "input_ids": input_ids_np,
                "attention_mask": attention_mask_np
            })

            # Get logits
            logits = output["logits"]
            print(f"Logits shape: {logits.shape}")
            print(f"Logits dtype: {logits.dtype}")

            # Get predictions
            predictions = np.argmax(logits[0], axis=-1)  # Shape: [seq_len]
            num_tokens = sum(1 for m in attention_mask if m == 1)

            # Show raw logits for first 10 non-padding tokens
            print("\nRaw logits for first 10 tokens:")
            print("  Tok  |     O   |  B-DATE |  I-DATE |  B-PER  |  I-PER  |  B-ORG  |  I-ORG  |  B-LOC  |  I-LOC  | Pred")
            print("  " + "-" * 110)
            for i in range(min(15, num_tokens)):
                token_logits = logits[0, i]
                pred_idx = predictions[i]
                pred_label = ID2LABEL.get(pred_idx, "?")
                token = reverse_vocab.get(input_ids[i], f"<{input_ids[i]}>")[:8].ljust(8)
                logit_str = " | ".join([f"{l:7.3f}" for l in token_logits])
                print(f"  {token} | {logit_str} | {pred_label}")

            # Show predictions for non-padding tokens
            print("\nPredictions (non-O only):")
            for i in range(num_tokens):
                pred = predictions[i]
                label = ID2LABEL.get(pred, f"UNK({pred})")
                if label != "O" and i < len(token_to_char):
                    token = reverse_vocab.get(input_ids[i], f"<id:{input_ids[i]}>")
                    char_range = token_to_char[i]

                    # Get raw logits for this token
                    token_logits = logits[0, i]
                    max_logit = token_logits[pred]
                    o_logit = token_logits[0]

                    print(f"  [{i}] {token} -> {label} (logit={max_logit:.3f}, O_logit={o_logit:.3f}, diff={max_logit-o_logit:.3f})")

            # Show aggregated entities
            print("\nEntities found by CoreML:")
            current_entity = None
            current_text = ""
            for i in range(num_tokens):
                pred = predictions[i]
                label = ID2LABEL.get(pred, "O")
                token = reverse_vocab.get(input_ids[i], "")

                if label.startswith("B-"):
                    if current_entity:
                        print(f"  - {current_entity}: '{current_text.strip()}'")
                    current_entity = label[2:]
                    current_text = token.replace("▁", " ")
                elif label.startswith("I-") and current_entity:
                    current_text += token.replace("▁", " ")
                else:
                    if current_entity:
                        print(f"  - {current_entity}: '{current_text.strip()}'")
                        current_entity = None
                        current_text = ""
            if current_entity:
                print(f"  - {current_entity}: '{current_text.strip()}'")

    except ImportError:
        print("coremltools not installed. Install with: pip install coremltools")
    except Exception as e:
        import traceback
        print(f"Error: {e}")
        traceback.print_exc()

def main():
    print("=" * 60)
    print("XLM-RoBERTa NER Model Test")
    print("=" * 60)

    # First test with HuggingFace to establish baseline
    test_with_transformers()

    # Then test with CoreML
    test_with_coreml()

    print("\n" + "=" * 60)
    print("Test Complete")
    print("=" * 60)

if __name__ == "__main__":
    main()
