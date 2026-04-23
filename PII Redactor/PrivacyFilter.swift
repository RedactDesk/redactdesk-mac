import Foundation
import Hub
import OnnxRuntimeBindings
import Tokenizers

/// A detected PII span inside a piece of text.
struct RedactionSpan: Identifiable, Equatable, Sendable {
    let id = UUID()
    /// The entity class, e.g. `private_person`, `private_email`, `secret`.
    let label: String
    /// Inclusive start offset in `RedactionResult.text` (Unicode scalars).
    let start: Int
    /// Exclusive end offset in `RedactionResult.text` (Unicode scalars).
    let end: Int
    /// The literal text slice.
    let text: String

    /// Human-readable label for UI display.
    var displayLabel: String {
        switch label {
        case "private_person": "person"
        case "private_email": "email"
        case "private_phone": "phone"
        case "private_address": "address"
        case "private_date": "date"
        case "private_url": "url"
        case "account_number": "account"
        case "secret": "secret"
        default: label
        }
    }
}

struct RedactionResult: Sendable {
    /// The text after tokenization + detokenization (should equal the input
    /// for non-degenerate BPE inputs).
    let text: String
    let spans: [RedactionSpan]

    /// Produces a redacted copy of `text`, replacing each span with a placeholder.
    func redact(placeholder: (RedactionSpan) -> String = { "[\($0.displayLabel.uppercased())]" }) -> String {
        guard !spans.isEmpty else { return text }
        let scalars = Array(text.unicodeScalars)
        var out = ""
        var cursor = 0
        for span in spans.sorted(by: { $0.start < $1.start }) {
            if span.start > cursor {
                out += String(String.UnicodeScalarView(scalars[cursor..<span.start]))
            }
            out += placeholder(span)
            cursor = span.end
        }
        if cursor < scalars.count {
            out += String(String.UnicodeScalarView(scalars[cursor..<scalars.count]))
        }
        return out
    }
}

enum PrivacyFilterError: LocalizedError {
    case notLoaded
    case missingOutput(String)
    case unsupportedLogitsType(Int32)

    var errorDescription: String? {
        switch self {
        case .notLoaded: "Model is not loaded yet."
        case .missingOutput(let name): "Model output `\(name)` was missing."
        case .unsupportedLogitsType(let raw): "Model logits had unsupported element type \(raw)."
        }
    }
}

