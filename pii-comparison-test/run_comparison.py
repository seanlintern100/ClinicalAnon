#!/usr/bin/env python3
"""
PII Detection Comparison Runner

Runs all three detection engines on test documents and outputs comparison results.
"""

import os
import sys
import json
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Any

# Add engines to path
sys.path.insert(0, str(Path(__file__).parent))

from engines.current_engine import CurrentEngine, DetectedEntity as CurrentEntity
from engines.presidio_engine import PresidioEngine, DetectedEntity as PresidioEntity
from engines.presidio_nz import PresidioNZEngine, DetectedEntity as PresidioNZEntity


def load_documents(docs_dir: Path) -> Dict[str, str]:
    """Load all .txt files from documents directory"""
    documents = {}
    for file_path in docs_dir.glob("*.txt"):
        with open(file_path, "r", encoding="utf-8") as f:
            documents[file_path.name] = f.read()
    return documents


def run_engine(engine, text: str, engine_name: str) -> List[Dict]:
    """Run an engine and return results as dicts"""
    try:
        entities = engine.detect(text)
        return [
            {
                "text": e.text,
                "type": e.entity_type if isinstance(e.entity_type, str) else e.entity_type.value,
                "start": e.start,
                "end": e.end,
                "confidence": e.confidence,
                "source": e.source
            }
            for e in entities
        ]
    except Exception as ex:
        print(f"  ERROR in {engine_name}: {ex}")
        return []


def compare_results(current: List[Dict], presidio: List[Dict], presidio_nz: List[Dict]) -> Dict:
    """Compare detection results between engines"""

    def make_key(e):
        return (e["text"].lower(), e["start"], e["end"])

    current_keys = set(make_key(e) for e in current)
    presidio_keys = set(make_key(e) for e in presidio)
    presidio_nz_keys = set(make_key(e) for e in presidio_nz)

    return {
        "current_only": len(current_keys - presidio_keys - presidio_nz_keys),
        "presidio_only": len(presidio_keys - current_keys),
        "presidio_nz_only": len(presidio_nz_keys - current_keys),
        "shared_current_presidio": len(current_keys & presidio_keys),
        "shared_current_presidio_nz": len(current_keys & presidio_nz_keys),
        "shared_all": len(current_keys & presidio_keys & presidio_nz_keys),
    }


def generate_report(doc_name: str, text: str, current: List[Dict],
                    presidio: List[Dict], presidio_nz: List[Dict]) -> str:
    """Generate human-readable comparison report for a document"""
    lines = []
    lines.append(f"{'='*60}")
    lines.append(f"Document: {doc_name}")
    lines.append(f"{'='*60}")
    lines.append("")

    # Current engine results
    lines.append(f"CURRENT ENGINE detected {len(current)} entities:")
    for e in sorted(current, key=lambda x: x["start"]):
        lines.append(f'  "{e["text"]}" -> {e["type"]} (conf: {e["confidence"]:.2f})')
    lines.append("")

    # Presidio results
    lines.append(f"PRESIDIO (vanilla) detected {len(presidio)} entities:")
    for e in sorted(presidio, key=lambda x: x["start"]):
        lines.append(f'  "{e["text"]}" -> {e["type"]} (conf: {e["confidence"]:.2f})')
    lines.append("")

    # Presidio NZ results
    lines.append(f"PRESIDIO + NZ detected {len(presidio_nz)} entities:")
    for e in sorted(presidio_nz, key=lambda x: x["start"]):
        lines.append(f'  "{e["text"]}" -> {e["type"]} (conf: {e["confidence"]:.2f})')
    lines.append("")

    # Differences
    comparison = compare_results(current, presidio, presidio_nz)
    lines.append("COMPARISON:")
    lines.append(f"  Current-only detections: {comparison['current_only']} (potential over-detection)")
    lines.append(f"  Presidio-only: {comparison['presidio_only']}")
    lines.append(f"  Presidio+NZ-only: {comparison['presidio_nz_only']}")
    lines.append(f"  Shared (all engines): {comparison['shared_all']}")
    lines.append("")

    # Highlight current-only detections (potential false positives)
    current_texts = {(e["text"].lower(), e["start"], e["end"]) for e in current}
    presidio_texts = {(e["text"].lower(), e["start"], e["end"]) for e in presidio}
    presidio_nz_texts = {(e["text"].lower(), e["start"], e["end"]) for e in presidio_nz}

    current_only = current_texts - presidio_texts - presidio_nz_texts
    if current_only:
        lines.append("POTENTIAL OVER-DETECTION (Current-only):")
        for text_lower, start, end in current_only:
            # Find original entity for display
            for e in current:
                if e["text"].lower() == text_lower and e["start"] == start:
                    lines.append(f'  ! "{e["text"]}" -> {e["type"]}')
                    break
        lines.append("")

    return "\n".join(lines)


