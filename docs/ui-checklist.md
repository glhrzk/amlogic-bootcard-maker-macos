# UI checklist — BootcardMaker for macOS

Source: design doc §UI design (`docs/superpowers/specs/2026-11-05-bootcardmaker-macos-design.md`)
and plan Task 5. The `pro-rules.md` checklist is mobile/native scoped;
it is applied here adapted to a mouse-driven desktop window: its
contrast, labelling, focus-order, and disabled-state checks apply;
its 44pt touch-target rule does not apply literally.

Status key:
- `Checked (static)` — verified by reading the Swift source on this
  Linux VM. The app cannot be built or run here, so this is not
  runtime proof.
- `Unchecked — Mac only` — needs the built app running on the owner's
  Mac. Must be checked there before the UI is called done.

## Layout and labels

- [ ] `Unchecked — Mac only` Window order, top to bottom: title and
  description, Choose disk, Choose bin file, Partition and Format,
  dry-run controls, Make, status line.
- [ ] `Checked (static)` Every control has a visible text label.
  No icon-only button, no emoji icon anywhere in the window.
  Evidence: `grep Image(` in `Sources/` finds nothing; the
  non-ASCII scan of the app sources finds no emoji; every button
  and picker in `MainView.swift` carries a text label. On-screen
  rendering is still Mac only.
- [ ] `Unchecked — Mac only` Disk picker lists disks as
  `Name — size (diskN)`, with nothing selected by default. A disk
  that disappears on Refresh clears the selection.
- [ ] `Unchecked — Mac only` Bin field is read-only, shows the chosen
  path, and the `Open…` button opens the system file picker for one
  file of any extension.
- [ ] `Unchecked — Mac only` The `Yes` checkbox for partition/format
  is ticked by default. When unticked, the note about keeping the
  existing partition table is shown.
- [ ] `Checked (static)` Make is disabled until a disk (or dry
  run) and an existing, non-empty bin file are chosen, and while an
  operation is running. Evidence: `canMake` in `MainViewModel`
  (`MainView.swift`) requires `binSize > 0` and a selected disk or
  dry-run mode, and is false while `isWorking`. Runtime behaviour
  is still Mac only.

## Confirmation sheet

- [ ] `Checked (static)` The sheet is the only confirmation step.
  It shows disk name, identifier, and size; bin file name and size;
  and the partition/format choice. Evidence: `ConfirmationView` in
  `MainView.swift` renders exactly those rows; no other
  confirmation dialog exists in the app target. On-screen
  rendering is still Mac only.
- [ ] `Checked (static)` The sheet shows the warning that the
  disk will be erased, and offers Cancel and `Erase and Make`.
  Evidence: same file, physical-disk branch of `ConfirmationView`.
  On-screen rendering is still Mac only.
- [ ] `Checked (static)` Dry-run sheet shows the image size and
  that a new image file will be created and left for inspection,
  instead of a physical disk. Evidence: dry-run branch of
  `ConfirmationView`. On-screen rendering is still Mac only.

## Progress, success, and errors

- [ ] `Checked (static)` While writing, a progress indicator is
  shown, all controls are disabled, there is no cancel button, and
  the UI states that the card must not be removed. Evidence:
  `ProgressView` plus the no-cancel text in `MainView.swift`,
  shown only while `isWorking`, when `canMake` is false and the
  pickers, buttons, and toggles are disabled. No cancel control
  exists in the file. On-screen behaviour is still Mac only.
- [ ] `Checked (static)` `Success!` appears only after
  `makeDiskOperation` returns (re-read verification passed).
  Evidence: `runOperation` in `MainViewModel` awaits the detached
  operation before `finishSuccess` sets the status message.
  Runtime behaviour is still Mac only.
- [ ] `Checked (static)` An error names the failed step in plain
  language and states honestly that no rollback is claimed.
  Evidence: `finishError` surfaces `DiskOperationError`'s
  step-naming descriptions (Task 4); no rollback wording exists in
  the app target. Runtime behaviour is still Mac only.

## Keyboard, focus, and readability

- [ ] `Unchecked — Mac only` Full keyboard access with a visible
  focus indicator and a sensible focus order matching the visual
  order.
- [ ] `Unchecked — Mac only` Body text contrast is at least 4.5:1 in
  both light and dark mode. Semantic colours only; no raw hex in
  components.
- [ ] `Unchecked — Mac only` Reduced motion does not break the layout
  (no non-essential animation is used).
- [ ] `Unchecked — Mac only` Larger system text does not break the
  layout or clip any label.

## Dry-run controls

- [ ] `Checked (static)` The dry-run toggle and image-size picker
  (default partition start + 64 MiB, 1 GiB, 4 GiB, 16 GiB sparse)
  are labelled, and enabling dry-run disables the physical disk
  picker with an explanatory note. Evidence: dry-run section of
  `MainView.swift`; `DryRunSize` labels in `DryRun.swift`.
  On-screen rendering is still Mac only.
- [ ] `Checked (static)` Dry-run never asks for administrator
  approval: no elevation prompt appears in dry-run mode. Evidence:
  no `Authorization` reference in `DryRun.swift`,
  `MainView.swift`, or `DiskListProvider.swift`, and
  `DryRunSession` calls `makeDiskOperation` with `dryRunDevice`
  set, which Task 4 routes through unelevated `ProcessRunner`.
  Runtime behaviour is still Mac only.
