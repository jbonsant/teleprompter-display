# Teleprompter Display

A native macOS teleprompter built for live French presentations. The app listens to your voice, tracks where you are in your script, and scrolls the text automatically — even when you paraphrase, skip bullets, or improvise.

Built for the GPSN RFP presentation at Universite Laval.

## How It Works

You write a presentation script in Markdown. The app compiles it into a presentation bundle that separates what you see on screen from what the speech engine uses to track your position. During the presentation:

1. **You speak naturally in French** — no need to read word for word
2. **On-device speech recognition** (WhisperKit) transcribes your voice locally — nothing goes to the cloud
3. **A forward-only aligner** matches what you say against the script and advances the teleprompter
4. **If you go off-script**, the aligner holds position and waits for you to come back
5. **If you need to jump**, manual controls let you skip to any section instantly

The app runs on a second display (or a beam-splitter/glass teleprompter) while the control window stays on your main screen.

## Features

### Teleprompter Window (second display)
- Large readable text on a dark background, optimized for distance
- Active segment highlighted, with read-ahead for the next few lines
- Inline slide markers telling you when to advance your slides
- Mirror mode for glass teleprompter setups
- Adjustable font size
- Emergency fixed-speed scroll if speech tracking fails

### Control Window (main display)
- Session state, timer, and slide counter
- Play, pause, freeze, and emergency scroll controls
- Section and Q&A jump lists for instant navigation
- Microphone selector
- Alignment confidence indicator
- Preflight checklist that must pass before going live

### Speech Tracking
- On-device French ASR via WhisperKit — no internet required
- Dual-stream architecture: fast hypothesis for visual feedback, stable confirmed text for position decisions
- Forward-only alignment that never jumps backward accidentally
- Handles paraphrasing, skipped bullets, and improvised asides
- Anchor phrase recovery when tracking drifts

### Safety
- Manual controls always override automatic tracking
- Keyboard-first: space, escape, arrow keys, section jumps
- Emergency fixed-speed scroll takes over in under 200ms
- Blocking preflight checks before every live session
- Works fully offline

## Requirements

- macOS 14+ (Sonoma or later)
- Apple Silicon (M1 or later)
- Second display recommended (single-screen overlay as fallback)
- Microphone (built-in or external)

## Quick Start

```bash
# Build
swift build

# Run the app
swift run teleprompter-display

# Run the rehearsal harness (headless, no GUI)
swift run teleprompter-rehearsal
```

## Writing Presentation Scripts

The teleprompter reads Markdown files with a specific structure. Place your scripts in `references/` as `.md` files.

### Script Format Reference

Use this format when generating scripts — either by hand or with an AI workspace assistant.

#### Header

```markdown
# Script de presentation — [PROJECT NAME] — [VENUE]

**Duree :** 60 min contenu + 30 min questions
**Presentateur :** [Name], [Organization]
```

#### Sections

Each major section uses an `## H2` heading with a timing annotation:

```markdown
## Section 1 — Documentation et modelisation des processus d'affaires notariaux

[⏱ 0:00 — cible 5:00]
```

The timing annotation `[⏱ START — cible END]` is a stage direction — it tells the presenter the target window for this section. It is not displayed on the teleprompter or used for alignment.

#### Sub-structure within a section

Use sub-headings and bold labels to organize content:

```markdown
### Accroche

Le GPSN n'est pas un projet techno — c'est un projet de numerisation metier.

### Points cles

**Consultant notarial dedie**
- 70 heures budgetees
- Workflows standardises par type d'acte

**Dimensionnement concret**
- 2 700 notaires actifs
- 3 000 sessions simultanees
```

- `### Accroche` — opening hook, spoken naturally
- `### Points cles` — bullet points the presenter scans (not read verbatim)
- `### Transition` — closing line that bridges to the next section
- `**Bold labels**` — sub-topics within a section

#### Slide cues

