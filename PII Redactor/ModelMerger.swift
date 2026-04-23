import Foundation
import SwiftProtobuf

/// Reads a descriptor `.onnx` file and its sibling `.onnx_data` weight blob,
/// inlines every TensorProto's external-data reference into `raw_data`, and
/// writes a single self-contained `.onnx` to disk.
///
/// Why this exists: ORT 1.24.2's CoreML execution provider pre-inlines
/// external weights through `TensorProtoWithExternalDataToTensorProto`
/// (model_builder.cc:790), passing the full model *file* path as the base
/// instead of the containing directory. Result: the path joins to
/// `<modelPath>/<externalName>` and fails with ENOTDIR. The CPU EP takes a
/// different code path and works fine. By inlining external data ourselves
/// before handing the file to ORT, we skip the buggy code path entirely and
/// can re-enable CoreML/ANE acceleration.
enum ModelMerger {
    enum MergeError: LocalizedError {
        case missingExternalKey(String)
        case shortRead(location: String, wanted: Int, got: Int)
        case ioError(location: String, underlying: Error)

        var errorDescription: String? {
            switch self {
            case .missingExternalKey(let key):
                "ONNX external_data entry is missing required key `\(key)`."
            case .shortRead(let location, let wanted, let got):
                "External data file `\(location)` short read: wanted \(wanted) bytes, got \(got)."
            case .ioError(let location, let underlying):
                "Reading external data `\(location)` failed: \(underlying.localizedDescription)"
            }
        }
    }

    /// Merge external-data references and write the resulting self-contained
    /// ONNX model to `outputURL`.
    ///
    /// Safe to re-run: if `outputURL` exists and is newer than `modelURL`,
    /// the caller should typically skip this call — this function always
    /// regenerates the output.
    static func mergeExternalData(
        modelURL: URL,
        outputURL: URL,
        progress: @Sendable (Double) -> Void = { _ in }
    ) throws {
        let modelBytes = try Data(contentsOf: modelURL)
        var model = try Onnx_ModelProto(serializedBytes: modelBytes)

        let modelDir = modelURL.deletingLastPathComponent()

        // mmap the external-data file(s) once. Most exports use a single file
        // (here: `model_q4.onnx_data`, ~917 MB). The OS pages in as needed.
        var mmaps: [String: Data] = [:]
        func ensureMmap(for location: String) throws -> Data {
            if let cached = mmaps[location] { return cached }
            let url = modelDir.appendingPathComponent(location)
            do {
                let data = try Data(contentsOf: url, options: [.mappedIfSafe])
                mmaps[location] = data
                return data
            } catch {
                throw MergeError.ioError(location: location, underlying: error)
            }
        }

        let count = model.graph.initializer.count
        guard count > 0 else {
            try model.serializedData().write(to: outputURL, options: [.atomic])
            progress(1.0)
            return
        }

        var inlinedCount = 0
        for idx in 0..<count {
            let tensor = model.graph.initializer[idx]
            guard tensor.dataLocation == .external else { continue }

            var entries: [String: String] = [:]
            entries.reserveCapacity(tensor.externalData.count)
            for e in tensor.externalData {
                entries[e.key] = e.value
            }

            guard let location = entries["location"] else {
                throw MergeError.missingExternalKey("location")
            }
            // offset defaults to 0, length may be absent if the data runs to EOF
            let offset = Int(entries["offset"].flatMap { Int($0) } ?? 0)

            let mmap = try ensureMmap(for: location)
            let remaining = mmap.count - offset
            let length: Int = {
                if let l = entries["length"].flatMap({ Int($0) }) { return l }
                return remaining
            }()
            guard length >= 0, offset >= 0, offset + length <= mmap.count else {
                throw MergeError.shortRead(
                    location: location,
                    wanted: length,
                    got: max(0, mmap.count - offset)
                )
            }

            let start = mmap.startIndex + offset
            let end = start + length
            let slice = mmap.subdata(in: start..<end)

            var updated = tensor
            updated.rawData = slice
            updated.dataLocation = .default
            updated.externalData = []
            model.graph.initializer[idx] = updated

            inlinedCount += 1
            if inlinedCount % 32 == 0 {
                progress(Double(idx + 1) / Double(count))
            }
        }

        let merged = try model.serializedData()
        try merged.write(to: outputURL, options: [.atomic])
        progress(1.0)
    }
}
