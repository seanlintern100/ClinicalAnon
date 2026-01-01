#!/usr/bin/env python3
"""
Convert XLM-RoBERTa NER model to CoreML format.

Usage:
    pip install transformers coremltools torch onnx onnxruntime
    python convert_xlmr_to_coreml.py

Output:
    - XLMRobertaNER.mlpackage (CoreML model)
    - sentencepiece.bpe.model (tokenizer)
    - config.json (label mapping)
"""

import os
import json
import shutil
from pathlib import Path

import torch
import coremltools as ct
from transformers import AutoModelForTokenClassification, AutoTokenizer

# Configuration
MODEL_NAME = "Davlan/xlm-roberta-base-ner-hrl"
OUTPUT_DIR = Path(__file__).parent.parent / "ClinicalAnon" / "Resources" / "BERT"
MAX_SEQ_LENGTH = 512

def main():
    print(f"Loading model: {MODEL_NAME}")

    # Load model and tokenizer
    model = AutoModelForTokenClassification.from_pretrained(MODEL_NAME)
    tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)

    model.eval()

    # Get label mapping
    id2label = model.config.id2label
    print(f"Labels: {id2label}")

    # Create dummy input for tracing
    dummy_text = "John Smith works at Google in New York."
    inputs = tokenizer(
        dummy_text,
        return_tensors="pt",
        max_length=MAX_SEQ_LENGTH,
        padding="max_length",
        truncation=True
    )

    print(f"Input shape: {inputs['input_ids'].shape}")

    # Trace the model
    print("Tracing model...")
    traced_model = torch.jit.trace(
        model,
        (inputs["input_ids"], inputs["attention_mask"]),
        strict=False
    )

    # Convert to CoreML
    print("Converting to CoreML...")

    mlmodel = ct.convert(
        traced_model,
        inputs=[
            ct.TensorType(
                name="input_ids",
                shape=(1, MAX_SEQ_LENGTH),
                dtype=ct.int32
            ),
            ct.TensorType(
                name="attention_mask",
                shape=(1, MAX_SEQ_LENGTH),
                dtype=ct.int32
            ),
        ],
        outputs=[
            ct.TensorType(name="logits")
        ],
        minimum_deployment_target=ct.target.macOS13,
        convert_to="mlprogram",
    )

    # Set metadata
    mlmodel.author = "Converted from Davlan/xlm-roberta-base-ner-hrl"
    mlmodel.short_description = "XLM-RoBERTa NER for 100+ languages"
    mlmodel.version = "1.0"

    # Save CoreML model
    output_path = OUTPUT_DIR / "XLMRobertaNER.mlpackage"
    print(f"Saving to: {output_path}")
    mlmodel.save(str(output_path))

    # Copy tokenizer files
    print("Copying tokenizer files...")
    tokenizer.save_pretrained(str(OUTPUT_DIR / "tokenizer"))

    # The SentencePiece model file
    spm_file = Path(tokenizer.vocab_file)
    if spm_file.exists():
        shutil.copy(spm_file, OUTPUT_DIR / "sentencepiece.bpe.model")
        print(f"Copied: sentencepiece.bpe.model")

    # Save label config
    config = {
        "id2label": id2label,
        "label2id": {v: k for k, v in id2label.items()},
        "max_seq_length": MAX_SEQ_LENGTH,
        "vocab_size": tokenizer.vocab_size,
        "model_type": "xlm-roberta",
        "special_tokens": {
            "cls_token_id": tokenizer.cls_token_id,
            "sep_token_id": tokenizer.sep_token_id,
            "pad_token_id": tokenizer.pad_token_id,
            "unk_token_id": tokenizer.unk_token_id,
        }
    }

    config_path = OUTPUT_DIR / "xlmr_config.json"
    with open(config_path, "w") as f:
        json.dump(config, f, indent=2)
    print(f"Saved config: {config_path}")

    print("\n=== Conversion Complete ===")
    print(f"Model: {output_path}")
    print(f"Config: {config_path}")
    print(f"\nNext steps:")
    print("1. Add XLMRobertaNER.mlpackage to Xcode project")
    print("2. Add sentencepiece.bpe.model to bundle resources")
    print("3. Update BertNERService.swift to use new model")

if __name__ == "__main__":
    main()
