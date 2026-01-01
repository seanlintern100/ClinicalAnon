#!/usr/bin/env python3
"""
Convert XLM-RoBERTa NER model to CoreML format.
"""

import os
import json
import shutil
import ssl
from pathlib import Path

# Disable SSL verification globally (for Zscaler)
ssl._create_default_https_context = ssl._create_unverified_context
os.environ['CURL_CA_BUNDLE'] = ''
os.environ['REQUESTS_CA_BUNDLE'] = ''
os.environ['HF_HUB_DISABLE_SSL_VERIFY'] = '1'

# Monkey-patch requests to disable SSL verification
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.ssl_ import create_urllib3_context

class SSLAdapter(HTTPAdapter):
    def init_poolmanager(self, *args, **kwargs):
        ctx = create_urllib3_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        kwargs['ssl_context'] = ctx
        return super().init_poolmanager(*args, **kwargs)

# Patch the default session
old_request = requests.Session.request
def new_request(self, *args, **kwargs):
    kwargs['verify'] = False
    return old_request(self, *args, **kwargs)
requests.Session.request = new_request

# Also patch urllib3
import urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# Now import the ML libraries
import numpy as np
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
    # Use slow tokenizer to avoid fast tokenizer bugs
    tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME, use_fast=False)

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

    # Wrap model to only return logits tensor
    class LogitsOnlyWrapper(torch.nn.Module):
        def __init__(self, model):
            super().__init__()
            self.model = model

        def forward(self, input_ids, attention_mask):
            outputs = self.model(input_ids=input_ids, attention_mask=attention_mask)
            return outputs.logits

    wrapped_model = LogitsOnlyWrapper(model)
    wrapped_model.eval()

    # Trace the model
    print("Tracing model...")
    traced_model = torch.jit.trace(
        wrapped_model,
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
                dtype=np.int32
            ),
            ct.TensorType(
                name="attention_mask",
                shape=(1, MAX_SEQ_LENGTH),
                dtype=np.int32
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

    # Ensure output directory exists
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    # Save CoreML model
    output_path = OUTPUT_DIR / "XLMRobertaNER.mlpackage"
    print(f"Saving to: {output_path}")
    mlmodel.save(str(output_path))

    # Copy tokenizer files
    print("Copying tokenizer files...")
    tokenizer_dir = OUTPUT_DIR / "tokenizer"
    tokenizer.save_pretrained(str(tokenizer_dir))

    # The SentencePiece model file
    if hasattr(tokenizer, 'vocab_file') and tokenizer.vocab_file:
        spm_file = Path(tokenizer.vocab_file)
        if spm_file.exists():
            shutil.copy(spm_file, OUTPUT_DIR / "sentencepiece.bpe.model")
            print(f"Copied: sentencepiece.bpe.model")

    # Save label config
    config = {
        "id2label": {str(k): v for k, v in id2label.items()},
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
