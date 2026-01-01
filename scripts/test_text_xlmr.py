#!/usr/bin/env python3
"""
Test XLM-R NER on provided text.
Usage: python3 scripts/test_text_xlmr.py "Your text here"
"""

import sys
import json
import numpy as np
from pathlib import Path

BERT_DIR = Path(__file__).parent.parent / "ClinicalAnon" / "Resources" / "BERT"
MODEL_PATH = BERT_DIR / "XLMRobertaNER.mlpackage"
VOCAB_PATH = BERT_DIR / "xlmr_vocab.json"

ID2LABEL = {0: "O", 1: "B-DATE", 2: "I-DATE", 3: "B-PER", 4: "I-PER", 5: "B-ORG", 6: "I-ORG", 7: "B-LOC", 8: "I-LOC"}
CLS_ID, SEP_ID, PAD_ID = 0, 2, 1
MAX_LEN = 512

def load_vocab():
    with open(VOCAB_PATH, "r", encoding="utf-8") as f:
        return json.load(f)

def tokenize(text, vocab):
    prefix = "▁"
    unk_id = vocab.get("<unk>", 3)
    input_ids = [CLS_ID]
    token_to_char = [(-1, -1)]

    i = 0
    while i < len(text):
        if text[i].isspace():
            i += 1
            continue
        # Find word end
        j = i
        while j < len(text) and not text[j].isspace():
            j += 1
        word = text[i:j]
        word_start = i

        # Tokenize word
        remaining = word
        offset = word_start
        is_first = True
        while remaining:
            prefixed = (prefix + remaining) if is_first else remaining
            found = False
            for length in range(len(prefixed), 0, -1):
                candidate = prefixed[:length]
                if candidate in vocab:
                    actual_len = (length - 1) if is_first else length
                    input_ids.append(vocab[candidate])
                    token_to_char.append((offset, offset + actual_len))
                    remaining = remaining[actual_len:] if actual_len > 0 else ""
                    offset += actual_len
                    is_first = False
                    found = True
                    break
            if not found:
                char = remaining[0]
                char_piece = (prefix + char) if is_first else char
                input_ids.append(vocab.get(char_piece, vocab.get(char, unk_id)))
                token_to_char.append((offset, offset + 1))
                remaining = remaining[1:]
                offset += 1
                is_first = False
            if len(input_ids) >= MAX_LEN - 1:
                break
        i = j
        if len(input_ids) >= MAX_LEN - 1:
            break

    input_ids.append(SEP_ID)
    token_to_char.append((-1, -1))
    attention_mask = [1] * len(input_ids) + [0] * (MAX_LEN - len(input_ids))
    input_ids = input_ids + [PAD_ID] * (MAX_LEN - len(input_ids))
    token_to_char = token_to_char + [(-1, -1)] * (MAX_LEN - len(token_to_char))
    return input_ids[:MAX_LEN], attention_mask[:MAX_LEN], token_to_char[:MAX_LEN]

def run_ner(text):
    import coremltools as ct

    vocab = load_vocab()
    model = ct.models.MLModel(str(MODEL_PATH))

    input_ids, attention_mask, token_to_char = tokenize(text, vocab)

    output = model.predict({
        "input_ids": np.array([input_ids], dtype=np.int32),
        "attention_mask": np.array([attention_mask], dtype=np.int32)
    })

    logits = output["logits"]
    predictions = np.argmax(logits[0], axis=-1)

    # Extract entities
    entities = []
    current = None
    for i, pred in enumerate(predictions):
        if attention_mask[i] == 0:
            break
        label = ID2LABEL.get(pred, "O")
        char_start, char_end = token_to_char[i]

        if label.startswith("B-"):
            if current:
                entities.append(current)
            entity_type = label[2:]
            current = {"type": entity_type, "start": char_start, "end": char_end, "text": text[char_start:char_end] if char_start >= 0 else ""}
        elif label.startswith("I-") and current:
            if char_end > 0:
                current["end"] = char_end
                current["text"] = text[current["start"]:char_end]
        else:
            if current:
                entities.append(current)
                current = None
    if current:
        entities.append(current)

    return entities

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 scripts/test_text_xlmr.py \"Your text here\"")
        sys.exit(1)

    text = sys.argv[1]
    print(f"Text: {text}\n")

    entities = run_ner(text)

    if entities:
        print("Entities found:")
        for e in entities:
            print(f"  [{e['type']}] \"{e['text']}\" (chars {e['start']}-{e['end']})")
    else:
        print("No entities found.")
