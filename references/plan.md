GPSN Teleprompter — Final Implementation Plan

Context

Build a native macOS teleprompter for the GPSN client presentation. The presenter speaks naturally in French (not reading
verbatim), so the app must track speech via on-device ASR and advance a cue sheet accordingly, with manual safety rails for
 recovery.

Repo: https://github.com/jbonsant/teleprompter-display → clone to ~/code/teleprompter-display

Key decisions:
- Slide cues: simple text-only "SLIDE" markers in the teleprompter stream + slide counter in control window. No diagram
thumbnails, no asset management.
- Local-first: WhisperKit on-device French ASR, no cloud dependency on the primary path
- Safety: manual controls always override, forward-only alignment, emergency fixed-speed scroll

This plan merges the Codex-revised architecture with web research findings on WhisperKit, alignment algorithms, and macOS
multi-window patterns.

---
Critical Improvements Found

1. WhisperKit Dual-Stream Architecture (HIGH — architecture impact)

Gap: The plan treats WhisperKit transcription as a single output stream. WhisperKit v0.17.0 natively produces two parallel
streams via its LocalAgreement streaming policy:
- Hypothesis stream: ~0.45s latency, may be revised as more audio arrives
- Confirmed stream: ~1.7s latency, stable — never changes once emitted

Impact: The aligner should use the confirmed stream for segment advancement decisions (prevents false jumps from transient
hypotheses). The hypothesis stream can drive optional intra-segment word highlighting for visual responsiveness. This
distinction directly affects Task 6 (ASR Service) and Task 7 (Aligner).

Action: The ASR service must expose both streams. The aligner consumes confirmed text for position logic; the UI can
optionally consume hypothesis text for visual feedback within the active segment.

2. ASR Hallucination Mitigation (HIGH — reliability impact)

Gap: The plan mentions "silence filtering" but doesn't specify critical WhisperKit configuration.

Findings:
- Whisper hallucinate phantom words on silence/pauses — documented issue, especially relevant for a presenter pausing
between sections
- WhisperKit includes built-in VAD (Voice Activity Detection) — must be explicitly enabled
- condition_on_previous_text should be set to false to prevent cascading hallucination loops
- The compressed 632MB whisper-large-v3-turbo 4-bit variant is the natural "backup smaller model"

Action: Add to ASR layer spec: enable WhisperKit VAD, set condition_on_previous_text = false, benchmark the 632MB
compressed turbo as the backup artifact.

3. [MONTRER: ...] Simplified to Slide Markers (MEDIUM — scope reduction)

Decision: [MONTRER: ...] annotations are reduced to simple "next slide" markers. The diagram name is ignored at runtime —
only the position in the script matters.

Parsing: Regex pre-processing extracts [MONTRER: ...] before swift-markdown parsing (swift-markdown would misparse these as
 Link nodes). Each occurrence becomes a SlideMarker with a position reference and sequential index.

Action: The ScriptCompiler emits slideMarkers[] instead of cueEvents[] + assetRefs[]. The control window shows a slide
counter ("Slide 7/23"). The teleprompter shows a highlighted "SLIDE" label inline.

4. Alignment Algorithm Specifics (MEDIUM — core algorithm)

Gap: The plan says "bounded candidate-window scoring over nearby spoken segments" without specifying the algorithm. The
proven approach for speech-tracking teleprompters is well-documented.

Recommended algorithm (validated by Textream, VoicePrompt, and academic literature):
1. Maintain cursor position in the spoken segment list
2. Take the last 3-5 confirmed ASR words
3. Search forward from cursor in a tight window (100-300 words of spoken text, ~2-4 segments)
4. Score candidates using normalized Levenshtein distance on word n-grams (bigrams/trigrams)
5. Advance cursor only if confidence exceeds threshold (0.6-0.8)
6. Debounce: require 2-3 consecutive matching frames before advancing to the next segment
7. Never move backward automatically

Critical for repeated phrases: Keep the forward search window tight (not the full remaining script) to prevent jumping
ahead when the presenter uses recurring formulas.

Action: Add algorithmic specifics to Task 7. The headless rehearsal harness (Task 4) should emit candidate scores per frame
 for threshold tuning.

5. Textream as Additional Architecture Reference (MEDIUM — reference value)

Gap: The plan references magic-teleprompter but misses Textream (github.com/f/textream), the most architecturally relevant
open-source macOS teleprompter:
- Native macOS 15+, SwiftUI + AppKit hybrid
- On-device speech recognition
- Floating window management with NotchOverlayController and ExternalDisplayController
- HTTP/WebSocket for remote control
- Its main weakness: character-count tracking (fragile for paraphrasing) — exactly what our n-gram aligner fixes

Key lesson from Textream: It uses AppKit controllers for multi-display management despite having a SwiftUI UI layer. This
confirms the plan's SwiftUI+AppKit hybrid approach and suggests we'll need dedicated AppKit window controllers for:
- Display connect/disconnect handling
- Per-display window placement
- NSWindow.sharingType = .none (no SwiftUI modifier exists)

