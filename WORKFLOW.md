# How to Build This App — 3 Prompts

Open one Claude Code session and paste 3 prompts, one at a time. Each prompt handles multiple tasks and spawns sub-agents for parallel work. Wait for each to finish before pasting the next.

## Setup

```bash
cd ~/code/teleprompter-display
claude
```

---

## Prompt 1 of 3 — Foundation, Compiler, and Harness

Paste this into the Claude session:

```
Build the foundation, script compiler, and rehearsal harness. This covers Tasks 1-4 from references/plan.md.

Read CLAUDE.md for full architecture context.

STEP 1 — Do these sequentially (yourself):

Task 1 — Expand Scaffold:
- Expand AppDelegate to handle display connect/disconnect (reference Textream github.com/f/textream for ExternalDisplayController pattern)
- Add Application Support directory setup on launch (bundle cache, models, logs)
- Make teleprompter window float (.floating window level)
- Add keyboard shortcut handling: space=pause, escape=emergency scroll, left/right=prev/next segment
- Verify both windows launch on `swift run teleprompter-display`
- No ASR/alignment/compiler logic yet — just the app shell

Task 2 — Expand Core Contracts:
- Add missing cross-reference fields to domain types (e.g., displayBlock.sectionID)
- Add DiagnosticEvent type (timestamp, eventType enum, payload)
- Add PreflightResult type (check name, passed, detail)
- Add SessionLog type accumulating DiagnosticEvents
- Generate a realistic 5-10 section sample bundle from references/presentation-script.md with real French text
- Save sample bundle as golden fixture JSON in Tests/Fixtures/
- Add comprehensive tests: JSON round-trip for every type, stable ID uniqueness

Run `swift build` and `swift test` after each task. Commit after each task.

STEP 2 — Spawn these two as parallel sub-agents using worktrees:

Agent A — Task 3 (Script Compiler):
Read references/presentation-script.md and references/presentation-script-opus.md.
Replace the stub compiler in Sources/ScriptCompiler/:
1. Regex pre-processing: extract [MONTRER: ...] BEFORE swift-markdown (it misparses as Link nodes). Each → SlideMarker with sequential index.
2. swift-markdown: headings, sub-headings, Q&A blocks, bullets, paragraphs
3. Classify: display text (teleprompter shows) / spoken sync text (aligner matches) / non-spoken (excluded)
4. NaturalLanguage: tokenize, extract 2-3 distinctive anchor phrases per segment (no filler)
5. Stable IDs from content hashes (not random UUIDs)
6. Bookmarks: one per major heading, one per Q&A block
Test with both scripts. Save golden fixture. Run `swift test`. Commit.

Agent B — Task 4 (Rehearsal Harness):
Expand Sources/RehearsalHarness/ CLI stub:
1. Accept PresentationBundle JSON + audio file path
2. Feed audio through WhisperKit (fr, VAD, condition_on_previous_text=false)
3. Pipe confirmed chunks into stub aligner (just log them)
4. Output per-frame: timestamp, confirmed text, segment position
5. End-of-run summary: segments traversed, final position, elapsed time
6. --speed flag for 2x/4x replay
7. JSON event log output
8. --download-model flag to fetch/cache model
Must work from CLI without GUI. Run `swift build`. Commit.

After both agents finish, merge their branches into main and resolve any conflicts.
Run `swift build` and `swift test` to verify the merged result. Commit the merge.
```

**Wait for it to finish completely.**

---

## Prompt 2 of 3 — ASR, Alignment, and Both UI Windows

Paste this into the same Claude session:

