# Design QA

## Target and evidence

- Selected target: `~/.codex/generated_images/019ffc4e-f875-7c61-825b-86183039ea1f/exec-62625d8e-67f5-41b9-be48-cbf62cb404b5.png`
- Final implementation capture: `/tmp/ramac-update-divider-ready.png`
- Combined focused comparison: `/tmp/ramac-option1-final-comparison.png`
- State tested: update available, downloading, and update ready for version 1.0.4
- Final main-window capture: `/tmp/ramac-geometry-final-main.png`
- Continuous sidebar capture: `/tmp/ramac-continuous-sidebar.png`
- Version 1.1.0 release captures: `/tmp/ramac-v110-main.png`, `/tmp/ramac-v110-add-account.png`, `/tmp/ramac-v110-players.png`, `/tmp/ramac-v110-launchsets.png`, `/tmp/ramac-v110-diagnostics.png`, and `/tmp/ramac-v110-updates.png`
- Final Add Account capture: `/tmp/ramac-geometry-final-add.png`
- Additional window captures: `/tmp/ramac-geometry-players.png`, `/tmp/ramac-geometry-launchsets.png`, `/tmp/ramac-geometry-updates.png`, and `/tmp/ramac-geometry-diagnostics.png`

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

## App-wide corner geometry

- App-owned geometry uses one shared scale: 20-point window corners, 12-point panels, and 6-point controls.
- Edge insets are derived from the two visible radii. Window-edge controls use 14 points. Controls inside app-owned panels use 6 points.
- The main sidebar footer, update notice, Add Account window, sign-in-again view, Joinable Players controls, Launch Sets footer, account website identity bar, account detail groups, batch-launch group, notes editor, release-note code blocks, avatars, and game thumbnails use the shared geometry.
- Native Form, List, GroupBox, toolbar, menu, popover, dialog, and sheet corners remain system-owned so macOS can keep its native concentric geometry.
- The final main, Add Account, Joinable Players, Launch Sets, Updates, and Diagnostics captures show no clipped controls, uneven edge gaps, or conflicting corner radii.

## Sidebar material

- The group filter, account list, update notice, and bulk controls now share one parent `.bar` material.
- The account list hides its separate scroll background, so it no longer creates a material boundary inside the sidebar.
- The continuous sidebar capture shows one surface from the title area to the bottom window corners, with no opaque footer bands or material seams.
- Selection, disabled, running, and secondary-text states remain readable against the shared material.

## Version 1.1.0 release review

- The exact packaged version 1.1.0 app was opened for the final review.
- The main account window, Add Account, Joinable Players, Launch Sets, Diagnostics and Backup, and Updates windows were inspected at their real macOS sizes.
- The main window keeps a clear launch hierarchy, a continuous sidebar surface, readable account state, and consistent edge spacing.
- Add Account keeps the sign-in method, instructions, browser, status, and save action within the window without clipping.
- Joinable Players, Launch Sets, and Diagnostics keep their main action and empty or saved-content states clear at first glance.
- The Updates window reports version 1.1.0 and keeps release selection, Markdown notes, and update status readable at its restored compact size.
- No control overlap, clipped text, mismatched custom radius, opaque sidebar band, or unreadable state was found.

## Interaction checks

- Clicked `Update available` and observed the downloading state.
- Confirmed the signed update reached the ready state.
- Clicked `Details`, confirmed the Updates window opened, and closed it.
- Did not click `Restart to update` during the update test.

## Findings and fixes

1. P2: The first implementation truncated the version text. Fixed by moving the state into the primary button and keeping the full version as the status text.
2. P2: The account-selection footer had too much space above its first line. Fixed by reducing its top padding from 10 to 5 points.
3. P2: The notice needed equal top, left, and bottom spacing. Fixed by applying one 8-point inset on all sides.
4. P2: The equal bottom inset was not visually clear because the update row blended into the footer below it. Fixed by adding a separator at the row's exact bottom edge.
5. P2: App-owned windows and panels used unrelated hard-coded radii and edge gaps. Fixed by routing every custom corner and edge-aligned control through shared concentric geometry.
6. P2: Only the account list showed the expected sidebar translucency because adjacent bars drew separate materials. Fixed by moving one material to the full sidebar and clearing the nested list and bar surfaces.

No open P0, P1, or P2 visual issues remain in the tested update flow or app-wide corner audit.

final result: passed