Action: Study Textream's window management code before Task 8-9 implementation. Plan for AppKit controllers wrapping
SwiftUI views, not pure SwiftUI windows.

6. French-Specific ASR Optimization (LOW — accuracy improvement)

Findings:
- A community fine-tuned French model exists: bofenghuang/whisper-large-v3-french (3.98% WER on MLS, 4.84% on Fleurs,
trained on 2500+ hours of French)
- It would need CoreML conversion to use with WhisperKit
- WhisperKit supports prompt/prefix biasing to push decoding toward expected technical vocabulary

Action: During Task 5 (model benchmarking), also test converting the French fine-tune to CoreML. Add domain vocabulary
prompting (GPSN-specific technical terms) to the ASR configuration.

7. Performance Budget (LOW — missing concrete targets)

Gap: Section 6.5 lists what to measure but doesn't set pass/fail thresholds.

Recommended targets:
- Speech-to-segment-update latency: < 2.5s p95 (confirmed stream ~1.7s + alignment scoring)
- Model warm load time: < 5s
- Peak memory: < 2GB (including model)
- Manual jump response: < 100ms
- Emergency scroll takeover: < 200ms

Action: Add concrete thresholds to section 6.5.

---
Codex Plan Additions Worth Keeping

- Runtime session state machine with explicit states (prevents implicit coordination bugs)
- Headless rehearsal harness (the single most important testability decision)
- Structured event logging (critical for debugging drift before presentation day)
- Stable IDs + cross-references, source hashes + compiler version
- Pinned model artifacts + backup model requirement
- Operational constraints (Apple Silicon only, exact machine qualification)
- Performance and readiness gates

---
Preparation: Before First Implementation Session

Step 1: Clone & scaffold repo

cd ~/code
git clone https://github.com/jbonsant/teleprompter-display.git
cd teleprompter-display

Step 2: Save reference materials into repo

- references/plan.md — This full implementation plan
- references/presentation-script.md — The actual GPSN presentation script (when available)
- references/presentation-script-opus.md — The Opus variant (when available)

Step 3: Write CLAUDE.md in the repo root

This is the critical file — every Claude session will read it automatically. It should contain:
- Project goal and v1 scope (narrow GPSN tool, not generic product)
- Technical stack (SwiftUI+AppKit, WhisperKit, swift-markdown)
- Architecture summary (PresentationBundle, dual-stream ASR, forward-only aligner, session state machine)
- Key decisions (slide markers only, no asset management; confirmed stream for alignment; VAD + no
condition_on_previous_text; regex pre-processing for MONTRER)
- Performance targets (model load <5s, speech-to-update <2.5s p95, memory <2GB)
- References to Textream (github.com/f/textream) for window management patterns

Step 4: Create initial Swift Package structure

Set up the basic Package.swift with WhisperKit and swift-markdown dependencies so Task 1 has a head start.

---
Build Workflow

Dependency graph

Phase A: Tasks 1-2 (scaffold + contracts) — sequential, one session
Phase B: Tasks 3 + 4 in parallel (compiler + harness) — two sessions/worktrees
Phase C: Tasks 5-7 (benchmark + ASR + aligner) — sequential, one session
Phase D: Tasks 8 + 9 in parallel (control window + teleprompter window) — two sessions
Phase E: Tasks 10-12 (preflight + cloud recovery + rehearsal) — sequential, one session

How to execute

- Run separate Claude Code sessions in terminal tabs, each on the same repo
- For parallel phases (B, D): use feature branches, merge after both complete
- Each session reads CLAUDE.md automatically for full context
- Use /agent:claude or /agent:opus within a session for subtask delegation if needed

---
Implementation Tasks

Task 1: Scaffold macOS Project & Dependencies

- App target: SwiftUI lifecycle + AppKit window controllers (plan for AppKit controllers from the start, not pure SwiftUI
windows)
- Dependencies: WhisperKit, swift-markdown, NaturalLanguage
- Application Support directories for bundle cache, models, logs
- Two placeholder windows (teleprompter + control) managed by AppKit controllers wrapping SwiftUI views **(NEW)
- Study Textream's NotchOverlayController/ExternalDisplayController patterns for window management **(NEW)

Task 2: Define Core Contracts

- PresentationBundle types with stable IDs, source hashes, compiler version:
  - sections[], displayBlocks[], spokenSegments[], slideMarkers[], bookmarks[], anchorPhrases[]
  - No assetRefs[] or cueEvents[] — simplified to slideMarkers[]
- Runtime SessionState enum: idle → preflight → ready → countdown → liveAuto → liveFrozen → manualScroll → recoveringLocal
→ recoveringCloud → error
- ASROutput type with separate hypothesis and confirmed fields and timestamps
- AlignmentFrame type capturing: candidate scores, chosen target, confidence, debounce count
- JSON encode/decode coverage for bundle fixtures
- One checked-in sample bundle from current GPSN content

