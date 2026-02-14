# TypeWhisper

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![macOS](https://img.shields.io/badge/macOS-15.0%2B-black.svg)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6-orange.svg)](https://swift.org)

Local speech-to-text for macOS. Transcribe audio using on-device AI models — no cloud, no API keys, no subscriptions. Your voice data never leaves your Mac.

<p align="center">
  <video src=".github/demo.mp4" autoplay loop muted playsinline width="700"></video>
</p>

## Screenshots

<p align="center">
  <img src=".github/screenshots/home.png" width="700" alt="Home Dashboard">
</p>

<p align="center">
  <img src=".github/screenshots/models.png" width="340" alt="Model Manager">
  <img src=".github/screenshots/history.png" width="340" alt="Transcription History">
</p>

<p align="center">
  <img src=".github/screenshots/profiles.png" width="700" alt="Profiles with URL Patterns">
</p>

## Features

- **On-device transcription** — All processing happens locally on your Mac
- **Three AI engines** — WhisperKit (99+ languages, streaming, translation), Parakeet TDT v3 (25 European languages, extremely fast), and Apple SpeechAnalyzer (macOS 26+, no model download needed)
- **System-wide dictation** — Push-to-talk or toggle mode via global hotkey, auto-pastes into any app
- **Streaming preview** — See partial transcription in real-time while speaking (WhisperKit)
- **Translation** — Translate transcriptions on-device using Apple Translate
- **File transcription** — Batch-process multiple audio/video files with drag & drop
- **Subtitle export** — Export transcriptions as SRT or WebVTT with timestamps
- **Local HTTP API** — REST API for integration with external tools and scripts
- **App-specific profiles** — Per-app and per-website overrides for language, task, engine, and whisper mode. Match by app (bundle ID) and/or domain (with subdomain support). Automatically activates when dictating in a matched application or website
- **Dictionary** — Custom term corrections applied after transcription (e.g., fix names, jargon, or recurring misrecognitions). Includes importable term packs
- **Snippets** — Text shortcuts with trigger→replacement. Supports placeholders like `{{DATE}}`, `{{TIME}}`, and `{{CLIPBOARD}}`
- **History** — Searchable transcription history with inline editing, correction detection, and app context tracking
- **Home dashboard** — Usage statistics (words, WPM, apps used, time saved), activity chart, and onboarding tutorial
- **Sound feedback** — Audio cues for recording start, transcription success, and errors
- **Media pause** — Automatically pauses media playback during recording
- **Whisper mode** — Boosted microphone gain for quiet speech
- **Auto-update** — Built-in updates via Sparkle
- **Launch at Login** — Start automatically with macOS
- **Multilingual UI** — English and German

## System Requirements

- macOS 15.0 (Sequoia) or later
- Apple Silicon (M1 or later) recommended
- 8 GB RAM minimum, 16 GB+ recommended for larger models

## Model Recommendations

| RAM | Recommended Models |
|-----|-------------------|
| < 8 GB | Whisper Tiny, Whisper Base |
| 8–16 GB | Whisper Small, Whisper Large v3 Turbo, Parakeet TDT v3 |
| > 16 GB | Whisper Large v3 |

## Build

1. Clone the repository:
   ```bash
   git clone https://github.com/TypeWhisper/typewhisper-mac.git
   cd typewhisper-mac
   ```

2. Open in Xcode 16+:
   ```bash
   open TypeWhisper.xcodeproj
   ```

3. Select the TypeWhisper scheme and build (Cmd+B). Swift Package dependencies (WhisperKit, FluidAudio, KeyboardShortcuts) resolve automatically.

4. Run the app. It appears as a menu bar icon — open Settings to download a model.

## HTTP API

Enable the API server in Settings > API Server (default port: 8787).

### Check Status

```bash
curl http://localhost:8787/v1/status
```

```json
{
  "status": "ready",
  "engine": "whisper",
  "model": "openai_whisper-large-v3_turbo",
  "supports_streaming": true,
  "supports_translation": true
}
```

### Transcribe Audio

```bash
curl -X POST http://localhost:8787/v1/transcribe \
  -F "file=@recording.wav" \
  -F "language=en"
```

```json
{
  "text": "Hello, world!",
  "language": "en",
  "duration": 2.5,
  "processing_time": 0.8,
  "engine": "whisper",
  "model": "openai_whisper-large-v3_turbo"
}
```

Optional parameters:
- `language` — ISO 639-1 code (e.g., `en`, `de`). Omit for auto-detection.
- `task` — `transcribe` (default) or `translate` (translates to English, WhisperKit only).

### List Models

```bash
curl http://localhost:8787/v1/models
```

## Profiles

Profiles let you configure transcription settings per application or website. For example:

- **Mail** — German language, Whisper Large v3
- **Slack** — English language, Parakeet TDT v3
- **Terminal** — Whisper mode always on
- **github.com** — English language (matches in any browser)
- **docs.google.com** — German language, translate to English

Create profiles in Settings > Profiles. Assign apps and/or URL patterns, set language/task/engine overrides, and adjust priority. URL patterns support subdomain matching — e.g. `google.com` also matches `docs.google.com`. The domain autocomplete suggests domains from your transcription history.

When you start dictating, TypeWhisper matches the active app and browser URL against your profiles with the following priority:
1. **App + URL match** — highest specificity (e.g. Chrome + github.com)
2. **URL-only match** — cross-browser profiles (e.g. github.com in any browser)
3. **App-only match** — generic app profiles (e.g. all of Chrome)

The active profile name is shown as a badge in the recording overlay.

Both engines (WhisperKit and Parakeet) can be loaded simultaneously for instant switching between profiles. Note that loading both models increases memory usage.

## Architecture

```
TypeWhisper/
├── App/                    # App entry point, dependency injection
├── Models/                 # Data models (ModelInfo, TranscriptionResult, EngineType, Profile, etc.)
├── Services/
│   ├── Engine/             # WhisperEngine, ParakeetEngine, SpeechAnalyzerEngine, TranscriptionEngine protocol
│   ├── HTTPServer/         # Local REST API (HTTPServer, APIRouter, APIHandlers)
│   ├── SubtitleExporter    # SRT/VTT export
│   ├── ModelManagerService # Model download, loading, transcription dispatch
│   ├── AudioFileService    # Audio/video → 16kHz PCM conversion
│   ├── AudioRecordingService
│   ├── HotkeyService
│   ├── TextInsertionService
│   ├── ProfileService      # Per-app profile matching and persistence
│   ├── HistoryService      # Transcription history persistence (SwiftData)
│   ├── DictionaryService   # Custom term corrections
│   ├── SnippetService      # Text snippets with placeholders
│   ├── TranslationService  # On-device translation via Apple Translate
│   ├── MediaPlaybackService # Pause/resume media during recording
│   └── SoundService        # Audio feedback for recording events
├── ViewModels/             # MVVM view models with Combine
├── Views/                  # SwiftUI views
└── Resources/              # Info.plist, entitlements, localization, sounds
```

**Patterns:** MVVM with `ServiceContainer` singleton for dependency injection. ViewModels use a static `_shared` pattern. Localization via `String(localized:)` with `Localizable.xcstrings`.

## License

GPLv3 — see [LICENSE](LICENSE) for details. Commercial licensing available — see [LICENSE-COMMERCIAL.md](LICENSE-COMMERCIAL.md).
