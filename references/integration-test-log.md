# Integration Test Log

## Run metadata

- Date: March 17, 2026
- Machine: MacBook Pro `Mac16,7`, Apple M4 Pro, 48 GB RAM
- macOS: 15.7.3 (`24G419`)
- Primary ASR model: `openai_whisper-large-v3_turbo`
- Cloud recovery model: `llama-3.3-70b-versatile`

## Automated coverage completed

### 1. Swift integration tests

Command:

```bash
swift test
```

Result:

- Passed `17/17` tests.
- Added `TeleprompterAppSupportTests/AppSessionStoreIntegrationTests.swift` to cover:
- blocking preflight sequencing and JSON report persistence
- cloud recovery arming after 30 seconds of low confidence
- manual jump, freeze, emergency scroll, bookmark jumps, and slide counter behavior

### 2. Rehearsal harness with recorded French fixture

Fixture inputs:

- Bundle: `Tests/Fixtures/golden-bundle.json`
- Transcript: `Tests/Fixtures/rehearsal-fr-gpsn.txt`
- Audio: `Tests/Fixtures/rehearsal-fr-gpsn.aiff`

Command:

```bash
swift run teleprompter-rehearsal \
  --bundle Tests/Fixtures/golden-bundle.json \
  --audio Tests/Fixtures/rehearsal-fr-gpsn.aiff \
  --event-log /tmp/teleprompter-rehearsal-log.json \
  --speed 4x
```

Observed result:

- Replay path completed successfully after fixing raw Whisper control-token leakage in `RehearsalTranscriptionService`.
- Final harness position: segment `6/14` (`seg-2b`).
- Event log written to `/tmp/teleprompter-rehearsal-log.json`.
- Fixture duration: `137.08s`.

### 3. Build validation

Command:

```bash
swift build
```

Result:

- Build completed successfully on March 17, 2026.

## Issues recorded

1. The first replay-harness run exposed a real bug in the offline rehearsal path: raw Whisper control tokens such as `<|fr|>` were entering the aligner and suppressing progression. Fixed in this session by normalizing rehearsal transcript chunks before they are converted into `ASROutput`.
2. The synthesized TTS regression fixture progresses reliably through the opening and architecture sections, but it does not cover the full `14/14` bundle. The fixture is still useful for regression on early-segment tracking, control flow, and ASR replay stability.
3. Full live-microphone validation with a human French speaker, a physical second display, and real operator keyboard interaction could not be completed from this terminal-only session. Those steps remain required on the presentation machine before the live event.

## Manual rehearsal checklist still required on target machine

- Run the blocking preflight in the control window with the actual live microphone.
- Speak the French mic prompt and verify the confirmed transcript in real time.
- Confirm the second display is detected and the teleprompter window lands on it.
- Verify keyboard shortcuts with focus on the control window.
- Verify emergency scroll visually on the teleprompter display.
- Run one full spoken rehearsal with the presenter, not TTS.
