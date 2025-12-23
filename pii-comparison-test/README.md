# PII Detection Comparison Test System

Compare the current Swift-based PII detection patterns with Microsoft Presidio to evaluate accuracy and identify over-detection.

## Quick Start

```bash
# 1. Navigate to test folder
cd pii-comparison-test

# 2. Create virtual environment
python3 -m venv venv
source venv/bin/activate

# 3. Install dependencies
pip install -r requirements.txt
python -m spacy download en_core_web_lg

# 4. Add your test documents
# Copy .txt files to documents/

# 5. Run comparison
python run_comparison.py

# 6. View results
python compare_results.py
# or: cat results/comparison_report.txt
```

## What It Does

Runs **three detection engines** on your test documents:

| Engine | Description |
|--------|-------------|
| **Current** | Port of Swift patterns (spaCy NER + NZ regex) |
| **Presidio** | Microsoft Presidio vanilla (default recognizers) |
| **Presidio+NZ** | Presidio + custom NZ recognizers (NHI, NZ phones, etc.) |

## Output

```
results/
├── comparison_report.txt     # Human-readable summary
├── detailed_results.json     # Full detection data (for further analysis)
└── per_document/
    ├── doc1_comparison.txt   # Side-by-side for each document
    └── ...
```

## Interpreting Results

The report highlights:

- **Current-only detections** = Potential over-detection (false positives)
- **Presidio-only detections** = Things Presidio catches that current misses
- **Shared detections** = Both engines agree (likely true positives)

## Example Output

```
==========================================================
Document: clinical_note_1.txt
==========================================================

CURRENT ENGINE detected 15 entities:
  "Jane Smith" -> PERSON_OTHER (conf: 0.70)
  "ABC1234" -> IDENTIFIER (conf: 0.85)
  "15/03/2024" -> DATE (conf: 0.95)
  ...

PRESIDIO (vanilla) detected 10 entities:
  "Jane Smith" -> PERSON (conf: 0.85)
  ...

PRESIDIO + NZ detected 14 entities:
  "Jane Smith" -> PERSON (conf: 0.85)
  "ABC1234" -> NZ_NHI (conf: 0.85)
  ...

COMPARISON:
  Current-only detections: 3 (potential over-detection)
  Presidio-only: 1
  Presidio+NZ-only: 2
  Shared (all engines): 8

POTENTIAL OVER-DETECTION (Current-only):
  ! "The" -> PERSON_OTHER
  ! "His" -> PERSON_OTHER
```

## Adding Test Documents

Place `.txt` files in the `documents/` folder. Include:

- Clinical notes with names, dates, NHI numbers
- Documents with edge cases that cause over-detection
- Various formats (referral letters, discharge summaries, etc.)

## Engines Explained

### Current Engine (`engines/current_engine.py`)

Python port of the Swift ClinicalAnon patterns:
- spaCy NER (equivalent to Apple NaturalLanguage)
- Maori name dictionary + phonetic patterns
- Relationship extraction ("sister Margaret")
- NZ phone formats (021, 0800, +64)
- NZ medical IDs (NHI, ACC)
- NZ addresses (Auckland suburbs, DHBs)
- Date patterns (DD/MM/YYYY, etc.)

### Presidio Vanilla (`engines/presidio_engine.py`)

Microsoft Presidio with default recognizers:
- PERSON, LOCATION, PHONE_NUMBER, EMAIL_ADDRESS
- DATE_TIME, CREDIT_CARD, URL, IP_ADDRESS
- No NZ-specific patterns

### Presidio + NZ (`engines/presidio_nz.py`)

Presidio with custom NZ recognizers added:
- NZ_NHI (National Health Index)
- NZ_ACC (ACC case numbers)
- NZ_PHONE (NZ mobile/landline formats)
- NZ_LOCATION (Auckland suburbs, cities, hospitals)
- NZ_DHB (District Health Boards)
- MAORI_NAME (dictionary + phonetic)

## Troubleshooting

### "en_core_web_lg not found"
```bash
python -m spacy download en_core_web_lg
```

### "ModuleNotFoundError: No module named 'presidio_analyzer'"
```bash
pip install presidio-analyzer presidio-anonymizer
```

### No results in output
Make sure you have `.txt` files in the `documents/` folder.
