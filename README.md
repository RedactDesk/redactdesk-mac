# SafePaste

> Redact PII from any PDF, 100% on your Mac. No cloud, no telemetry.

Made by the [Elephas](https://elephas.app?ref=safepaste-github) team.

SafePaste is a free, open-source macOS app that removes personally identifiable
information from PDFs — names, emails, phone numbers, addresses, dates, URLs,
account numbers, and secrets — using OpenAI's
[privacy-filter](https://huggingface.co/openai/privacy-filter) model running
entirely on-device via ONNX Runtime.

- **On-device**: the model runs on your Mac's CPU, GPU, and Neural Engine. No
  network traffic after the one-time model download.
- **Image-rewrite redaction**: exported PDFs have the redacted content
  physically removed from the page — not just hidden behind a visual overlay.
  Copy-paste, accessibility APIs, and text extraction tools find nothing.
- **Eight PII categories**: people, emails, phone numbers, addresses, dates,
  URLs, account numbers, secrets. Each can be toggled on or off before export.
- **Free and MIT-licensed**.

## Status

v0.1 — text-based PDFs only (OCR for scanned documents is planned for 0.3).
macOS 14 Sonoma or later, Intel and Apple Silicon.

## Screenshots

*(to be added)*

## Building from source

### Requirements

- macOS 14+
- Xcode 16+ (Swift 5.9+)
- About 2 GB of free disk for the model + build artifacts

### Steps

```bash
git clone https://github.com/kambanthemaker/safepaste.git
cd safepaste
open "PII Redactor.xcodeproj"
# Cmd-R to build and run.
```

The first launch downloads the openai/privacy-filter ONNX weights
(~917 MB) into the app's sandbox cache (`~/Library/Containers/com.kamban.safepaste/Data/Library/Caches/`).
Subsequent launches load instantly from the local merged model.

## Distribution

SafePaste ships as a notarized direct download from the team's website
(not the Mac App Store). The repo is MIT-licensed, so you can build
from source and run locally for free. If you prefer a signed,
auto-updating binary with support, grab it from the product page.

## Architecture

Eleven Swift files grouped by layer:

| Layer | Files |
|---|---|
| Shared tokens | `DesignSystem.swift` |
| Model runtime | `PrivacyFilter.swift`, `ModelMerger.swift`, `Onnx.pb.swift` |
| PDF pipeline | `PDFExtractor.swift`, `Redaction.swift`, `PDFRedactor.swift` |
| Orchestration | `DocumentController.swift` |
| UI | `RootView.swift`, `EmptyStateView.swift`, `DocumentView.swift`, `EntitySidebar.swift`, `PDFCanvasView.swift` |

See [`CLAUDE.md`](CLAUDE.md) for architectural decisions and gotchas.

## About Elephas

SafePaste is built and maintained by the team behind
[**Elephas**](https://elephas.app?ref=safepaste-github-about) - a Mac
app for working with sensitive documents in AI. Elephas does
folder-wide redaction, summarization, and sensitive-document search,
with a fully local processing mode for teams that cannot send data to
the cloud.

SafePaste is a small, open-source slice of that world, focused on one
job: redacting PII from a single PDF, free forever. If you want the
full workflow - across folders, with chat, search, and summarization -
take a look at Elephas.

- Website: <https://elephas.app?ref=safepaste-github-about>
- SafePaste is MIT-licensed; Elephas is a separate commercial product.

## Acknowledgments

- **Model**: [openai/privacy-filter](https://huggingface.co/openai/privacy-filter) (Apache-2.0)
- **ONNX Runtime**: [microsoft/onnxruntime-swift-package-manager](https://github.com/microsoft/onnxruntime-swift-package-manager) (MIT)
- **Tokenizer + Hub downloads**: [huggingface/swift-transformers](https://github.com/huggingface/swift-transformers) (Apache-2.0)
- **Protobuf**: [apple/swift-protobuf](https://github.com/apple/swift-protobuf) (Apache-2.0)

## License

Code is MIT - see [LICENSE](LICENSE). The "SafePaste" name and icon
are a trademark of Elephas and are not covered by the MIT grant - see
[TRADEMARK.md](TRADEMARK.md) before forking.
