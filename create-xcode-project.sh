#!/bin/bash

# ClinicalAnon - Xcode Project Creation Helper
# This script prepares the project structure for Xcode

set -e

echo "🚀 ClinicalAnon Xcode Project Setup"
echo "===================================="
echo ""

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Check if we're in the right directory
if [ ! -f "ClinicalAnon/ClinicalAnonApp.swift" ]; then
  echo -e "${RED}Error: Please run this script from the Redactor directory${NC}"
  echo "cd /Users/seanversteegh/Redactor"
  exit 1
fi

echo -e "${BLUE}Step 1: Verifying project structure...${NC}"

# Check all required files exist
FILES_TO_CHECK=(
  "ClinicalAnon/ClinicalAnonApp.swift"
  "ClinicalAnon/Utilities/DesignSystem.swift"
  "ClinicalAnon/Utilities/AppError.swift"
  "ClinicalAnon/Resources/Info.plist"
  "ClinicalAnon/Resources/Fonts/Lora-Regular.ttf"
  "ClinicalAnon/Resources/Fonts/Lora-Bold.ttf"
  "ClinicalAnon/Resources/Fonts/Lora-Italic.ttf"
  "ClinicalAnon/Resources/Fonts/SourceSans3-Regular.ttf"
  "ClinicalAnon/Resources/Fonts/SourceSans3-SemiBold.ttf"
  "ClinicalAnon/Resources/Fonts/SourceSans3-Bold.ttf"
)

ALL_PRESENT=true
for file in "${FILES_TO_CHECK[@]}"; do
  if [ -f "$file" ]; then
    echo -e "${GREEN}✓${NC} $file"
  else
    echo -e "${RED}✗${NC} $file (missing)"
    ALL_PRESENT=false
  fi
done

if [ "$ALL_PRESENT" = false ]; then
  echo -e "\n${RED}Error: Some required files are missing${NC}"
  exit 1
fi

echo ""
echo -e "${BLUE}Step 2: Creating Assets.xcassets...${NC}"

# Create basic Assets.xcassets structure
mkdir -p "ClinicalAnon/Resources/Assets.xcassets/AppIcon.appiconset"
mkdir -p "ClinicalAnon/Resources/Assets.xcassets/AccentColor.colorset"

# Create Contents.json for Assets
cat > "ClinicalAnon/Resources/Assets.xcassets/Contents.json" << 'EOF'
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF

# Create AppIcon Contents.json
cat > "ClinicalAnon/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json" << 'EOF'
{
  "images" : [
    {
      "filename" : "AppIcon-512@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "512x512"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF

# Create AccentColor Contents.json
cat > "ClinicalAnon/Resources/Assets.xcassets/AccentColor.colorset/Contents.json" << 'EOF'
{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "0.486",
          "green" : "0.420",
          "red" : "0.039"
        }
      },
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF

echo -e "${GREEN}✓${NC} Assets.xcassets created"

echo ""
echo -e "${BLUE}Step 3: Creating Preview Content...${NC}"

mkdir -p "ClinicalAnon/Preview Content"
cat > "ClinicalAnon/Preview Content/Preview Assets.xcassets/Contents.json" << 'EOF'
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF

echo -e "${GREEN}✓${NC} Preview Content created"

echo ""
echo -e "${BLUE}Step 4: Organizing file structure...${NC}"

# Ensure all directory structure exists
mkdir -p ClinicalAnon/Views/Components
mkdir -p ClinicalAnon/ViewModels
mkdir -p ClinicalAnon/Models
mkdir -p ClinicalAnon/Services
mkdir -p ClinicalAnon/Tests

echo -e "${GREEN}✓${NC} Directory structure complete"

echo ""
echo -e "${GREEN}✅ Project structure is ready!${NC}"
echo ""
echo -e "${YELLOW}═══════════════════════════════════════════${NC}"
echo -e "${YELLOW}Next Steps - Manual in Xcode:${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════${NC}"
echo ""
echo "1. Open Xcode"
echo "2. File → New → Project"
echo "3. macOS → App"
echo "4. Configure:"
echo "   - Product Name: ClinicalAnon"
echo "   - Organization: 3 Big Things"
echo "   - Interface: SwiftUI"
echo "   - Language: Swift"
echo ""
echo "5. Save location: /Users/seanversteegh/Redactor/"
echo "   (Choose 'Merge' when prompted)"
echo ""
echo "6. Follow docs/XCODE-SETUP-SIMPLE.md for detailed steps"
echo ""
echo -e "${BLUE}Or try this command to open Xcode:${NC}"
echo "  open -a Xcode"
echo ""

# Try to detect if Xcode is installed
if command -v xcodebuild &> /dev/null; then
  echo -e "${GREEN}✓${NC} Xcode detected: $(xcodebuild -version | head -n 1)"
  echo ""
  echo -e "${BLUE}Would you like to:"
  echo "  A) Open Xcode now (you'll create the project manually)"
  echo "  B) See the setup guide"
  echo "  C) Exit"
  echo ""
  read -p "Choice (A/B/C): " choice

  case $choice in
    [Aa]* )
      open -a Xcode
      echo ""
      echo "Xcode opened! Follow docs/XCODE-SETUP-SIMPLE.md"
      ;;
    [Bb]* )
      if command -v bat &> /dev/null; then
        bat docs/XCODE-SETUP-SIMPLE.md
      elif command -v less &> /dev/null; then
        less docs/XCODE-SETUP-SIMPLE.md
      else
        cat docs/XCODE-SETUP-SIMPLE.md
      fi
      ;;
    * )
      echo "Setup complete. See docs/XCODE-SETUP-SIMPLE.md when ready."
      ;;
  esac
else
  echo -e "${YELLOW}⚠️  Xcode not found in PATH${NC}"
  echo "Please install Xcode from the App Store"
fi

echo ""
echo "📚 Documentation:"
echo "  - Quick guide: docs/XCODE-SETUP-SIMPLE.md"
echo "  - Detailed guide: docs/PHASE-1-SETUP-GUIDE.md"
echo ""
