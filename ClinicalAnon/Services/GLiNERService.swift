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
/// The Python bundle (runtime + model) is downloaded on first use and cached locally
@MainActor
class GLiNERService: ObservableObject {

    // MARK: - Singleton

    static let shared = GLiNERService()

    // MARK: - Published Properties

    @Published private(set) var isAvailable = true  // Always available (downloads on demand)
    @Published private(set) var isModelLoaded = false
    @Published private(set) var isProcessing = false
    @Published private(set) var isDownloading = false
    @Published private(set) var downloadProgress: Double = 0
    @Published private(set) var lastError: String?

    // MARK: - Constants

    /// URL to download the GLiNER Python bundle (tar.gz)
    /// TODO: Replace with actual hosted URL
    private let bundleDownloadURL = "https://github.com/YOUR_REPO/releases/download/v1.0/gliner_bundle.tar.gz"

    /// Expected bundle size for progress calculation (~730MB compressed)
    private let expectedBundleSize: Int64 = 730_000_000

    /// Default PII entity labels to search for
    private let entityLabels = [
        "person",
        "organization",
        "phone number",
        "email",
        "address",
        "date of birth",
        "social security number",
        "credit card number",
        "bank account number",
        "passport number",
        "driver license number",
        "health insurance id",
        "medical record number",
        "ip address"
    ]

    /// Confidence threshold for entity detection
    private let confidenceThreshold: Double = 0.5

    // MARK: - Cache Paths

    private var cacheDirectory: URL {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return cacheDir.appendingPathComponent("GLiNER")
    }

    /// Path to the bundled Python bundle directory
    private var bundlePath: URL {
        return cacheDirectory.appendingPathComponent("gliner_bundle")
    }

    /// Path to the Python interpreter in the bundle
    private var pythonPath: URL {
        return bundlePath.appendingPathComponent("gliner-env/bin/python3")
    }

    /// Path to the gliner_scan.py script
    private var scriptPath: URL {
        return bundlePath.appendingPathComponent("gliner_scan.py")
    }

    /// Check if the bundle is cached and valid
    var isModelCached: Bool {
        return FileManager.default.fileExists(atPath: pythonPath.path) &&
               FileManager.default.fileExists(atPath: scriptPath.path)
    }

    // MARK: - Initialization

    private init() {
        print("GLiNERService: Initialized (Bundled Python mode)")
    }

    // MARK: - Public Methods

    /// Download and extract the GLiNER Python bundle
    func downloadModel() async throws {
        guard !isDownloading else { return }

        isDownloading = true
        downloadProgress = 0
        lastError = nil

        print("GLiNERService: Starting bundle download...")

        do {
            // Create cache directory if needed
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

            // Download bundle archive
            let archivePath = cacheDirectory.appendingPathComponent("gliner_bundle.tar.gz")
            try await downloadBundle(to: archivePath)

            // Extract bundle
            print("GLiNERService: Extracting bundle...")
            downloadProgress = 0.95

            // Remove existing bundle if present
            if FileManager.default.fileExists(atPath: bundlePath.path) {
                try FileManager.default.removeItem(at: bundlePath)
            }

            // Create bundle directory
            try FileManager.default.createDirectory(at: bundlePath, withIntermediateDirectories: true)

            // Extract using tar
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            task.arguments = ["-xzf", archivePath.path, "-C", bundlePath.path]
            try task.run()
            task.waitUntilExit()

            guard task.terminationStatus == 0 else {
                throw AppError.localLLMModelLoadFailed("Failed to extract bundle")
            }

            // Clean up archive
            try? FileManager.default.removeItem(at: archivePath)

            // Make Python executable
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: pythonPath.path
            )

            isDownloading = false
            isModelLoaded = true
            downloadProgress = 1.0
            print("GLiNERService: Bundle download and extraction complete")

        } catch {
            isDownloading = false
            print("GLiNERService: Download failed: \(error)")
            lastError = error.localizedDescription
            throw AppError.localLLMModelLoadFailed(error.localizedDescription)
        }
    }

    /// Load the model (just verify bundle exists)
    func loadModel() async throws {
        if isModelCached {
            isModelLoaded = true
            print("GLiNERService: Bundle already cached")
        } else {
            try await downloadModel()
        }
    }

    /// Unload the model (no-op for subprocess approach)
    func unloadModel() {
        isModelLoaded = false
    }

    /// Run PII scan on text
    func runPIIScan(text: String, existingEntities: [Entity]) async throws -> [PIIFinding] {
        guard isModelCached else {
            try await downloadModel()
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

    /// Download the bundle archive from URL
    private func downloadBundle(to destination: URL) async throws {
        guard let url = URL(string: bundleDownloadURL) else {
            throw AppError.invalidResponse
        }

        print("GLiNERService: Fetching \(bundleDownloadURL)")

        let (asyncBytes, response) = try await URLSession.shared.bytes(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            print("GLiNERService: HTTP \(statusCode)")
            throw AppError.invalidResponse
        }

        let totalSize = httpResponse.expectedContentLength > 0 ? httpResponse.expectedContentLength : expectedBundleSize

        var data = Data()
        data.reserveCapacity(Int(totalSize))

        for try await byte in asyncBytes {
            data.append(byte)

            // Update progress periodically (0-90% for download, 90-100% for extraction)
            if data.count % 1_000_000 == 0 {
                let progress = Double(data.count) / Double(totalSize) * 0.9
                await MainActor.run {
                    self.downloadProgress = min(progress, 0.9)
                }
            }
        }

        print("GLiNERService: Downloaded \(data.count) bytes")
        try data.write(to: destination)
    }

    /// Run the Python script as subprocess
    private func runPythonScan(text: String) async throws -> [GLiNEREntity] {
        let input = GLiNERInput(
            text: text,
            labels: entityLabels,
            threshold: confidenceThreshold
        )

        let inputJSON = try JSONEncoder().encode(input)

        // Capture URLs before entering async context to avoid Sendable warnings
        let pythonURL = pythonPath
        let scriptURL = scriptPath

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let process = Process()
                    process.executableURL = pythonURL
                    process.arguments = [scriptURL.path, "--stdin"]

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
        case "person", "name":
            return .personOther
        case "organization", "company":
            return .organization
        case "phone number", "mobile phone number", "email":
            return .contact
        case "address", "location":
            return .location
        case "date of birth", "dob":
            return .date
        case "social security number", "ssn", "credit card number", "bank account number",
             "passport number", "driver license number", "health insurance id",
             "medical record number", "mrn", "ip address":
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
