#!/usr/bin/env python3
"""
Re-convert XLM-RoBERTa NER model to CoreML using cached files.
Fixes tokenizer vocabulary mismatch.
"""

import json
import numpy as np
import torch
from pathlib import Path

# Find cached model
CACHE_DIR = Path.home() / ".cache/huggingface/hub/models--Davlan--xlm-roberta-base-ner-hrl/snapshots"
OUTPUT_DIR = Path(__file__).parent.parent / "ClinicalAnon" / "Resources" / "BERT"
MAX_SEQ_LENGTH = 512

def main():
    # Find the cached snapshot
    snapshots = list(CACHE_DIR.iterdir())
    if not snapshots:
        print("ERROR: No cached model found!")
        return

    model_dir = snapshots[0]
    print(f"Using cached model: {model_dir}")

    # Load model and tokenizer from cache (no network needed)
    from transformers import XLMRobertaForTokenClassification, XLMRobertaTokenizerFast

    print("Loading model from cache...")
    model = XLMRobertaForTokenClassification.from_pretrained(str(model_dir), local_files_only=True)
    model.eval()

    print("Loading tokenizer from cache...")
    tokenizer = XLMRobertaTokenizerFast.from_pretrained(str(model_dir), local_files_only=True)

    # Get config
    config = model.config
    print(f"Model config: {config.num_labels} labels")
    print(f"id2label: {config.id2label}")

    # ===== FIX 1: Export correct vocabulary =====
    print("\n=== Exporting correct vocabulary ===")

    # Get the full vocabulary from the tokenizer
    vocab = tokenizer.get_vocab()
    print(f"Tokenizer vocab size: {len(vocab)}")

    # Verify special tokens
    print(f"Special tokens:")
    print(f"  <s> (CLS): {tokenizer.cls_token_id}")
    print(f"  </s> (SEP): {tokenizer.sep_token_id}")
    print(f"  <pad>: {tokenizer.pad_token_id}")
    print(f"  <unk>: {tokenizer.unk_token_id}")

    # Save vocabulary
    vocab_path = OUTPUT_DIR / "xlmr_vocab.json"
    print(f"Saving vocabulary to: {vocab_path}")
    with open(vocab_path, "w", encoding="utf-8") as f:
        json.dump(vocab, f, ensure_ascii=False)
    print(f"Saved {len(vocab)} vocabulary entries")

    # ===== FIX 2: Re-convert model to CoreML =====
    print("\n=== Converting model to CoreML ===")

    import coremltools as ct

    # Create dummy input
    dummy_text = "John Smith lives in New York."
    inputs = tokenizer(
        dummy_text,
        return_tensors="pt",
        max_length=MAX_SEQ_LENGTH,
        padding="max_length",
        truncation=True
    )

    print(f"Dummy input shape: {inputs['input_ids'].shape}")
    print(f"Dummy tokens: {tokenizer.convert_ids_to_tokens(inputs['input_ids'][0][:10])}")

    # Test PyTorch model first
    print("\nTesting PyTorch model...")
    with torch.no_grad():
        outputs = model(**inputs)
    logits = outputs.logits[0]

    print("PyTorch predictions for first 8 tokens:")
    for i in range(8):
        token = tokenizer.convert_ids_to_tokens([inputs['input_ids'][0][i].item()])[0]
        pred = torch.argmax(logits[i]).item()
        label = config.id2label[pred]
        print(f"  {token}: {label}")

    # Wrap model to only return logits
    class LogitsWrapper(torch.nn.Module):
        def __init__(self, model):
            super().__init__()
            self.model = model

        def forward(self, input_ids, attention_mask):
            outputs = self.model(input_ids=input_ids, attention_mask=attention_mask)
            return outputs.logits

    wrapped = LogitsWrapper(model)
    wrapped.eval()

    # Trace the model
    print("\nTracing model...")
    with torch.no_grad():
        traced = torch.jit.trace(
            wrapped,
            (inputs["input_ids"], inputs["attention_mask"]),
            strict=False
        )

    # Test traced model
    print("Testing traced model...")
    with torch.no_grad():
        traced_output = traced(inputs["input_ids"], inputs["attention_mask"])

    print("Traced model output shape:", traced_output.shape)
    print("Traced predictions for first 8 tokens:")
    for i in range(8):
        token = tokenizer.convert_ids_to_tokens([inputs['input_ids'][0][i].item()])[0]
        pred = torch.argmax(traced_output[0][i]).item()
        label = config.id2label[pred]
        print(f"  {token}: {label}")

    # Verify traced model matches original
    diff = torch.abs(logits - traced_output[0]).max().item()
    print(f"Max difference between original and traced: {diff}")
    if diff > 0.001:
        print("WARNING: Traced model differs from original!")

    # Convert to CoreML
    print("\nConverting to CoreML...")
    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.TensorType(name="input_ids", shape=(1, MAX_SEQ_LENGTH), dtype=np.int32),
            ct.TensorType(name="attention_mask", shape=(1, MAX_SEQ_LENGTH), dtype=np.int32),
        ],
        outputs=[
            ct.TensorType(name="logits", dtype=np.float32)
        ],
        minimum_deployment_target=ct.target.macOS13,
        convert_to="mlprogram",
    )

    # Set metadata
    mlmodel.author = "Re-converted from Davlan/xlm-roberta-base-ner-hrl"
    mlmodel.short_description = "XLM-RoBERTa NER for multilingual named entity recognition"
    mlmodel.version = "2.0"

    # Save model
    output_path = OUTPUT_DIR / "XLMRobertaNER.mlpackage"
    print(f"\nSaving to: {output_path}")

    # Remove old model if exists
    import shutil
    if output_path.exists():
        shutil.rmtree(output_path)

    mlmodel.save(str(output_path))
    print("Model saved!")

    # ===== FIX 3: Test CoreML model =====
    print("\n=== Testing CoreML model ===")

    # Load and test
    loaded_model = ct.models.MLModel(str(output_path))

    input_ids_np = inputs["input_ids"].numpy().astype(np.int32)
    attention_mask_np = inputs["attention_mask"].numpy().astype(np.int32)

    coreml_output = loaded_model.predict({
        "input_ids": input_ids_np,
        "attention_mask": attention_mask_np
    })

    coreml_logits = coreml_output["logits"]
    print(f"CoreML output shape: {coreml_logits.shape}")

    print("\nCoreML predictions for first 8 tokens:")
    for i in range(8):
        token = tokenizer.convert_ids_to_tokens([inputs['input_ids'][0][i].item()])[0]
        pred = np.argmax(coreml_logits[0, i])
        label = config.id2label[pred]

        # Show logits for comparison
        o_logit = coreml_logits[0, i, 0]
        bper_logit = coreml_logits[0, i, 3]
        print(f"  {token}: {label} (O={o_logit:.2f}, B-PER={bper_logit:.2f})")

    # Compare with PyTorch
    pytorch_logits = logits.numpy()
    max_diff = np.abs(pytorch_logits - coreml_logits[0]).max()
    print(f"\nMax difference PyTorch vs CoreML: {max_diff}")

    if max_diff < 0.1:
        print("\n SUCCESS! CoreML model matches PyTorch!")
    else:
        print("\n WARNING: Large difference between PyTorch and CoreML")

    # Save updated config
    config_data = {
        "id2label": {str(k): v for k, v in config.id2label.items()},
        "label2id": {v: k for k, v in config.id2label.items()},
        "max_seq_length": MAX_SEQ_LENGTH,
        "vocab_size": len(vocab),
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
        json.dump(config_data, f, indent=2)
    print(f"Saved config to: {config_path}")

    print("\n=== DONE ===")
    print(f"Model: {output_path}")
    print(f"Vocab: {vocab_path}")
    print(f"Config: {config_path}")

if __name__ == "__main__":
    main()
