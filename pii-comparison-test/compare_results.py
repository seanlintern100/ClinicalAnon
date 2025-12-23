#!/usr/bin/env python3
"""
Results Viewer - Display comparison results in a readable format

Usage: python compare_results.py [document_name]
"""

import sys
import json
from pathlib import Path


def main():
    results_dir = Path(__file__).parent / "results"
    json_path = results_dir / "detailed_results.json"
    report_path = results_dir / "comparison_report.txt"

    if not json_path.exists():
        print("No results found. Run 'python run_comparison.py' first.")
        sys.exit(1)

    # If a specific document is requested
    if len(sys.argv) > 1:
        doc_name = sys.argv[1]
        if not doc_name.endswith(".txt"):
            doc_name += ".txt"

        per_doc_path = results_dir / "per_document" / f"{doc_name.replace('.txt', '')}_comparison.txt"
        if per_doc_path.exists():
            with open(per_doc_path, "r") as f:
                print(f.read())
        else:
            print(f"No results found for document: {doc_name}")
            print("Available documents:")
            with open(json_path, "r") as f:
                data = json.load(f)
                for name in data["documents"].keys():
                    print(f"  - {name}")
        return

    # Show full report
    if report_path.exists():
        with open(report_path, "r") as f:
            print(f.read())
    else:
        print("No comparison report found. Run 'python run_comparison.py' first.")


if __name__ == "__main__":
    main()
