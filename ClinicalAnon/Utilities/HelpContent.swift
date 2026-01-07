//
//  HelpContent.swift
//  ClinicalAnon
//
//  Purpose: Static help content for Redactor User Guide and phase-specific help
//  Organization: 3 Big Things
//

import Foundation

// MARK: - Help Content Type

enum HelpContentType {
    case fullGuide
    case redactPhase
    case improvePhase
    case restorePhase

    var title: String {
        switch self {
        case .fullGuide: return "Redactor User Guide"
        case .redactPhase: return "Redact Phase Guide"
        case .improvePhase: return "Improve Phase Guide"
        case .restorePhase: return "Restore Phase Guide"
        }
    }

    var subtitle: String {
        switch self {
        case .fullGuide: return "Complete Guide"
        case .redactPhase: return "Phase 1 of 3"
        case .improvePhase: return "Phase 2 of 3"
        case .restorePhase: return "Phase 3 of 3"
        }
    }

    var content: String {
        switch self {
        case .fullGuide: return HelpContent.fullGuide
        case .redactPhase: return HelpContent.redactPhase
        case .improvePhase: return HelpContent.improvePhase
        case .restorePhase: return HelpContent.restorePhase
        }
    }
}

// MARK: - Help Content

struct HelpContent {

    // MARK: - Full User Guide

