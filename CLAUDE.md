# CLAUDE.md

Orientation for Claude Code (and any AI collaborator) working in this repo.

## What this project is

**SafePaste** is an open-source (MIT) macOS app that redacts PII from PDFs
entirely on-device. Text model + PDFKit + SwiftUI. The user name shown
in-app and in marketing is "SafePaste"; the Xcode target + source folders
are still named "PII Redactor" from the original template (soft-rename  -
renaming the folders involves a risky pbxproj shuffle, deferred).

**Distribution**: direct download from the team's website, not the Mac App
Store. Repo is MIT so anyone can build from source for free; the signed,
notarized binary is sold as a separate paid download. Don't propose MAS
submission work (StoreKit receipt validation, MAS sandbox quirks, App Store
Connect pricing) - it's explicitly off the roadmap.

The underlying ML pipeline is `openai/privacy-filter` (a token-classification
model) running via ONNX Runtime with the CoreML execution provider. Exported
PDFs use **image-rewrite redaction**: each page is rasterized, black boxes are
painted over PII rectangles, and the result is a new PDF with no recoverable
text layer for the redacted regions.

## Build / run commands

```bash
# Debug build on Apple Silicon
xcodebuild -project "PII Redactor.xcodeproj" \
  -scheme "PII Redactor" -configuration Debug \
  -destination "platform=macOS,arch=arm64" build

# Universal Release (arm64 + x86_64)
xcodebuild -project "PII Redactor.xcodeproj" \
  -scheme "PII Redactor" -configuration Release \
  -destination "generic/platform=macOS" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build

# Resolve SPM deps (fixes "failed downloading" cache errors)
xcodebuild -project "PII Redactor.xcodeproj" -resolvePackageDependencies
```

The model is **not bundled in the repo or the .app**. First launch
downloads the ~917 MB ONNX weights from HuggingFace Hub into
`~/Library/Containers/com.kamban.safepaste/Data/Library/Caches/huggingface/`
and runs `ModelMerger` once to produce a self-contained merged `.onnx`.
Subsequent launches reuse that cached file with no network.

No test suite yet. Verification is end-to-end: drop a PDF with PII, check the
sidebar detections, export, inspect the resulting PDF in Preview.

## Key files by layer

| Layer | Files | Role |
|---|---|---|
| Design tokens | `PII Redactor/DesignSystem.swift` | All colors, spacing, fonts, the 8-category palette (color + icon + title). Any new view should read from here. |
| Model runtime | `PII Redactor/PrivacyFilter.swift` | `actor PrivacyFilter` - loads model, runs per-text detection, emits `RedactionSpan`s. |
| Model prep | `PII Redactor/ModelMerger.swift` | Inlines ONNX external weights into a single `.onnx` file - required workaround for ORT CoreML EP bug (see "Gotchas"). |
| Protobuf | `PII Redactor/Onnx.pb.swift` | Generated from `onnx/onnx.proto v1.17.0`. **Do not hand-edit.** Regenerate via `protoc --swift_opt=Visibility=Public --swift_out=. onnx.proto`. |
| PDF pipeline | `PII Redactor/PDFExtractor.swift` | PDFKit → page text + PDFPage reference. |
|  | `PII Redactor/Redaction.swift` | `PageSpan`, `DocumentSpans`, `SpanMapper` - maps model spans to PDF rectangles. |
|  | `PII Redactor/PDFRedactor.swift` | Image-rewrite export - renders each page as a bitmap + overlays black rects. |
| Orchestration | `PII Redactor/DocumentController.swift` | `@MainActor ObservableObject` driving model prep, load, detection, export. |
| UI | `PII Redactor/RootView.swift` | Router: empty state ↔ document view, model-preparing overlay, toolbar. |
|  | `PII Redactor/EmptyStateView.swift` | First-launch drop zone + feature cards. |
|  | `PII Redactor/DocumentView.swift` | Loaded-doc workspace: header + sidebar + canvas + export status bar. |
|  | `PII Redactor/EntitySidebar.swift` | Category chips + grouped entity list. |
|  | `PII Redactor/PDFCanvasView.swift` | `NSViewRepresentable` wrapping `PDFView` with translucent overlay annotations. |
| App entry | `PII Redactor/PII_RedactorApp.swift` | `@main`, menu commands (⌘O, ⇧⌘E). |

## Architectural decisions worth knowing

### 1. Image-rewrite redaction, not PDF content-stream editing

`PDFRedactor` renders each PDF page to a bitmap and writes that as the new
page - the source PDF's text layer doesn't survive. Any selection, copy, or
PDF-to-text extraction on the output yields no PII. This is simpler than
editing the PDF content stream in-place (which would need PSPDFKit or a
hand-rolled content-stream editor) and is genuinely more thorough: the data is
gone, not just visually covered.

Tradeoff: exported PDFs have no selectable text anywhere, not just in
redacted regions. Users expecting Adobe-Acrobat-style "redact these spans but
leave everything else selectable" will be surprised. Acceptable for v0.1.

### 2. Span rectangles come from PDFKit native selection, not from a manual bounds array

