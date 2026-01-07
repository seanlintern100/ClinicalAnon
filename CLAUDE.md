# Claude Code Notes for Redactor

## Build Instructions

**DO NOT run xcodebuild from CLI for this project.**

This app uses MLX (Metal Performance Shaders) which requires the full Xcode Metal toolchain. CLI builds will fail or cause DerivedData corruption.

**To verify builds:** Ask user to build from Xcode (Cmd+B) and share any error logs.

## Project Overview

Redactor is a macOS app for anonymizing clinical documentation. It detects and redacts PII (names, dates, locations, etc.) from healthcare documents.

## Key Technologies

- **MLX Swift** - Local LLM for PII review (requires Apple Silicon)
- **XLM-RoBERTa** - CoreML model for NER
- **AWS Bedrock** - Cloud AI via Lambda proxy (AU region)

## Feature Branches

- `feature/gliner` - Preserved GLiNER code (removed from main, can be re-enabled by merging)