/// Wraps an ONNX Runtime session for `openai/privacy-filter` and applies BIOES
/// post-processing to produce PII spans from raw token-classification logits.
actor PrivacyFilter {
    enum ModelVariant: String, CaseIterable, Sendable {
        case quantized = "model_quantized.onnx" // ~1.6 GB int8
        case q4 = "model_q4.onnx"              // ~920 MB int4

        var downloadGlob: String { "onnx/\(rawValue)*" }
        /// Filename (not path) of the self-contained model we emit after
        /// inlining external weights. Written into the same `onnx/` directory.
        var mergedFilename: String {
            (rawValue as NSString).deletingPathExtension + ".merged.onnx"
        }
    }

    private let repoID: String
    private let variant: ModelVariant

    private var tokenizer: (any Tokenizer)?
    private var session: ORTSession?
    private var env: ORTEnv?
    private var labels: [String] = []
    private var inputNames: Set<String> = []

    init(repoID: String = "openai/privacy-filter", variant: ModelVariant = .q4) {
        self.repoID = repoID
        self.variant = variant
    }

    var isLoaded: Bool { session != nil && tokenizer != nil }

    /// Downloads the model + tokenizer (cached across runs), pre-inlines the
    /// ONNX external weights (required to unblock CoreML EP — see ModelMerger),
    /// and prepares an ORT session with CoreML/ANE acceleration enabled.
    func load(progress: @Sendable @escaping (Double) -> Void) async throws {
        let hub = HubApi.shared
        let repo = Hub.Repo(id: repoID)
        let globs = [
            "config.json",
            "tokenizer.json",
            "tokenizer_config.json",
            "viterbi_calibration.json",
            variant.downloadGlob,
        ]
        // Phase A: download weights (~810 MB–1.6 GB, cached). Map 0...0.85.
        let modelDir = try await hub.snapshot(from: repo, matching: globs) { p in
            progress(min(0.85, p.fractionCompleted * 0.85))
        }

        let tokenizer = try await AutoTokenizer.from(modelFolder: modelDir)

        let configURL = modelDir.appendingPathComponent("config.json")
        let configData = try Data(contentsOf: configURL)
        let labels = try Self.parseLabels(from: configData)

        // Phase B: merge external data if we haven't already. Map 0.85...0.98.
        let onnxDir = modelDir.appendingPathComponent("onnx")
        let originalURL = onnxDir.appendingPathComponent(variant.rawValue)
        let mergedURL = onnxDir.appendingPathComponent(variant.mergedFilename)
        let fm = FileManager.default
        if !fm.fileExists(atPath: mergedURL.path) {
            try ModelMerger.mergeExternalData(modelURL: originalURL, outputURL: mergedURL) { f in
                progress(0.85 + f * 0.13)
            }
        }

        // Phase C: build the session with CoreML EP. Map 0.98...1.0.
        progress(0.98)

        let env = try ORTEnv(loggingLevel: .warning)
        let options = try ORTSessionOptions()
        try options.setGraphOptimizationLevel(.all)
        try options.setIntraOpNumThreads(0)

        // Re-enabled now that external data is inlined. MLProgram + All compute
        // units lets CoreML pick across ANE/GPU/CPU on Apple Silicon; on Intel
        // Macs (no ANE) it falls back to CPU+GPU automatically.
        if ORTIsCoreMLExecutionProviderAvailable() {
            try? options.appendCoreMLExecutionProvider(withOptionsV2: [
                "MLComputeUnits": "All",
                "ModelFormat": "MLProgram",
            ])
        }

        let session = try ORTSession(
            env: env,
            modelPath: mergedURL.path,
            sessionOptions: options
        )
        let names = (try? session.inputNames()) ?? ["input_ids", "attention_mask"]

        self.env = env
        self.session = session
        self.tokenizer = tokenizer
        self.labels = labels
        self.inputNames = Set(names)
        progress(1.0)
    }

    /// Runs inference and returns detected PII spans.
    func detect(text: String, maxTokens: Int = 2048) throws -> RedactionResult {
        guard let tokenizer, let session else { throw PrivacyFilterError.notLoaded }
        guard !text.isEmpty else { return RedactionResult(text: text, spans: []) }

        let ids = tokenizer.encode(text: text, addSpecialTokens: false)
        let truncated = Array(ids.prefix(maxTokens))
        guard !truncated.isEmpty else { return RedactionResult(text: text, spans: []) }

        let seqLen = truncated.count
        let shape: [NSNumber] = [1, NSNumber(value: seqLen)]
        let int64Ids = truncated.map { Int64($0) }
        let mask = Array(repeating: Int64(1), count: seqLen)

        var feeds: [String: ORTValue] = [:]
        feeds["input_ids"] = try Self.makeInt64Tensor(int64Ids, shape: shape)
        if inputNames.contains("attention_mask") {
            feeds["attention_mask"] = try Self.makeInt64Tensor(mask, shape: shape)
        }
        if inputNames.contains("position_ids") {
            let positions = (0..<Int64(seqLen)).map { $0 }
            feeds["position_ids"] = try Self.makeInt64Tensor(positions, shape: shape)
        }

        let outputs = try session.run(
            withInputs: feeds,
            outputNames: Set(["logits"]),
            runOptions: nil
        )
        guard let logits = outputs["logits"] else {
            throw PrivacyFilterError.missingOutput("logits")
        }

        let info = try logits.tensorTypeAndShapeInfo()
        let outShape = info.shape.map(\.intValue)
        let numLabels = outShape.last ?? max(labels.count, 33)
        let data = try logits.tensorData() as Data

        let predicted: [Int] = try Self.argmaxPerToken(
            data: data,
            elementType: info.elementType,
            seqLen: seqLen,
            numLabels: numLabels
        )

        let predictedLabels: [String] = predicted.map { idx in
            labels.indices.contains(idx) ? labels[idx] : "O"
        }

        // Build per-token character end offsets by decoding progressively longer
        // prefixes. This costs O(n) decode calls but is O(n) total work because
        // the BPE decoder short-circuits on shared prefixes internally.
        var charEnds: [Int] = []
        charEnds.reserveCapacity(seqLen)
        for i in 0..<seqLen {
            let prefix = tokenizer.decode(
                tokens: Array(truncated.prefix(i + 1)),
                skipSpecialTokens: true
            )
            charEnds.append(prefix.unicodeScalars.count)
        }
        let fullDecoded = tokenizer.decode(tokens: truncated, skipSpecialTokens: true)

        let spans = Self.mergeBIOES(
            labels: predictedLabels,
            charEnds: charEnds,
            in: fullDecoded
        )
        return RedactionResult(text: fullDecoded, spans: spans)
    }

    // MARK: - Helpers

    private static func parseLabels(from data: Data) throws -> [String] {
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let id2label = obj?["id2label"] as? [String: String] else { return [] }
        let count = id2label.keys.compactMap(Int.init).max().map { $0 + 1 } ?? 0
        return (0..<count).map { id2label[String($0)] ?? "O" }
    }

    private static func makeInt64Tensor(_ values: [Int64], shape: [NSNumber]) throws -> ORTValue {
        let byteCount = values.count * MemoryLayout<Int64>.stride
        let data = NSMutableData(length: byteCount)!
        _ = values.withUnsafeBufferPointer { buf in
            memcpy(data.mutableBytes, buf.baseAddress, byteCount)
        }
        return try ORTValue(tensorData: data, elementType: .int64, shape: shape)
    }

    private static func argmaxPerToken(
        data: Data,
        elementType: ORTTensorElementDataType,
        seqLen: Int,
        numLabels: Int
    ) throws -> [Int] {
        var out = [Int](repeating: 0, count: seqLen)
        guard elementType == .float else {
            throw PrivacyFilterError.unsupportedLogitsType(Int32(elementType.rawValue))
        }
        data.withUnsafeBytes { raw in
            let buf = raw.bindMemory(to: Float.self)
            for t in 0..<seqLen {
                var bestIdx = 0
                var bestVal = -Float.infinity
                for j in 0..<numLabels {
                    let v = buf[t * numLabels + j]
                    if v > bestVal { bestVal = v; bestIdx = j }
                }
                out[t] = bestIdx
            }
        }
        return out
    }

    /// Merges BIOES per-token labels into contiguous character spans.
    private static func mergeBIOES(
        labels: [String],
        charEnds: [Int],
        in text: String
    ) -> [RedactionSpan] {
        var spans: [RedactionSpan] = []
        let scalars = Array(text.unicodeScalars)
        var current: (label: String, start: Int)?

        func close(end: Int) {
            guard let c = current else { return }
            let safeStart = min(max(0, c.start), scalars.count)
            let safeEnd = min(max(safeStart, end), scalars.count)
            let slice = String(String.UnicodeScalarView(scalars[safeStart..<safeEnd]))
            spans.append(
                RedactionSpan(label: c.label, start: safeStart, end: safeEnd, text: slice)
            )
            current = nil
        }

        for i in 0..<labels.count {
            let label = labels[i]
            let tokStart = i == 0 ? 0 : charEnds[i - 1]
            let tokEnd = charEnds[i]

            if label == "O" {
                close(end: tokStart)
                continue
            }
            let prefix = label.prefix(2)
            let entity = String(label.dropFirst(2))

            switch prefix {
            case "B-":
                close(end: tokStart)
                current = (entity, tokStart)
            case "S-":
                close(end: tokStart)
                current = (entity, tokStart)
                close(end: tokEnd)
            case "I-":
                if current?.label != entity {
                    close(end: tokStart)
                    current = (entity, tokStart)
                }
            case "E-":
                if current?.label != entity {
                    close(end: tokStart)
                    current = (entity, tokStart)
                }
                close(end: tokEnd)
            default:
                close(end: tokStart)
            }
        }
        close(end: charEnds.last ?? 0)
        return spans
    }
}
