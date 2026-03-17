# ASR Model Benchmark

Date: 2026-03-17

Machine:
- MacBook Pro (`Mac16,7`)
- Apple M4 Pro
- 48 GB RAM

WhisperKit version:
- `0.17.0`

Benchmark method:
- Generated a 122.72 second French benchmark clip from the GPSN presentation script using macOS `say -v Amelie`.
- Ran all transcription passes with `language = "fr"`, VAD enabled, and no prompt or prefix tokens so `condition_on_previous_text = false` in practice.
- Benchmarked cached models from `~/Library/Application Support/TeleprompterDisplay/Models`.
- Warm-cache numbers below were collected after each model had already been downloaded and loaded once, so they reflect the steady-state path we care about for rehearsals and preflight.
- Memory comes from `/usr/bin/time -l` max resident set size.

## Warm-cache results

| Model ID | Load (s) | Transcription latency (s) | Speed factor | Max RSS (MiB) | Notes |
| --- | ---: | ---: | ---: | ---: | --- |
| `openai_whisper-large-v3_turbo` | 1.25 | 32.31 | 3.80x | 730.6 | Intended live primary. Stable output on the synthetic clip. |
| `openai_whisper-large-v3-v20240930_turbo_632MB` | 1.40 | 6.87 | 17.86x | 377.0 | Best latency and memory. Keep as the lower-memory fallback artifact. |
| `openai_whisper-large-v3` | 1.03 | 30.85 | 3.98x | 926.0 | Quality reference. Highest memory of the warm runs. |

## Cold-start note

The first standalone load of `openai_whisper-large-v3_turbo` on this machine took 104.81 seconds and peaked at 1777.5 MiB RSS because Core ML had to specialize the model artifacts. That is acceptable only as a one-time cache warmup, not as a live-session path. Preflight must warm the model before the presenter starts.

## Decision

Pinned runtime defaults:
- Primary: `openai_whisper-large-v3_turbo`
- Backup: `openai_whisper-large-v3-v20240930_turbo_632MB`

Rationale:
- Keep the full turbo artifact as the default live model because that was the original target and it remains within the steady-state memory budget once warmed.
- Keep the 632 MB turbo artifact cached as the immediate fallback because it materially reduces both load-time footprint and transcription latency.
- Keep `openai_whisper-large-v3` available only as a reference model for future live-speaker accuracy checks, not as the default runtime choice.

Follow-up:
- Re-run the same benchmark against a real French rehearsal recording before freeze. The synthesized benchmark is good enough for performance and cache validation, but not for final WER decisions.
