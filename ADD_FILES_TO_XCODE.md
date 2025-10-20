# Adding New Swift NER Files to Xcode Project

The Swift NER implementation files have been created but need to be added to the Xcode project target.

## Files to Add

### Services Directory:
- `ClinicalAnon/Services/EntityRecognizer.swift`
- `ClinicalAnon/Services/SwiftNERService.swift`

### Recognizers Directory (new folder):
- `ClinicalAnon/Services/Recognizers/AppleNERRecognizer.swift`
- `ClinicalAnon/Services/Recognizers/MaoriNameRecognizer.swift`
- `ClinicalAnon/Services/Recognizers/RelationshipNameExtractor.swift`
- `ClinicalAnon/Services/Recognizers/NZPhoneRecognizer.swift`
- `ClinicalAnon/Services/Recognizers/NZMedicalIDRecognizer.swift`
- `ClinicalAnon/Services/Recognizers/NZAddressRecognizer.swift`
- `ClinicalAnon/Services/Recognizers/DateRecognizer.swift`

## Steps to Add Files in Xcode

1. **Open Xcode project**: `open Redactor.xcodeproj`

2. **In Project Navigator** (left sidebar):
   - Right-click on `ClinicalAnon/Services` folder
   - Select "Add Files to Redactor..."

3. **Add the two service files**:
   - Navigate to `ClinicalAnon/Services/`
   - Select `EntityRecognizer.swift` and `SwiftNERService.swift`
   - Make sure "Add to targets: Redactor" is checked
   - Click "Add"

4. **Add the Recognizers folder**:
   - Right-click on `ClinicalAnon/Services` folder
   - Select "Add Files to Redactor..."
   - Navigate to `ClinicalAnon/Services/`
   - Select the entire `Recognizers` folder
   - Make sure "Create groups" is selected (not "Create folder references")
   - Make sure "Add to targets: Redactor" is checked
   - Click "Add"

5. **Verify**:
   - You should see the Recognizers folder with all 7 .swift files inside it
   - All files should have no red/yellow icons (indicating they're properly linked)

6. **Build** (⌘+B):
   - Build the project to verify everything compiles

## Alternative: Command Line

If you prefer command line, you can try:
```bash
cd /Users/seanversteegh/Redactor
open Redactor.xcodeproj
```

Then follow steps 2-6 above.