def main():
    print("PII Detection Comparison")
    print("=" * 40)
    print()

    # Paths
    base_dir = Path(__file__).parent
    docs_dir = base_dir / "documents"
    results_dir = base_dir / "results"
    per_doc_dir = results_dir / "per_document"

    # Create output directories
    results_dir.mkdir(exist_ok=True)
    per_doc_dir.mkdir(exist_ok=True)

    # Load documents
    documents = load_documents(docs_dir)
    if not documents:
        print("ERROR: No .txt files found in documents/ folder")
        print("Please add test documents and run again.")
        sys.exit(1)

    print(f"Found {len(documents)} document(s)")
    print()

    # Initialize engines
    print("Initializing engines...")
    try:
        current_engine = CurrentEngine()
        print("  [OK] Current engine")
    except Exception as e:
        print(f"  [FAIL] Current engine: {e}")
        sys.exit(1)

    try:
        presidio_engine = PresidioEngine()
        print("  [OK] Presidio engine")
    except Exception as e:
        print(f"  [FAIL] Presidio engine: {e}")
        sys.exit(1)

    try:
        presidio_nz_engine = PresidioNZEngine()
        print("  [OK] Presidio + NZ engine")
    except Exception as e:
        print(f"  [FAIL] Presidio + NZ engine: {e}")
        sys.exit(1)

    print()

    # Process documents
    all_results = {}
    all_reports = []
    summary = {
        "total_current": 0,
        "total_presidio": 0,
        "total_presidio_nz": 0,
        "current_only_total": 0,
    }

    for doc_name, text in documents.items():
        print(f"Processing: {doc_name}")

        # Run all engines
        current_results = run_engine(current_engine, text, "Current")
        presidio_results = run_engine(presidio_engine, text, "Presidio")
        presidio_nz_results = run_engine(presidio_nz_engine, text, "Presidio+NZ")

        # Store results
        all_results[doc_name] = {
            "text_length": len(text),
            "current": current_results,
            "presidio": presidio_results,
            "presidio_nz": presidio_nz_results,
            "comparison": compare_results(current_results, presidio_results, presidio_nz_results)
        }

        # Update summary
        summary["total_current"] += len(current_results)
        summary["total_presidio"] += len(presidio_results)
        summary["total_presidio_nz"] += len(presidio_nz_results)
        summary["current_only_total"] += all_results[doc_name]["comparison"]["current_only"]

        # Generate per-document report
        report = generate_report(doc_name, text, current_results, presidio_results, presidio_nz_results)
        all_reports.append(report)

        # Save per-document report
        report_path = per_doc_dir / f"{doc_name.replace('.txt', '')}_comparison.txt"
        with open(report_path, "w", encoding="utf-8") as f:
            f.write(report)

        print(f"  Current: {len(current_results)}, Presidio: {len(presidio_results)}, Presidio+NZ: {len(presidio_nz_results)}")

    print()

    # Save detailed JSON results
    json_path = results_dir / "detailed_results.json"
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump({
            "timestamp": datetime.now().isoformat(),
            "summary": summary,
            "documents": all_results
        }, f, indent=2)
    print(f"Detailed results saved to: {json_path}")

    # Save combined report
    report_path = results_dir / "comparison_report.txt"
    with open(report_path, "w", encoding="utf-8") as f:
        f.write("PII DETECTION COMPARISON REPORT\n")
        f.write(f"Generated: {datetime.now().isoformat()}\n")
        f.write("=" * 60 + "\n\n")

        f.write("SUMMARY\n")
        f.write("-" * 40 + "\n")
        f.write(f"Documents processed: {len(documents)}\n")
        f.write(f"Total detections - Current: {summary['total_current']}\n")
        f.write(f"Total detections - Presidio: {summary['total_presidio']}\n")
        f.write(f"Total detections - Presidio+NZ: {summary['total_presidio_nz']}\n")
        f.write(f"\nPotential over-detection (Current-only): {summary['current_only_total']}\n")
        f.write("\n" + "=" * 60 + "\n\n")

        for report in all_reports:
            f.write(report)
            f.write("\n\n")

    print(f"Comparison report saved to: {report_path}")
    print()

    # Print summary
    print("=" * 40)
    print("SUMMARY")
    print("=" * 40)
    print(f"Current engine detections:    {summary['total_current']}")
    print(f"Presidio detections:          {summary['total_presidio']}")
    print(f"Presidio + NZ detections:     {summary['total_presidio_nz']}")
    print()
    print(f"Current-only (potential over-detection): {summary['current_only_total']}")
    print()
    print(f"See results/ folder for detailed reports.")


if __name__ == "__main__":
    main()
