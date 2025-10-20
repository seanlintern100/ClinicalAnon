#!/bin/bash

# ClinicalAnon - Font Download and Setup Script
# This script downloads Lora and Source Sans 3 fonts and prepares them for Xcode

set -e

echo "🎨 ClinicalAnon Font Setup"
echo "=========================="
echo ""

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Create fonts directory
echo -e "${BLUE}Creating fonts directory...${NC}"
mkdir -p ClinicalAnon/Resources/Fonts
cd ClinicalAnon/Resources/Fonts

# Download Lora fonts
echo -e "${BLUE}Downloading Lora fonts (serif - for headings)...${NC}"

curl -L -o "Lora-Regular.ttf" \
  "https://github.com/google/fonts/raw/main/ofl/lora/static/Lora-Regular.ttf"

curl -L -o "Lora-Bold.ttf" \
  "https://github.com/google/fonts/raw/main/ofl/lora/static/Lora-Bold.ttf"

curl -L -o "Lora-Italic.ttf" \
  "https://github.com/google/fonts/raw/main/ofl/lora/static/Lora-Italic.ttf"

# Download Source Sans 3 fonts
echo -e "${BLUE}Downloading Source Sans 3 fonts (sans-serif - for body)...${NC}"

curl -L -o "SourceSans3-Regular.ttf" \
  "https://github.com/google/fonts/raw/main/ofl/sourcesans3/static/SourceSans3-Regular.ttf"

curl -L -o "SourceSans3-SemiBold.ttf" \
  "https://github.com/google/fonts/raw/main/ofl/sourcesans3/static/SourceSans3-SemiBold.ttf"

curl -L -o "SourceSans3-Bold.ttf" \
  "https://github.com/google/fonts/raw/main/ofl/sourcesans3/static/SourceSans3-Bold.ttf"

# Verify downloads
echo ""
echo -e "${BLUE}Verifying font files...${NC}"
echo ""

FONTS=(
  "Lora-Regular.ttf"
  "Lora-Bold.ttf"
  "Lora-Italic.ttf"
  "SourceSans3-Regular.ttf"
  "SourceSans3-SemiBold.ttf"
  "SourceSans3-Bold.ttf"
)

ALL_GOOD=true

for font in "${FONTS[@]}"; do
  if [ -f "$font" ]; then
    SIZE=$(stat -f%z "$font" 2>/dev/null || stat -c%s "$font" 2>/dev/null)
    if [ "$SIZE" -gt 10000 ]; then
      echo -e "${GREEN}✓${NC} $font ($(numfmt --to=iec-i --suffix=B $SIZE 2>/dev/null || echo ${SIZE} bytes))"
    else
      echo -e "${RED}✗${NC} $font (file too small - likely download error)"
      ALL_GOOD=false
    fi
  else
    echo -e "${RED}✗${NC} $font (missing)"
    ALL_GOOD=false
  fi
done

cd ../../..

echo ""
if [ "$ALL_GOOD" = true ]; then
  echo -e "${GREEN}✅ All fonts downloaded successfully!${NC}"
  echo ""
  echo "Fonts are ready in: ClinicalAnon/Resources/Fonts/"
  echo ""
  echo "Next steps:"
  echo "1. Open Xcode"
  echo "2. Create new macOS App project named 'ClinicalAnon'"
  echo "3. Add the fonts to your Xcode project"
  echo "4. See docs/XCODE-SETUP-SIMPLE.md for detailed instructions"
else
  echo -e "${RED}❌ Some fonts failed to download.${NC}"
  echo ""
  echo "You can manually download fonts from:"
  echo "  Lora: https://fonts.google.com/specimen/Lora"
  echo "  Source Sans 3: https://fonts.google.com/specimen/Source+Sans+3"
  echo ""
  echo "Place the TTF files in: ClinicalAnon/Resources/Fonts/"
  exit 1
fi