    static let fullGuide = """
# Redactor User Guide

## About Redactor

Redactor was built for 3 Big Things staff to use AI effectively when working with client-related information while meeting New Zealand privacy principles.

You want AI to help polish notes, create reports, and save time—but sending client details to external services creates risk you can't afford. Redactor solves this by removing identifying information locally before anything leaves your Mac.

**Key features:**
- Redacts personally identifiable information before AI processing
- No storage of information locally or on external servers
- Uses AI based in Australia (Anthropic Claude via AWS) that does not use your content for training

All AI processing happens on servers in Australia. Your content is never stored—not on your Mac, not on external servers.

---

## What Redactor Does

Redactor handles tasks that involve client information:

- **Polish rough notes** — Turn your session jottings into clear documentation
- **Process transcripts** — Convert session transcripts into structured notes for you and your client
- **Create review documents** — Pull together notes from multiple sessions to create ACC BSS reviews or similar
- **Build assessments** — Combine reports from various sources (other clinicians, your own notes) into comprehensive assessments

The process works in three phases: Redact, Improve, Restore.

---

## Phase 1: Redact

### Getting Started

Copy and paste your text into the left pane. You can paste from any source—Word documents, PDFs, web pages, your records system. Redactor works with text only; you cannot upload files directly.

Click **Analyze** to start detection.

### How Detection Works

Redactor runs an initial scan using Named Entity Recognition (NER) combined with a local language model. This happens entirely on your Mac—nothing is sent externally at this stage.

The initial scan catches most identifying information automatically.

**Important:** Redaction is not 100% accurate. We encourage you to do a manual scan after auto-detection and redact any key information that wasn't captured.

### Additional Scanning Options

**Deep Scan**
A quick secondary check that picks up items the initial scan may have missed. Because Deep Scan casts a wider net, it produces false positives—words flagged that aren't actually identifying information.

Deep Scan results are listed but not automatically applied. Review the suggestions and select which ones to redact.

**LLM Scan**
Uses a more thorough local language model for detection. This is slower but catches additional edge cases. LLM Scan is currently available for testing purposes.

To use LLM Scan, you need to download the local model first. Manage this through Settings—download when you need it, delete it to free up disk space (approximately 2-5GB).

### Understanding Entities

An entity is any piece of text that gets redacted. When Redactor detects identifying information, it becomes an entity and is replaced with a placeholder.

For example, "James Wilson" might become [CLIENT_A], "Dr Patel" becomes [PROVIDER_A], and "021 555 1234" becomes [CONTACT_A]. The app categorises entities by type—client, provider, person, date, location, organisation, identifier, contact—to help keep things organised.

### Managing Entities

**Adding missed items**
If a word wasn't detected, right-click on it and select "Add as entity." You can also use the **+** button at the top of the sidebar to add words manually.

**Removing false positives**
Right-click on a redacted word and select "Remove from entities," or untick it in the sidebar.

**Ongoing issues**
If a word keeps getting redacted when it shouldn't (or keeps being missed when it should be caught), add it to the Exclusions or Inclusions lists in Settings. This saves you fixing it every time.

**Reclassifying entities**
Right-click on any entity in the sidebar to change its type—for example, if a place name was incorrectly classified as a person.

### Merging Entities

Documents often refer to the same person in different ways—"Sean Versteegh," "Sean," or "Mr Versteegh." Without merging, each becomes a separate placeholder, which confuses the AI and clutters your output.

Merging links all variants to a single identifier.

**How to merge manually:**
Right-click on a name in the sidebar and select "Merge with another." The name you click gets merged into the target—so pick the fullest version of the name (e.g., "Sean Versteegh") as your target, as this will persist in the final output.

**Bulk merging:**
The app automatically identifies possible merges and suggests them at the top of the sidebar. This is helpful but not always accurate—review the suggestions before accepting.

**Editing name structure:**
Right-click → "Edit name structure" to update how the restored name will appear in your final document.

### Adding Multiple Documents

You can combine multiple source documents for AI processing. This is useful when creating assessments from multiple reports or building reviews from several sessions.

Click **Add More Docs** to save your current document and paste another. Add as many as you need.

When you've added all your documents, click **Continue** to move to the Improve phase.

---

## Phase 2: Improve

### Choosing Your Approach

When you land on this page, you have two options:

1. **Use a pre-built prompt** — We've created prompts for common tasks that we know work well. Select a document type and Redactor handles the rest.

2. **Chat directly** — Skip the prompts and talk to the AI yourself. Ask for exactly what you need.

You can also edit the pre-built prompts or create your own for specific tasks.

The AI receives your redacted text alongside your prompt or message. It sees placeholders like [CLIENT_A], never the original names.

### Document Types

| Type | What It Does |
|------|--------------|
| **Notes** | Transforms rough notes into clear, professional documentation |
| **Transcript Notes** | Converts transcripts into structured notes for your records and client summaries |
| **Report** | Creates formal reports for external audiences—case managers, GPs, funders |
| **Summary** | Produces a concise summary of key findings and recommendations |
| **ACC BSS Report** | Formats output for NZ Behavioural Support Service reporting |
| **ACC BSS Review** | Creates goals vs outcomes reviews for ACC purposes |
| **Custom** | Use your own template or create something specific |

### Refining Output

Review the AI output in the left pane. Use the chat on the right to refine: "Make this more concise," "Add more detail about the treatment plan," or "Use less formal language."

When you're satisfied, click **Accept & Continue**.

---

## Phase 3: Restore

### What Happens Here

Redactor takes the AI-improved document and puts the original names and identifiers back in place of the placeholders. Everything happens locally on your Mac.

### Editing Replacements

If an entity has been replaced with incorrect text, right-click on it in the sidebar and type in the text that should appear instead.

### Copying Your Final Document

When you're satisfied:

1. Click **Copy to Clipboard**
2. Paste directly into your records system, Word, or wherever you need it

Click **Start New** to begin a fresh session. Nothing from your session is retained after you close the app or start a new session.

---

## Settings

Access via **Cmd + ,** or the menu bar.

### AI Model

Select your preferred Claude model. Claude Sonnet 4.5 is recommended for the best balance of speed and quality.

No credentials needed—Redactor uses a secure proxy.

### Local LLM

- Requires Apple Silicon (M1/M2/M3/M4)
- Download the model for LLM Scan functionality
- Delete to free disk space (approximately 2-5GB)

### Number Handling

Redactor automatically redacts all numbers by default. However, numbers are often necessary for the AI to understand context and frequently don't represent identifying information.

You can choose whether numbers should be auto-redacted. Even with the toggle off, the app will still pick up key identifiers like phone numbers, but may miss other numeric information. You can always manually redact or unredact specific numbers when using the app.

### Date Handling

Dates are often useful context for the AI. You can choose to:
- Keep the month visible (recommended) — Redacts only the day and year
- Redact the whole date automatically

These are general settings. You can always choose to unredact or redact specific dates when using the app.

### Exclusions

Words that should never be flagged as identifying information. Add terms specific to your practice that commonly trigger false positives.

### Inclusions

Words that should always be flagged. Add names that are frequently missed and assign each an entity type.

---

## Privacy and Security

**Local processing**
All detection and redaction happens on your Mac. Unredacted client information never leaves your device.

**Australian data residency**
AI processing uses Anthropic's Claude via AWS servers in Sydney. Your data does not leave Australia.

**No storage**
External servers do not retain your content. Session data on your device clears when the app closes.

**No training**
Your content is never used to train AI models.

**Encryption**
All data in transit uses TLS encryption.

Even if external servers were compromised, attackers would find only meaningless placeholders with no way to connect them to real individuals.

---

## Tips for Best Results

1. **Always do a manual check** — Auto-detection is good but not perfect. Scan through after redaction and catch anything that was missed.
2. **Merge name variants** — Linking "Dr Smith," "Smith," and "Jane Smith" to one identifier gives cleaner output.
3. **Use Deep Scan for complex documents** — More catches, but review suggestions carefully.
4. **Add problem words to Settings** — If something keeps being missed or falsely flagged, add it to Inclusions or Exclusions.
5. **Use the chat to refine** — Easier than regenerating from scratch.
6. **Review the final document** — Your professional judgement matters. AI assists your documentation; it doesn't replace you.

---

## Limitations

**Review required**
Redaction is not 100% accurate. Always check detected entities before processing. Unusual names, nicknames, or names that are common words may be missed.

**Professional judgement**
AI suggestions should be reviewed. This tool assists your documentation—it doesn't replace your professional judgement.

**Connectivity**
AI processing requires an internet connection. Redaction works offline.

**Text only**
Redactor works with copied text. You cannot upload document files directly.

---

## Support

For help or feedback, contact your administrator.

To report a missed detection or privacy concern, flag it immediately so we can improve the system.

---

**Redactor**
Version 1.0

Developed for 3 Big Things Ltd
© 2026 All rights reserved
"""

