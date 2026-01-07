//
//  GLiNERService.swift
//  Redactor
//
//  Purpose: GLiNER-based PII detection using bundled Python environment
//  Organization: 3 Big Things
//

import Foundation

// MARK: - GLiNER Service

/// Provides PII detection using the GLiNER model via bundled Python subprocess
/// The Python bundle (runtime + model) is included in the app bundle
@MainActor
class GLiNERService: ObservableObject {

    // MARK: - Singleton

    static let shared = GLiNERService()

    // MARK: - Published Properties

    @Published private(set) var isAvailable = false  // Set to true when bundle is verified
    @Published private(set) var isModelLoaded = false
    @Published private(set) var isProcessing = false
    @Published private(set) var lastError: String?

    // MARK: - Constants

    /// Default PII entity labels to search for
    private let entityLabels = [
        "person",
        "name",
        "patient name",
        "doctor name",
        "organization",
        "hospital",
        "clinic",
        "phone number",
        "email",
        "address",
        "location",
        "city",
        "date",
        "date of birth",
        "social security number",
        "credit card number",
        "bank account number",
        "passport number",
        "driver license number",
        "health insurance id",
        "medical record number",
        "account number",
        "id number",
        "ip address"
    ]

    /// Confidence threshold for entity detection (lower = more sensitive)
    private let confidenceThreshold: Double = 0.15

    // MARK: - Bundle Paths

    /// Path to the GLiNERBundle directory in app resources
    private var bundlePath: URL {
        Bundle.main.resourceURL!.appendingPathComponent("GLiNERBundle")
    }

    /// Path to the Python interpreter in the bundle
    private var pythonPath: URL {
        bundlePath.appendingPathComponent("python/bin/python3")
    }

    /// Path to the gliner_scan.py script
    private var scriptPath: URL {
        bundlePath.appendingPathComponent("gliner_scan.py")
    }

    /// Check if the bundle exists in app resources
    var isBundleValid: Bool {
        FileManager.default.fileExists(atPath: pythonPath.path) &&
        FileManager.default.fileExists(atPath: scriptPath.path)
    }

    // MARK: - Initialization

    private init() {
        print("GLiNERService: Initialized (App-bundled Python mode)")
        // Verify bundle exists on init
        if isBundleValid {
            isAvailable = true
            isModelLoaded = true
            print("GLiNERService: Bundle verified at \(bundlePath.path)")
        } else {
            print("GLiNERService: WARNING - Bundle not found at \(bundlePath.path)")
            lastError = "GLiNER bundle not found in app resources"
        }
    }

    // MARK: - Public Methods

    /// Verify the bundle is available (no download needed - bundled with app)
    func loadModel() async throws {
        if isBundleValid {
            isAvailable = true
            isModelLoaded = true
            print("GLiNERService: Bundle ready")
        } else {
            let error = "GLiNER bundle not found. Please reinstall the application."
            lastError = error
            throw AppError.localLLMModelLoadFailed(error)
        }
    }

    /// Unload the model (no-op for subprocess approach)
    func unloadModel() {
        isModelLoaded = false
    }

    /// Run PII scan on text
    func runPIIScan(text: String, existingEntities: [Entity]) async throws -> [PIIFinding] {
        guard isBundleValid else {
            throw AppError.localLLMModelLoadFailed("GLiNER bundle not available")
        }

        isProcessing = true
        defer { isProcessing = false }

        print("GLiNERService: Starting PII scan (length: \(text.count))")
        let startTime = Date()

        // Split into chunks for long documents
        let chunks = ChunkManager.splitWithOverlap(
            text,
            chunkSize: 4000,  // Larger chunks OK for Python approach
            overlap: 200
        )
        print("GLiNERService: Split into \(chunks.count) chunk(s)")

        var allEntities: [GLiNEREntity] = []

        for (chunkIndex, chunk) in chunks.enumerated() {
            print("GLiNERService: Processing chunk \(chunkIndex + 1)/\(chunks.count)")

            let chunkEntities = try await runPythonScan(text: chunk.text)

            // Adjust positions for global document coordinates
            let globalEntities = chunkEntities.map { entity -> GLiNEREntity in
                GLiNEREntity(
                    text: entity.text,
                    label: entity.label,
                    start: entity.start + chunk.globalOffset,
                    end: entity.end + chunk.globalOffset,
                    confidence: entity.confidence
                )
            }

            allEntities.append(contentsOf: globalEntities)
        }

        // Deduplicate entities from overlapping chunks
        let deduplicated = deduplicateEntities(allEntities)

        let elapsed = Date().timeIntervalSince(startTime)
        print("GLiNERService: Scan completed in \(String(format: "%.3f", elapsed))s, found \(deduplicated.count) entities")

        // Convert to PIIFindings and filter against existing entities
        let findings = deduplicated.compactMap { entity -> PIIFinding? in
            let normalizedEntityText = entity.text.lowercased()
            let alreadyCovered = existingEntities.contains { existing in
                existing.originalText.lowercased() == normalizedEntityText ||
                normalizedEntityText.contains(existing.originalText.lowercased()) ||
                existing.originalText.lowercased().contains(normalizedEntityText)
            }

            if alreadyCovered {
                return nil
            }

            // Filter out clinical terms
            if NERUtilities.isClinicalTerm(entity.text) {
                print("GLiNERService: '\(entity.text)' filtered as clinical term")
                return nil
            }

            return PIIFinding(
                text: entity.text,
                suggestedType: mapGLiNERLabel(entity.label),
                reason: "GLiNER: \(entity.label)",
                confidence: entity.confidence
            )
        }

        print("GLiNERService: Returning \(findings.count) new findings")
        return findings
    }