```
Build the ASR service, aligner, and both UI windows. This covers Tasks 5-9 from references/plan.md.

Read CLAUDE.md for full architecture context.

STEP 1 — Do these sequentially (yourself):

Task 5 — Benchmark & Pin ASR Models:
- Download/cache: openai_whisper-large-v3-turbo (primary), compressed/quantized variant (backup), openai_whisper-large-v3 (reference)
- Benchmark each: load time, transcription latency, memory
- Test with VAD enabled, condition_on_previous_text=false
- Write results to references/model-benchmark.md
- Pin chosen primary + backup model IDs in a config constant
- Commit

Task 6 — ASR Service & State Machine:
In Sources/SpeechAlignment/:
- AVAudioEngine capture, mic selection, permission flow
- WhisperKit: language="fr", VAD, conditionOnPreviousText=false
- Expose TWO streams (AsyncSequence or Combine): hypothesis (~0.45s) and confirmed (~1.7s)
- Pinned model ID from Task 5, latency tracking

In Sources/TeleprompterAppSupport/:
- Expand AppSessionStore into transport state machine
- All transitions: idle → preflight → ready → countdown → liveAuto → liveFrozen → manualScroll → recoveringLocal → recoveringCloud → error
- Manual commands transition immediately
- Log every transition as DiagnosticEvent
- Commit

Task 7 — Forward-Only Aligner:
Create Sources/SpeechAlignment/ForwardAligner.swift:
1. Cursor = current segment index in spokenSegments[]
2. On each confirmed chunk: extract last 3-5 words, build forward window (100-300 words, ~2-4 segments), score candidates with normalized Levenshtein on word bigrams/trigrams
3. Score > 0.7 → increment debounce. 3 consecutive agreements → advance cursor.
4. Score < threshold → hold, try anchor phrases
5. NEVER move backward
6. Manual jump resets cursor + debounce + window
- Consumes CONFIRMED stream only
- Publishes segment ID, confidence, AlignmentFrame
- Unit tests: exact match, paraphrase, skipped section, repeated phrase, manual jump
- Update rehearsal harness to use real aligner
- Commit

Run `swift test` after Tasks 6 and 7.

STEP 2 — Spawn these two as parallel sub-agents using worktrees:

Agent A — Task 8 (Control Window):
Replace ControlRootView in Sources/TeleprompterAppSupport/Views/:
- Top bar: state badge (colored), timer, slide counter ("Slide 7/23")
- Transport: Play/Pause, Freeze, Prev/Next Segment, Emergency Scroll toggle
- Section jump list: scrollable bookmarks, tap to jump
- Q&A jump list: separate section
- Mic selector: dropdown of audio devices
- Sync status: confidence bar, current/next segment preview
- Preflight panel: checks with pass/fail
- All controls read from and write to AppSessionStore
- Keyboard shortcuts alongside mouse
- Red border on error/manualScroll states
Run `swift build`. Commit.

Agent B — Task 9 (Teleprompter Window):
Replace TeleprompterRootView in Sources/TeleprompterAppSupport/Views/:
- Full-screen dark, readable at distance
- Active segment: large bold white, highlighted
- Read-ahead: 2-3 segments below, dimmer
- Previous: one above, very dim
- Slide markers: "▶ SLIDE" labels between blocks
- Auto-scroll: smooth animation on advance
- Mirror mode (M key): horizontal flip
- Font size (+/- keys)
- Emergency scroll (Escape): fixed WPM, takes over in < 200ms
- Space=pause, Up/Down=prev/next
- Optional: hypothesis word highlighting
- Uses existing TeleprompterWindowController (AppKit)
- Fills target display, .floating level
Run `swift build`. Commit.

After both agents finish, merge their branches and resolve conflicts.
Run `swift build` and `swift test`. Commit the merge.
```

**Wait for it to finish completely.**

---

## Prompt 3 of 3 — Preflight, Cloud Recovery, and Integration

Paste this into the same Claude session:

```
Build the preflight system, cloud recovery, and run integration tests. This covers Tasks 10-12 from references/plan.md.

Read CLAUDE.md for full architecture context.

Task 10 — Blocking Preflight:
1. Preflight checks (sequential, all must pass):
   - Microphone permission granted
   - Pinned WhisperKit model present locally
   - Model warmup < 5s
   - Live French mic test: speak, verify French transcription
   - Bundle loaded and valid
   - Second display detected
   - Keyboard shortcuts responsive
   - Emergency scroll activates/deactivates
2. Blocking readiness screen in control window:
   - Each check: name, status (pending/running/pass/fail), detail
   - "Start" disabled until all pass
   - Re-run individual checks
3. Save preflight report as JSON in Application Support
Commit.

Task 11 — Optional Cloud Recovery (flag OFF by default):
Only activates when: local confidence < threshold for > 30s AND anchor recovery fails AND flag enabled.
- Groq API, llama-3.3-70b-versatile
- Send: last 20 confirmed words + candidate segment IDs/text from forward window
- JSON Object Mode: { "targetSegmentID": "...", "confidence": 0.0-1.0 }
- Validate: target must exist within candidate window
- Success: jump aligner, log. Failure: hold position, log.
- Max 1 retry. Toggle in control window.
- API key from env var GROQ_API_KEY
Commit.

Task 12 — Integration Test & Freeze:
1. Full end-to-end test:
   - Load bundle from references/presentation-script.md
   - Run preflight
   - Start live session with mic
   - Verify segment tracking with spoken French
   - Test: manual jump, freeze, emergency scroll, section jumps, slide counter
2. Record issues in references/integration-test-log.md
3. Freeze: pin model ID, lock thresholds, document macOS version + hardware → references/production-config.json
4. Record rehearsal audio fixture for regression
Commit.

Run `swift build` and `swift test` at the end. Run `swift run teleprompter-display` to verify the app launches correctly.
```

---

## That's It

After all 3 prompts complete, your app is built. Run it:

```bash
swift run teleprompter-display
```

## Cheat Sheet

| Action | Command |
|--------|---------|
| Start session | `cd ~/code/teleprompter-display && claude` |
| Build | `swift build` |
| Test | `swift test` |
| Run app | `swift run teleprompter-display` |
| Run harness | `swift run teleprompter-rehearsal` |
| Second opinion | Inside claude: `/agent:opus "review ..."` |
