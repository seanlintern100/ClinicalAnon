#!/bin/bash

# Script to add new Swift NER files to Xcode project
# This uses a workaround since direct pbxproj manipulation is complex

cd /Users/seanversteegh/Redactor

echo "📁 Adding Swift NER files to Xcode project..."

# The safest way is to use Xcode's command line tools
# Since Xcode is already open, we need to:
# 1. Close Xcode
# 2. Add files
# 3. Reopen

echo "⚠️  Please close Xcode first (Cmd+Q)"
read -p "Press Enter when Xcode is closed..."

# Create a temporary script for xcodebuild
cat > /tmp/add_files.rb << 'EOF'
require 'xcodeproj'

project_path = '/Users/seanversteegh/Redactor/Redactor.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Get the main target
target = project.targets.first

# Find the Services group
services_group = project.main_group['ClinicalAnon']['Services']

# Add new files
new_files = [
  'ClinicalAnon/Services/EntityRecognizer.swift',
  'ClinicalAnon/Services/SwiftNERService.swift',
  'ClinicalAnon/Services/Recognizers/AppleNERRecognizer.swift',
  'ClinicalAnon/Services/Recognizers/MaoriNameRecognizer.swift',
  'ClinicalAnon/Services/Recognizers/RelationshipNameExtractor.swift',
  'ClinicalAnon/Services/Recognizers/NZPhoneRecognizer.swift',
  'ClinicalAnon/Services/Recognizers/NZMedicalIDRecognizer.swift',
  'ClinicalAnon/Services/Recognizers/NZAddressRecognizer.swift',
  'ClinicalAnon/Services/Recognizers/DateRecognizer.swift'
]

recognizers_group = services_group.new_group('Recognizers')

new_files.each do |file_path|
  file_ref = if file_path.include?('Recognizers/')
    recognizers_group.new_file(file_path)
  else
    services_group.new_file(file_path)
  end

  target.add_file_references([file_ref])
end

project.save

puts "✅ Files added successfully!"
EOF

# Check if xcodeproj gem is installed
if ! gem list xcodeproj -i &>/dev/null; then
    echo "📦 Installing xcodeproj gem..."
    sudo gem install xcodeproj
fi

# Run the Ruby script
ruby /tmp/add_files.rb

if [ $? -eq 0 ]; then
    echo "✅ Files added to Xcode project successfully!"
    echo "📱 Opening Xcode..."
    open Redactor.xcodeproj
    echo ""
    echo "Next steps:"
    echo "1. In Xcode, press Cmd+B to build"
    echo "2. Verify no build errors"
    echo "3. Run the app to test!"
else
    echo "❌ Failed to add files automatically."
    echo ""
    echo "Please add files manually in Xcode:"
    echo "1. Right-click on ClinicalAnon/Services"
    echo "2. Select 'Add Files to Redactor...'"
    echo "3. Add EntityRecognizer.swift and SwiftNERService.swift"
    echo "4. Add the Recognizers folder with all 7 files"
    echo "5. Make sure 'Add to targets: Redactor' is checked"
fi