    // MARK: - Private Methods

    /// Path to the site-packages in the virtual environment
    private var sitePackagesPath: URL {
        bundlePath.appendingPathComponent("gliner-env/lib/python3.11/site-packages")
    }

    /// Run the Python script as subprocess
    private func runPythonScan(text: String) async throws -> [GLiNEREntity] {
        let input = GLiNERInput(
            text: text,
            labels: entityLabels,
            threshold: confidenceThreshold
        )

        let inputJSON = try JSONEncoder().encode(input)

        // Capture paths before entering async context to avoid Sendable warnings
        let pythonURL = pythonPath
        let scriptURL = scriptPath
        let sitePackages = sitePackagesPath.path

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let process = Process()
                    process.executableURL = pythonURL
                    process.arguments = [scriptURL.path, "--stdin"]

                    // Set PYTHONPATH so standalone Python finds packages in gliner-env
                    var env = ProcessInfo.processInfo.environment
                    env["PYTHONPATH"] = sitePackages
                    process.environment = env

                    let inputPipe = Pipe()
                    let outputPipe = Pipe()
                    let errorPipe = Pipe()

                    process.standardInput = inputPipe
                    process.standardOutput = outputPipe
                    process.standardError = errorPipe

                    try process.run()

                    // Write input
                    inputPipe.fileHandleForWriting.write(inputJSON)
                    inputPipe.fileHandleForWriting.closeFile()

                    process.waitUntilExit()

                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

                    if process.terminationStatus != 0 {
                        let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                        print("GLiNERService: Process failed: \(errorString)")
                        continuation.resume(throwing: AppError.localLLMModelLoadFailed(errorString))
                        return
                    }

                    let entities = try JSONDecoder().decode([GLiNEREntity].self, from: outputData)
                    continuation.resume(returning: entities)

                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Deduplicate entities from overlapping chunks
    private func deduplicateEntities(_ entities: [GLiNEREntity]) -> [GLiNEREntity] {
        var seen = Set<String>()
        var result: [GLiNEREntity] = []

        for entity in entities.sorted(by: { $0.confidence > $1.confidence }) {
            let key = "\(entity.start)-\(entity.end)-\(entity.text.lowercased())"
            if !seen.contains(key) {
                seen.insert(key)
                result.append(entity)
            }
        }

        return result
    }

    /// Map GLiNER labels to EntityType
    private func mapGLiNERLabel(_ label: String) -> EntityType {
        switch label.lowercased() {
        case "person", "name", "patient name", "doctor name":
            return .personOther
        case "organization", "company", "hospital", "clinic":
            return .organization
        case "phone number", "mobile phone number", "email":
            return .contact
        case "address", "location", "city":
            return .location
        case "date", "date of birth", "dob":
            return .date
        case "social security number", "ssn", "credit card number", "bank account number",
             "passport number", "driver license number", "health insurance id",
             "medical record number", "mrn", "ip address", "account number", "id number":
            return .identifier
        default:
            return .identifier  // Default to identifier for unknown PII types
        }
    }
}

// MARK: - Supporting Types

/// Input structure for Python script
private struct GLiNERInput: Codable {
    let text: String
    let labels: [String]
    let threshold: Double
}

/// Entity detected by GLiNER
private struct GLiNEREntity: Codable {
    let text: String
    let label: String
    let start: Int
    let end: Int
    let confidence: Double
}
