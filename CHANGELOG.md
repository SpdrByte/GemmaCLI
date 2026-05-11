# Changelog

All notable changes to the **Gemma CLI** will be documented in this file. This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.8.8] - 2026-05-01

### Model Migration: Gemma 3 → Gemma 4
- **Google API deprecation**: Google has deprecated all Gemma 3 models in the Generative Language API. All Gemma 3 handles have been remapped to Gemma 4 equivalents.
- **Removed API Gemma 3 models**: All Gemma 3 handles (`gemma-ultra`, `gemma-heavy`, `gemma-medium`, `gemma-small`, `gemma-nano-pro`, `gemma-nano-lite`) now map to Gemma 4 model IDs.
- **Added Gemma 4 thinking levels**: Model registry entries support an optional `thinking` field (`HIGH` or `MINIMAL`) that injects `thinkingConfig.thinkingLevel` into the API payload.
- **Unified Gemma 4 RPM**: All Gemma 4 models now use a 5 requests-per-minute limit.

### Added
- **Thinking level display**: The `/model` picker appends thinking suffixes to model IDs (e.g., `gemma-4-31b-it-high`, `gemma-4-26b-a4b-it-min`).

### Changed
- `gemma-ultra` → `gemma-4-31b-it` with `HIGH` thinking.
- `gemma-heavy` → `gemma-4-26b-a4b-it` with `HIGH` thinking.
- `gemma-medium` → `gemma-4-31b-it` with `MINIMAL` thinking.
- `gemma-small`, `gemma-nano-pro`, `gemma-nano-lite` → `gemma-4-26b-a4b-it` with `MINIMAL` thinking.

### Fixed
- Corrected REST API payload structure for Gemma 4 thinking levels: `thinkingLevel` now nests inside `thinkingConfig` within `generationConfig`, matching the official Google REST API schema.

---

## [0.8.6] - 2026-04-27

### UI Stability & Console Sync
- **Synchronous Spinner**: Refactored `Stop-Spinner` in `lib/UI.ps1` to be fully synchronous and wait for the background thread to exit, ensuring cleaner UI transitions.
- **Fixed-Line Spinner**: Implemented spinner row reservation to prevent UI artifacts or "orphaned" text from appearing in the middle of tool-generated content.
- **Console Synchronization**: Introduced `consoleLock` using `[System.Threading.Monitor]` to synchronize access between the spinner and bar tracker, eliminating race conditions and output contention in concurrent console writes.

---

## [0.8.5] - 2026-04-24

### Architectural Infrastructure
- **Sound Effect Protocol**: Implemented `PLAY_SOUND` protocol for the main-loop event listener to trigger system sounds.
- **Regex Resiliency**: Enhanced `GemmaCLI.ps1` console parser with `.*?` non-greedy anchors and `.Trim()` to ignore pipeline noise from interactive tools.
- **Timer Enhancements**: Added `sound_index` support (1-10) and an interactive hourglass UI spinner to `timer.ps1`.

### Added
- **Hybrid 83 Mechanics**: Integrated per-member health, individual attrition, and yoke-based oxen purchasing into `gemmas_trail.ps1`.
- **System Sound Integration**: Added `Alarm01` audio feedback for setup and status game events.

### Changed
- Standardized `ToolMeta` registration template in `AddingTools.md` to include all required metadata (Icon, Keywords, Tutorial, Relationships).

### Fixed
- Resolved `Test-Path` failures in sound triggers caused by "swallowed" ASCII art newlines in the regex capture group.
- Fixed oxen purchase pricing discrepancy in the store module.
- Suppressed pipeline leakage from interactive UI components (Show-ArrowMenu/Draw-Box) to ensure protocol stability.

---

## [0.8.4] - 2026-04-24

### Architectural Infrastructure
- **Multi-Backend Quota Decoupling**: Implemented independent Rate-Per-Minute (RPM) tracking for `gemma`, `gemini`, and `embedding` backends.
- **Dynamic Quota Configuration**: Established framework for model-specific RPM limits within `settings.json`.
- **Text Processing Pipeline**: Created `lib/Renderer.ps1` to centralize ANSI rendering, text formatting, and markdown parsing.

### Added
- Dedicated `embedding` backend branch in `Invoke-RpmCheck` with a 99 RPM ceiling (optimized for AI Studio free-tier research).
- `apiCallLog_Embedding` tracker for precise temporal logging of vectorization requests.
- **Robust Markdown Parser**: Implemented regex-based markdown support (bold, italic, code, headers, lists) within the rendering pipeline.

### Changed
- Increased Embedding RPM default from 15 to 99 to prevent bottlenecks during Semantic Smart Trim operations.
- Refactored `Invoke-RpmCheck` to use explicit backend branching, reducing collection unrolling risks in PowerShell.
- Migrated `Convert-ToHyperlink`, `Get-VisualWidth`, and `Format-TextForSpeech` to `lib/Renderer.ps1` to decouple text processing from UI logic.

### Fixed
- Resolved 5-minute timeout loops caused by shared quota buckets between text generation and semantic history trimming.
- Improved error handling in `Get-StoredKey` to suppress non-critical exceptions during high-frequency API calls.
- Fixed italic markdown regex fragility when handling nested or adjacent markers (e.g., `***bold-italic***`).

---

## [0.8.3] - 2026-04-23

### Architectural Infrastructure
- **Enhanced Security**: Hardened API key management using explicit `BSTR` handling and memory zeroing to prevent potential key leakage in memory.
- **Resilient Tool-Call Loop**: Implemented an automated error-reporting loop where malformed or truncated tool calls are sent back to the model as `[SYSTEM ERROR]` context, enabling self-correction.
- **Truncation Guardrails**: Added explicit detection for `MAX_TOKENS` truncation during JSON parsing of tool calls, preventing unstable state when payloads are incomplete.

### Added
- **Tool Wiki**: New `TOOLS.html` for better developer discoverability of tool metadata.
- **New Core Tools**: Integrated `readfile`, `search_content`, `searchdir`, `server_manager`, `timer`, and `writefile`.

### Changed
- Standardized UI box widths to `DRAWBOX_WIDTH_SLIM` (80) and `DRAWBOX_WIDTH_WIDE` (100).
- Enhanced `Invoke-GemmaApiWithRetry` with automatic history trimming on initial quota failure.

### Fixed
- UTF-8 encoding consistency across PowerShell job boundaries.
- ANSI color bleeding on multi-line input prompts.