    // MARK: - Redact Phase Guide

    static let redactPhase = """
# Redact Phase Guide

## What Happens Here

This is where you prepare your text for AI processing. Redactor identifies and masks all personally identifiable information—names, dates, NHI numbers, addresses—so nothing identifying leaves your Mac.

The AI will only ever see placeholders like [CLIENT_A] or [DATE_A], never the original details.

---

## Getting Your Text In

Copy and paste your text into the left pane. You can paste from anywhere—Word documents, PDFs, web pages, your records system. Redactor works with text only; you cannot upload files directly.

Click **Analyze** to start detection.

---

## How Detection Works

### Initial Scan
Redactor runs Named Entity Recognition (NER) combined with a local language model. This happens entirely on your Mac—nothing is sent externally.

The initial scan catches most identifying information automatically.

### Important: Manual Review Required

**Redaction is not 100% accurate.** We encourage you to do a manual scan after auto-detection occurs. Look through your document and redact any key information that wasn't captured. This is especially important for unusual names, nicknames, or words that could be names in context.

### Deep Scan
A quick secondary check that casts a wider net. Useful for picking up items the initial scan missed, but expect false positives—words flagged that aren't actually identifying information.

Deep Scan results appear as suggestions. They're not automatically applied. Review the list and tick the ones you want to redact.

### LLM Scan
A more thorough check using a local language model. Slower but catches additional edge cases. Currently available for testing.

You'll need to download the local model first (Settings → Local LLM). It's approximately 2-5GB. Delete it when you don't need it to free up space.

---

## Understanding Entities

An entity is any piece of text that gets redacted. When Redactor detects identifying information, it becomes an entity and is replaced with a placeholder.

For example, "James Wilson" might become [CLIENT_A], "Dr Patel" becomes [PROVIDER_A], and "021 555 1234" becomes [CONTACT_A]. The app categorises entities by type—client, provider, person, date, location, organisation, identifier, contact—to help keep things organised.

---

## Managing Entities

### Adding Missed Items
- **Right-click** on any word → "Add as entity"
- **+ button** at top of sidebar → Add manually

### Removing False Positives
- **Right-click** on redacted word → "Remove from entities"
- **Untick** in the sidebar

### Ongoing Issues
If a word keeps getting redacted when it shouldn't (or keeps being missed when it should be caught), add it to the **Exclusions** or **Inclusions** lists in Settings. This saves you fixing the same thing every session.

### Changing Entity Types
Right-click on any entity in the sidebar to reclassify—for example, if a location was incorrectly tagged as a person.

---

## Merging Entities

Documents often refer to the same person multiple ways: "Sean Versteegh," "Sean," "Mr Versteegh." Without merging, each becomes a separate placeholder ([PERSON_A], [PERSON_B], [PERSON_C]), which confuses the AI and clutters your output.

Merging links all variants to a single identifier.

### Manual Merging

1. Find the **fullest version** of the name (e.g., "Sean Versteegh")—this will be your target
2. Right-click on a variant (e.g., "Sean")
3. Select "Merge with another"
4. Choose the target name

The name you click gets merged into the target. The target name persists in the final output.

### Bulk Merging

The app automatically identifies possible merges and suggests them at the top of the sidebar. This is helpful but not always accurate—review the suggestions before accepting them.

### Editing Name Structure
Right-click → "Edit name structure" to update how the restored name will appear in your final document.

---

## Working with Multiple Documents

You can combine multiple source documents for AI processing. This is useful when:
- Creating assessments from multiple reports
- Building ACC BSS reviews from several sessions
- Pulling together notes from different sources

### Adding Documents
1. Complete redaction on your first document
2. Click **Add More Docs**
3. Paste your next document
4. Repeat as needed

Add as many documents as you need. All will be sent together to the AI.

### When You're Done
Click **Continue** to move to the Improve phase.

---

## Tips

- **Always do a manual check** — Auto-detection is good but not perfect. Scan through and catch anything that was missed.
- **Merge liberally** — Linking name variants significantly improves output quality.
- **Use Deep Scan for complex documents** — More catches, but review the suggestions carefully.
- **Check the sidebar** — It shows everything that's been detected. Scroll through to spot anything odd.
- **Add problem words to Settings** — If something keeps being missed or falsely flagged, add it to Inclusions or Exclusions so you don't have to fix it every time.
"""

