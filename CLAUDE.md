# Teleprompter Display

## Mission

Build a narrow, reliable macOS teleprompter for the GPSN presentation. This is not a generic teleprompter product. The primary job is to keep a French-speaking presenter on track while allowing natural paraphrasing, manual recovery, and offline-first operation.

## Read First

Before changing architecture or implementation direction, read these files in order:

1. `references/plan.md`
2. `references/presentation-script.md`
3. `references/presentation-script-opus.md`

## v1 Scope

- Native macOS app.
- Two windows: teleprompter display and control surface.
- On-device French ASR via WhisperKit.
- Forward-only speech alignment against a compiled presentation bundle.
- Manual recovery controls that always override automatic tracking.
- Slide cues represented only as simple inline `SLIDE` markers plus a control-window counter.
- Headless rehearsal harness for repeatable tuning and regression work.

## Explicit Non-Goals

- Do not build a generic SaaS teleprompter.
- Do not add diagram thumbnails, asset management, or a generic media pipeline.
- Do not make cloud ASR the primary path.
- Do not add automatic backward jumps.
- Do not optimize for multi-presenter workflows.

## Technical Direction

- Swift 6 with Swift Package Manager.
- macOS 14+ on Apple Silicon.
- App shell: AppKit window controllers hosting SwiftUI views.
- Parsing: `swift-markdown`, with a regex pre-pass for `[MONTRER: ...]` cues.
- NLP helpers: `NaturalLanguage`.
- ASR: `WhisperKit` with French configuration.
- Testing: unit tests plus a headless rehearsal harness.

## Architecture Decisions That Must Hold

- `PresentationBundle` is the core compiled artifact and must carry stable IDs, source hashes, and compiler version metadata.
- The ASR layer must expose two streams: hypothesis and confirmed.
- Only the confirmed stream drives segment advancement.
- Hypothesis text is only for optional intra-segment highlighting or operator feedback.
- WhisperKit must run with VAD enabled and `condition_on_previous_text = false`.
- Alignment is forward-only, windowed, confidence-gated, and debounced.
- Manual jumps and emergency fixed-speed scroll always take priority over automatic tracking.
- Window management should stay AppKit-first for placement, sharing policy, and multi-display handling.

## Alignment Guardrails

- Keep the search window tight: 100-300 words, roughly 2-4 nearby segments.
- Score candidates with normalized edit-distance style matching on word n-grams.
- Require repeated agreement before advancing.
- Never auto-rewind.
- Treat repeated phrases as a primary failure mode and design for them explicitly.

## Performance Gates

- Model warm load under 5 seconds.
- Speech-to-segment update latency under 2.5 seconds p95.
- Peak memory under 2 GB including the loaded model.
- Manual jump response under 100 ms.
- Emergency scroll takeover under 200 ms.

## Delivery Phases

- Phase A: scaffold and contracts.
- Phase B: script compiler and headless rehearsal harness.
- Phase C: benchmark models, ASR service, and aligner.
- Phase D: control window and teleprompter window.
- Phase E: preflight workflow, optional cloud recovery, full rehearsal, and freeze.

Parallel work is acceptable only where the reference plan already allows it. Otherwise prefer sequential integration to keep drift visible.

## Repo Layout Intent

- `references/` contains the product inputs and planning documents.
- `Sources/TeleprompterDisplayApp/` owns app bootstrap.
- `Sources/TeleprompterAppSupport/` owns shared UI shell, window controllers, and session store.
- `Sources/TeleprompterDomain/` owns durable contracts and runtime state types.
- `Sources/ScriptCompiler/` owns bundle compilation from the presentation scripts.
- `Sources/SpeechAlignment/` owns ASR configuration and aligner policy.
- `Sources/RehearsalHarness/` owns headless replay tooling.
- `Tests/` should grow with every contract or algorithm change.

## Working Rules For Future Sessions

- Keep the GPSN scope narrow even if the code naturally suggests abstraction.
- Read the presentation scripts before making compiler or UX decisions.
- Update the rehearsal harness when alignment behavior changes.
- Prefer explicit state machines over implicit UI coordination.
- Add fixtures and logs before tuning thresholds.
- Preserve manual operator control paths even when improving automation.
- Benchmark on the target live machine before locking ASR defaults.
- Treat `references/plan.md` as the authoritative implementation sequence.

## Current Scaffold Status

This repo already includes:

- the implementation references and presentation scripts;
- a SwiftPM scaffold with the app shell, domain module, compiler stub, alignment bootstrap module, and rehearsal CLI;
- placeholder dual-window macOS UI so future sessions can iterate from a working shell;
- basic JSON round-trip coverage for the bundle contracts.

The next implementation sessions should start with Task 1 and Task 2 from `references/plan.md`, expanding the placeholder code instead of replacing the structure.
