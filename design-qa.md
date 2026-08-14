# Design QA

## Target and evidence

- Selected target: `~/.codex/generated_images/019ffc4e-f875-7c61-825b-86183039ea1f/exec-62625d8e-67f5-41b9-be48-cbf62cb404b5.png`
- Final implementation capture: `/tmp/ramac-update-centered-ready.png`
- Combined focused comparison: `/tmp/ramac-option1-final-comparison.png`
- State tested: update available, downloading, and update ready for version 1.0.4

## Size normalization

- Source capture: 1556 x 1011 pixels at its generated desktop density.
- Implementation capture: 2464 x 1664 pixels from a 1232 x 832 point macOS window at 2x density.
- Focused source region: 320 x 70 pixels, normalized to 640 x 140 pixels.
- Focused implementation region: 640 x 140 pixels at 2x density.
- The focused comparison uses equal 640 x 140 pixel regions.

## Visual comparison

- The update notice keeps the selected single-line action-rail layout.
- The icon, version, primary action, and Details action share one vertical center.
- The notice uses an equal 8-point inset on the left, top, and bottom.
- All visible text fits without truncation.
- The space before the account-selection footer is reduced.
- The primary action carries the update state, as requested after image 1 was selected. The available state uses `Update available`. The ready state uses `Restart to update`.
- The implementation keeps native SwiftUI controls, typography, colors, and materials.

## Interaction checks

- Clicked `Update available` and observed the downloading state.
- Confirmed the signed update reached the ready state.
- Clicked `Details`, confirmed the Updates window opened, and closed it.
- Did not click `Restart to update`, so the ready-state demo stays open for inspection.

## Findings and fixes

1. P2: The first implementation truncated the version text. Fixed by moving the state into the primary button and keeping the full version as the status text.
2. P2: The account-selection footer had too much space above its first line. Fixed by reducing its top padding from 10 to 5 points.
3. P2: The notice needed equal top, left, and bottom spacing. Fixed by applying one 8-point inset on all sides.

No open P0, P1, or P2 visual issues remain in the tested update flow.

final result: passed