    // MARK: - Improve Phase Guide

    static let improvePhase = """
# Improve Phase Guide

## What Happens Here

This is where AI enhances your documentation. Your redacted text—with all identifying information replaced by placeholders—is sent to Claude (Anthropic's AI) running on servers in Australia.

The AI sees [CLIENT_A] and [PROVIDER_A], never the real names. Your content is processed and returned. Nothing is stored. Nothing is used for training.

---

## Two Ways to Work

When you arrive at this page, choose your approach:

### Option 1: Use a Pre-Built Prompt
We've created prompts for common tasks that we know work well. Select a document type, adjust the style sliders if needed, and click Generate.

These prompts have been tested and refined. They're a good starting point for standard documentation tasks.

### Option 2: Chat Directly
Skip the prompts entirely. Type what you need in the chat panel and talk to the AI yourself.

This gives you complete flexibility. Ask for exactly what you want, in whatever format suits your purpose.

---

## Document Types

| Type | What It Does |
|------|--------------|
| **Notes** | Transforms rough session notes into clear, professional documentation |
| **Transcript Notes** | Converts session transcripts into structured notes for your records and client summaries |
| **Report** | Creates formal reports for external audiences—case managers, GPs, funders |
| **Summary** | Produces a concise summary of key findings and recommendations |
| **ACC BSS Report** | Formats output for NZ Behavioural Support Service reporting |
| **ACC BSS Review** | Creates goals vs outcomes reviews for ACC purposes |
| **Custom** | Use your own template or create something specific |

---

## Style Sliders

Adjust these to match your audience and purpose:

### Formality
- **Low (1):** Warm, conversational tone. Suitable for internal notes or client-facing summaries.
- **High (5):** Precise, formal language. Suitable for medico-legal documentation or external reports.

### Detail
- **Low (1):** Brief essentials only. Key points without elaboration.
- **High (5):** Comprehensive coverage. Thorough documentation of all relevant information.

### Structure
- **Low (1):** Flowing narrative. Natural prose without rigid formatting.
- **High (5):** Structured format. Clear headings, sections, and systematic organisation.

---

## Editing Prompts

The pre-built prompts work well for most situations, but you can modify them:

1. Select a document type
2. Review the prompt text
3. Edit as needed for your specific requirements
4. Generate

Your edits apply to the current session. To save a custom prompt permanently, use the Custom option.

---

## Creating Custom Prompts

For tasks you do regularly that don't fit the standard options:

1. Select **Custom**
2. Write your prompt
3. Save it for future use

Good prompts are specific about what you want: format, tone, what to include, what to leave out.

---

## Working with Large Documents

When you submit lengthy source material, the AI automatically creates individual summary documents. These appear in the sidebar.

This helps manage complex inputs—the AI breaks down the material into digestible pieces before producing your final output.

---

## Refining Your Output

The AI's first attempt might not be exactly what you need. Use the chat panel to refine:

- "Make this more concise"
- "Add more detail about the treatment plan"
- "Use less formal language"
- "Restructure with clearer headings"
- "Focus more on the client's progress"
- "Remove the recommendations section"

The AI remembers the conversation. You can refine iteratively until you're satisfied.

---

## What the AI Receives

The AI sees:
- Your redacted text (with placeholders, not real names)
- Your selected prompt or chat message
- The style settings you've chosen

The AI does not see:
- Original names or identifying information
- Your previous sessions
- Anyone else's documents

Each session is isolated. Nothing persists after you close the app.

---

## Moving Forward

When you're happy with the output, click **Accept & Continue** to move to the Restore phase, where original names are put back in.

If you want to start over with different settings or a different approach, you can regenerate or modify your request.

---

## Tips

- **Start with pre-built prompts** — They're tested and work well for standard tasks
- **Use chat for refinement** — Easier than regenerating from scratch
- **Match sliders to audience** — External reports need higher formality; internal notes can be warmer
- **Be specific in custom prompts** — "Write a report" is vague; "Write a one-page summary for the client's GP focusing on medication response and next steps" gets better results
- **Check the output carefully** — AI is helpful but not perfect. Your professional judgement matters.
"""