When the presenter should advance to the next slide or show a diagram:

```markdown
[MONTRER : 05-f01-functional-module-map.png]
```

or without the `.png` extension:

```markdown
[MONTRER: 05-f01-functional-module-map]
```

Both formats work. The teleprompter renders these as highlighted `SLIDE` markers inline with the text. The diagram filename is for the presenter's reference only — the app does not load or display the actual image files.

#### Cut-down notes

When time is tight, include a cut-down block that tells the presenter what to keep and what to skip:

```markdown
Si on doit couper:

- garder consultant notarial
- garder 5 profils
- garder chiffres de volumetrie
- finir sur la cartographie modulaire
```

These are classified as non-spoken notes — they appear on the teleprompter as dimmed text but are excluded from speech alignment.

#### Q&A section

Anticipated questions use `####` headings inside a Q&A section:

```markdown
## Section 7 — Questions anticipees et reponses

#### Q1. Comment garantir la confidentialite des donnees notariales?

- chiffrement AES-256 au repos
- TLS 1.3 en transit
- cles gerees dans Azure Key Vault
- rotation automatique tous les 90 jours
```

Each Q&A block becomes a bookmark in the teleprompter — the presenter can jump directly to any anticipated answer from the control window.

#### Presenter notes

End the script with a notes section for pacing and visual priorities:

```markdown
## Notes presentateur

- Si le temps serre, compresser d'abord section 3D, puis heritiers, puis CI detaillee
- Visuels essentiels si le deck doit etre resserre:
  - `05-f01-functional-module-map`
  - `01-t01-architecture-overview`
```

This section is excluded from the teleprompter display and from speech alignment.

### Guidelines for AI Script Generation

When using an AI assistant (Claude, GPT, etc.) to generate or refine presentation scripts for this teleprompter, include these instructions:

```
Generate a presentation script in Markdown for a French-language RFP defense presentation.

Format rules:
- Write in natural spoken French — the presenter will paraphrase, not read verbatim
- Use ## H2 for major sections with [⏱ START — cible END] timing annotations
- Use ### H3 for sub-structure: "Accroche", "Points cles", "Transition"
- Use **bold** for sub-topic labels within a section
- Use bullet points for scannable key points (not full sentences)
- Use [MONTRER: filename] on its own line when the presenter should show a slide/diagram
- Include "Si on doit couper:" blocks with priorities for time-constrained delivery
- Include a ## Q&A section with #### Q1/Q2/Q3... for anticipated questions
- End with ## Notes presentateur for pacing and visual priorities
- Keep transitions natural: one sentence bridging each section
- Separate sections with --- horizontal rules
- Do not use inline HTML, tables in the body, or complex Markdown features
- Write for a 60-minute presentation with 30 minutes of Q&A
```

### Two Script Variants

This repo includes two script files demonstrating the format:

| File | Style | Best for |
|------|-------|----------|
| `references/presentation-script.md` | Compact bullet points, minimal prose | Experienced presenters who need quick visual cues |
| `references/presentation-script-opus.md` | Structured with Accroche/Points cles/Transition | Presenters who want more guidance on phrasing and flow |

Both are valid inputs. The compiler handles either format.

## Project Structure

```
Sources/
  TeleprompterDisplayApp/   — App bootstrap, AppDelegate
  TeleprompterAppSupport/   — Window controllers, session store, SwiftUI views
  TeleprompterDomain/       — Data contracts (PresentationBundle, SessionState, etc.)
  ScriptCompiler/           — Markdown → PresentationBundle compiler
  SpeechAlignment/          — WhisperKit ASR service, forward-only aligner
  RehearsalHarness/         — Headless CLI for testing without the GUI
Tests/
references/
  plan.md                   — Implementation plan
  presentation-script.md    — GPSN presentation script (compact)
  presentation-script-opus.md — GPSN presentation script (structured)
```

## License

Private repository. Not for distribution.