See `SpanMapper.mapSpans` in `Redaction.swift`. We search for the literal PII
text in `page.text` (walking a cursor forward to disambiguate duplicates),
then call `PDFPage.selection(for: NSRange)` and `selectionsByLine()` for
pixel-accurate rects. Early implementation used per-scalar
`PDFPage.characterBounds(at:)` + a manual line-fusion heuristic, indexed by
the token-decoded offset - that drifted by 1–3 characters because BPE
encode/decode isn't exactly identity. Don't revert to offset-based indexing.

### 3. ModelMerger inlines external weights

The raw `openai/privacy-filter` ONNX ships as `model_q4.onnx` (160 KB
descriptor) + `model_q4.onnx_data` (917 MB weights). ORT 1.24.2's CoreML EP
passes the model's full file path (not its directory) as the base for
resolving external-data references, producing paths like
`<modelFile>/<externalName>` which fail with `ENOTDIR`. See
`model_builder.cc:790` at `microsoft/onnxruntime@v1.24.2`.

`ModelMerger.mergeExternalData` decodes the descriptor with SwiftProtobuf,
reads each external-data slice out of the `.onnx_data` file, sets it as
inline `rawData`, clears the external reference, and writes a single merged
`.onnx` to Caches. First run spends ~10–20 s on this; subsequent runs reuse
the cache.

### 4. MainActor isolation default removed

The project has **not** set `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` on
purpose - that default was applying MainActor to the generated protobuf
types, breaking their `Sendable` conformance to SwiftProtobuf's `Message`
protocol. Types that genuinely need MainActor (`RedactorViewModel`, SwiftUI
`View`s) annotate it explicitly. Don't reintroduce the default.

### 5. macOS 14 minimum

ORT SPM 1.24.x ships binaries with `minos 14.0`. We need ORT ≥ 1.23 for this
specific model's `GatherBlockQuantized` op variant (has the `bits`
attribute). ORT 1.20 SPM supports macOS 11+ but can't load this model. ORT
1.21–1.23 don't have SPM releases. So macOS 14 minimum is a forced floor,
not a choice. Don't try to lower the deployment target without first
swapping the ORT runtime distribution.

### 6. Model variant = q4

`PrivacyFilter.ModelVariant.q4` (`model_q4.onnx`, int4 weights, fp32 logits).
`.quantized` (int8) is also wired if smaller model size is ever preferred.
Don't add fp16 variants - the ORT Obj-C binding doesn't expose a `.float16`
element type, so we can't read fp16 logits.

## Gotchas

- **First-run network**: without `./Scripts/bundle-model.sh`, the app
  downloads ~917 MB from HuggingFace Hub on first launch. Dev builds on
  slow networks can take ages.
- **Sandbox + quarantine**: downloaded model files get
  `com.apple.quarantine` xattrs (harmless for reads, but worth knowing if
  debugging a "file not found" error).
- **PDF character indices are UTF-16, not Unicode scalars**: when bridging
  to PDFKit, use `NSRange` over `page.text`, not scalar offsets.
- **CoreML EP partition count is low**: ~148/331 nodes get accepted by CoreML
  on Apple Silicon. The rest run on CPU. Don't spend time optimizing the
  partition count - the model is small and the CoreML↔CPU boundary cost is
  marginal.
- **Tokenizer offsets are in decoded space, not input space**: if you need
  input-space offsets, locate by text search in `page.text` (what
  `SpanMapper` does). Don't trust `RedactionSpan.start`/`end` against the
  original text directly.

## Conventions

- **Spacing**: 8-pt grid via `Design.Space` (xxs=4, xs=8, sm=12, md=16,
  lg=24, xl=32, xxl=48). Don't hard-code spacing values.
- **Category colors/icons/titles**: read from `Design.Category`. Adding a new
  category means updating its `rawLabels`, `displayOrder`, palette entries.
- **Sendability**: prefer `actor` for anything that owns model state or
  external sessions. `@MainActor` only on view models and Views.
- **SwiftUI previews**: not wired up project-wide yet. Adding `#Preview` to
  new views is welcome.
- **Git commits**: descriptive subject + wrapped body. The trailer
  `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`
  is appropriate when Claude materially contributed.
- **Punctuation**: no em-dashes (`U+2014`) and no smart quotes (`U+2018`,
  `U+2019`, `U+201C`, `U+201D`) anywhere: source files, comments, UI copy,
  commit messages, docs. Use ` - ` (ASCII hyphen with spaces) or split the
  sentence instead of an em-dash. Use straight quotes `'` and `"` only.
  Applies to everything you author, not just code.

## What this repo is **not**

- Not a general-purpose ML inference wrapper. It's tailored to
  `openai/privacy-filter`'s exact architecture and labels.
- Not a PDF editor. It only consumes and produces PDFs - no page reorder,
  annotation, signing, etc.
- Not a cloud product. Any contribution that phones home or adds telemetry
  (beyond the one-time HuggingFace model download) will be rejected.
- Not a Mac App Store app. Distribution is direct-download DMG from the
  team's website.