Task 3: Implement Script Compiler

- Regex pre-processing to extract [MONTRER: ...] → SlideMarker entries (avoids swift-markdown Link-node misparse)
- swift-markdown for structural parsing (headings, sections, Q&A blocks)
- NaturalLanguage for tokenization and anchor phrase extraction
- Classification: display text / spoken sync text / non-spoken notes
- No asset resolver — slide markers are position-only, no file references
- Deterministic tests with golden fixture output
- Anchor phrase selection: pick 2-3 distinctive phrases per segment (avoid common filler)

Task 4: Build Headless Rehearsal Harness

- CLI/test harness feeding recorded audio → WhisperKit → aligner pipeline
- Real-time and faster-than-real-time replay
- Output per-frame: confirmed text chunk, candidate window, all candidate scores, chosen target, confidence, debounce state
- Drift summary and segment timeline
- Baseline fixtures for regression runs
- This harness is the primary tool for tuning thresholds in Task 7

Task 5: Benchmark & Pin ASR Models

- Benchmark on exact live machine:
  - whisper-large-v3-turbo (primary candidate)
  - whisper-large-v3 (quality alternative)
  - whisper-large-v3-turbo compressed 632MB 4-bit (explicit backup candidate)
  - Optionally: bofenghuang/whisper-large-v3-french CoreML conversion if time permits
- Test with condition_on_previous_text = false and VAD enabled
- Test with domain vocabulary prompting (GPSN technical terms)
- Pin primary + backup model artifact IDs
- Warmup and load-time measurements
- Decision record

Task 6: ASR Service & Transport State Machine

- AVAudioEngine capture, permission flow, device selection
- WhisperKit configured with: language = "fr", VAD enabled, condition_on_previous_text = false
- Expose dual streams: hypothesis (for optional UI) and confirmed (for aligner)
- Timestamped transcript chunk stream
- Shared runtime store with all session states
- Session logging for every state transition

Task 7: Forward-Only Aligner & Local Recovery

- Concrete algorithm: sliding window + normalized Levenshtein on word n-grams (bigrams/trigrams)
- Forward search window: 100-300 words (~2-4 segments) from current position
- Confidence threshold: 0.6-0.8 (tune via rehearsal harness)
- Debounce: require 2-3 consecutive agreeing frames before advancing
- Anchor-phrase recovery within local neighborhood
- Hard rule: never jump backward automatically
- Manual jump resets aligner cleanly (new search window from jump target)
- Aligner consumes confirmed stream only for position decisions

Task 8: Build Control Window

- Transport controls, section/Q&A jumps
- Slide counter ("Slide 7/23"), progress bar, session timer, sync status
- Microphone selector, preflight panel
- Visual transport mode + degraded state indicators
- Alignment confidence indicator (from aligner frame data)

Task 9: Build Teleprompter Window

- Large readable display blocks with active-segment highlighting
- Inline "SLIDE" markers rendered as highlighted labels between text blocks
- Optional intra-segment word highlighting from hypothesis stream (visual responsiveness)
- Read-ahead lines, mirror mode
- Keyboard-first transport controls
- Emergency fixed-speed scroll with immediate takeover
- AppKit NSWindowController managing SwiftUI view, not pure SwiftUI Window

Task 10: Blocking Preflight & Rehearsal Workflow

- Preflight checks: model present, warmup OK, mic sanity (live French test), display target, offline path
- Blocking readiness screen
- Saved readiness report
- Concrete pass/fail thresholds: model load < 5s, speech-to-update < 2.5s p95, memory < 2GB
- Operator checklist for full-run rehearsal

Task 11: Optional Cloud Recovery (Flag Off)

- Groq API, llama-3.3-70b-versatile, JSON Object Mode
- Bounded prompt: recent confirmed transcript + candidate segment IDs from forward window
- Local validation: target must be a known segment/bookmark ID within candidate window
- One retry limit, timeout holds position
- Feature flag defaulted off
- Cerebras as alternative if Groq rate-limited

Task 12: Dress Rehearsal & Configuration Freeze

- Full end-to-end rehearsal on exact live machine + conferencing stack
- Issue log: drift, hotkey, display, audio failures
- Final pinned model + config snapshot
- Cloud recovery decision
- Record a rehearsal audio fixture for future regression testing via harness

---
Verification Plan

1. Compiler: Run ScriptCompiler on presentation scripts. Verify sections, slide markers, bookmarks, and anchors extracted
correctly. Compare golden fixture.
2. Headless alignment: Feed recorded French audio through harness. Verify segment advancement matches expected timeline
within ±1 segment. No backward jumps.
3. UI smoke test: Launch both windows on second display. Verify floating, mirror mode, keyboard shortcuts, emergency
scroll, inline SLIDE markers.
4. Preflight: Run on target machine. All checks pass. Deliberately fail one (unplug mic) → verify blocking.
5. Full rehearsal: Complete presentation with live speech. Presenter recovers from 30s improvised aside within 5s using
manual controls.