    // MARK: - Restore Phase Guide

    static let restorePhase = """
# Restore Phase Guide

## What Happens Here

This is the final step. Redactor takes the AI-improved document and puts the original names and identifiers back in place of the placeholders.

Everything happens locally on your Mac. The restored document with real names never touches external servers.

---

## Reviewing Your Document

Before copying your final document, scan through to check that names and identifiers have been restored correctly.

The sidebar shows each entity that was redacted. Review these to ensure the right text is appearing in the right places.

---

## Editing Replacements

If an entity has been replaced with incorrect text:

1. Right-click on the entity in the sidebar
2. Type in the text that should appear instead
3. The document updates automatically

Use this when:
- The restored name isn't quite right (wrong format, missing title)
- You want to use a different form of the name
- Something needs correcting before you copy

---

## Copying Your Final Document

When you're satisfied with the restored document:

1. Click **Copy to Clipboard**
2. Paste directly into your records system, Word, or wherever you need it

The document is ready to use—professional documentation with all the correct names and identifiers in place.

---

## Starting Fresh

Click **Start New** to begin a new session.

This clears everything:
- Source documents
- Detected entities
- AI output
- Restored document

Nothing from your session is retained after you close the app or start a new session.

---

## Common Situations

### Names Restored in Wrong Format
If "Dr Sarah Mitchell" comes back as "Sarah Mitchell" when you wanted the title included, right-click and type the correct version.

To prevent this in future, use **Edit Name Structure** in the Redact phase to define how names should appear.

### Merged Names Looking Odd
If you merged name variants in the Redact phase, the fullest version (your merge target) should appear in the restored document. If something looks off, you can still edit individual replacements here.

### Missing Information
If the AI removed something you needed, go back to the Improve phase (if possible) or note it for next time. You can also manually edit the final document after copying.

---

## Tips

- **Scan the full document** — Don't just check the sidebar; read through to catch anything that looks off
- **Edit replacements for consistency** — If you want "Ms Chen" throughout rather than mixing "Ms Chen" and "Jenny Chen," edit here
- **Copy and review** — Even after copying, give the document a final read in your records system before saving

---

## After You're Done

Your restored document is now standard documentation—no placeholders, no Redactor formatting. It's ready for your records, to send to other providers, or for any other professional use.

The privacy protection happened during processing. The final document is clean and complete.
"""
}
