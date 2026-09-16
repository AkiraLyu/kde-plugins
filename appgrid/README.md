# Plasma App Grid

Plasma App Grid is a Qt 6/QML full-screen application launcher for KDE Plasma 6. Its interaction model and proportions follow GNOME Shell's App Grid, while application discovery, launching, icon loading, configuration, window placement, and Wayland integration reuse Plasma/KDE facilities.

This repository currently contains the third usable milestone:

- a real Plasma launcher applet backed by Kicker's `RootModel`/`AppsModel`;
- full-screen placement on the applet's screen through Plasma's dashboard window;
- GNOME's aspect-ratio modes (3×8, 4×6, 6×4, 8×3) with lazy page delegates;
- GNOME-style adaptive row/column spacing capped at 36 logical pixels;
- mouse wheel, touchpad/touch swipe, keyboard, and pointer navigation;
- application search and launch;
- app-first federated search backed by KRunner for System Settings,
  calculator/unit conversion, and power/session actions;
- persistent drag ordering and stationary-dwell app-folder merging;
- direct pointer tracking, interruptible drop settling, and icons that shrink
  into folder previews without a release-frame jump;
- deliberate hover before opening reorder gaps, generous merge targets, and
  a lifted drag layer that stays visible across multiple pages;
- GNOME-style drag-reorder gap preview that slides tiles aside and wraps rows;
- KDE jump-list, recent-document, launcher, app-details, and hide actions;
- in-app hide/restore of applications, persisted separately from the layout;
- reduced-motion support (per-widget setting plus the system animation-speed modifier);
- fully mirrored right-to-left controls, tile order, paging, and keyboard navigation;
- reconciliation when applications are installed or removed;
- a GNOME-like folder dialog, page indicators, spacing, dimming, and transitions;
- GNOME-style running-application dots backed by KDE's Wayland task model;
- folder popups that zoom from the activating tile and use GNOME's current
  centered 3×3 folder grid;
- continuous touchpad paging in addition to discrete mouse-wheel paging;
- repeated edge paging while dragging, with bounded initial page caching and
  mirrored RTL edge behavior;
- bounded sliding page indicators that remain usable with very large catalogs;
- a Plasma configuration page for icon size, appearance, search, and reduced
  motion;
- compositor-side blur through Wayland's `ext-background-effect-v1`, following
  the Plasma theme and KWin's live Blur-effect capability;
- independently configurable background color and opacity, including a KDE
  color-scheme fallback;
- native indexed search with stable result objects and warmed page delegates;
- local launch history that prioritizes frequent and recent apps within each
  search match tier, with controls to disable learning or clear history;
- input, drag, and rendered-frame performance regression tests for 5,000 apps;
- page-scoped AT-SPI semantics with modal folder-tree isolation;
- system-palette and high-contrast rendering when forced dark mode is off;
- output-following fullscreen geometry across Wayland display removal.

On Wayland, running dots are enabled only inside the trusted `plasmashell`
host. Standalone `plasmawindowed` and QML fixture previews intentionally omit
live task state; use the fixture's `--running` flag for visual verification.

## Requirements

- Qt 6
- Qt 6 Wayland Client development files and `qtwaylandscanner`
- KDE Frameworks 6
- KF6 Config and KWindowSystem development files
- Wayland client development files and `wayland-scanner`
- Plasma 6 (the current implementation is tested against Plasma 6.7)
- CMake 3.22+

The launcher deliberately uses `org.kde.plasma.private.kicker` for the application model and Plasma dashboard window. This avoids reimplementing `.desktop` filtering and Wayland launcher behavior, but it is a private Plasma module, so each Plasma feature release must be included in compatibility testing.

## Build and install

Install the package from AkiraLyu/pkgbuilds with `paru --sudo run0 -S appgrid`.
For development and a staged install:

```sh
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_INSTALL_PREFIX=/usr
cmake --build build
ctest --test-dir build --output-on-failure
DESTDIR="$PWD/staging" cmake --install build
```

Restart Plasma, add **App Grid** to a panel, then assign a global shortcut from the widget's shortcut settings. For an isolated development window:

```sh
plasmawindowed org.kde.plasma.appgrid
```

Rebuild the package after changing QML or either native module:

```sh
paru --sudo run0 --rebuild -S appgrid
```

Restart the launcher host after updating native modules. The package owns the
applet and both native modules under `/usr`.

Search learns from application launches accepted by App Grid, including apps
opened from folders, search results, new-window actions, and recent-file
actions. Exact names and stronger text matches retain priority; among equally
strong matches, recent and frequent choices come first. Empty search preserves
your app order and folders. Learning takes effect on the next query edit or
reopening, without reshuffling the active query.

History is stored in this widget's local Plasma configuration as application
IDs, a decaying usage weight, and the last launch time. It stores no search
queries or document paths. Frequency has a seven-day half-life, its weight is
capped at 32 launches, and a one-day recency bonus helps new habits emerge.
At most 512 applications are remembered; records unused for 90 days are
discarded when history is loaded or updated. Disable **Prioritize frequently
and recently opened apps** to stop learning and use the original text ranking.
**Clear app launch history** removes the saved history when settings are applied.

To verify history saving, restoration, disabling, and clearing across real
Plasma widget host restarts with temporary configuration and a fake launch
backend:

```sh
python3 tests/manual/history_persistence_smoke.py
```

For manual visual checks without a Plasma panel, run the fixture-backed window:

```sh
QT_LOGGING_RULES='kf.i18n.warning=false' qml6 \
    -I build/qml -I package/contents/ui tests/manual/AppGridVisualHarness.qml
```

Pass `-- --folder`, `-- --search`, `-- --rtl`, `-- --light`,
`-- --high-contrast`, `-- --running`, `-- --launch-animation`,
`-- --action-menu`, or `-- --real` to open a deterministic or real-model
visual state. Add
`--capture-launch=/absolute/output.png` to the launch-animation state for a
deterministic mid-transition frame. Any state can be captured with
`--capture=/absolute/output.png`; add `--capture-after=100` to sample a
specific animation time in milliseconds (the default is 350 ms).
`-- --input-smoke` waits for a real wheel
or swipe event and exits successfully after reaching page two. In a second
terminal, `tests/manual/uinput_smoke.py mouse` or
`tests/manual/uinput_smoke.py touchpad` supplies a reproducible kernel uinput
device that travels through libinput, KWin, Wayland, and Qt rather than calling
the QML paging functions directly. It requires write access to `/dev/uinput`.

For an AT-SPI tree check, start the visual harness with accessibility forced
on, then run the matching assertion helper from a second terminal:

```sh
QT_LINUX_ACCESSIBILITY_ALWAYS_ON=1 qml6 \
    -I build/qml -I package/contents/ui tests/manual/AppGridVisualHarness.qml
tests/manual/accessibility_smoke.py
```

Add `-- --folder` to the QML command and `--folder` to the helper to verify
that the dialog is the only exposed interactive subtree. The helper requires
the Python GObject AT-SPI bindings.

The multi-output smoke starts an isolated virtual KWin with two 1280×720
Wayland outputs, opens the real `DashboardWindow` integration, verifies that
the standardized background-effect global was selected, removes the output
containing its visual parent, and checks that both the parent and App Grid move
to the remaining output at its updated geometry. It does not alter the running
desktop session:

```sh
tests/manual/multi_output_smoke.py
```

To verify the real KDE application model and real KRunner backend in the
current Plasma session:

```sh
qml6 tests/manual/KickerModelSmoke.qml
qml6 tests/manual/KRunnerSmoke.qml
qml6 tests/manual/KRunnerSmoke.qml -- firefox
qml6 tests/manual/KRunnerSmoke.qml -- 10 cm in inches
```

## Project layout

- `package/contents/ui/`: QML presentation and interaction components
- `package/contents/ui/SearchController.qml`: local/KRunner search federation
- `package/contents/code/LayoutStore.js`: deterministic layout reconciliation and search
- `package/contents/config/`: persistent settings schema and KCM model
- `src/`: native search index, incremental page model, background-effect
  observer and vendored protocol description
- `tests/`: QML behavior, persistence, search, layout, and performance tests

## Development status

The launcher is functional, but the project remains pre-1.0. The next
milestones are tuning on physical touch hardware, hands-on Orca testing,
moving a live Plasma panel between physical outputs while the launcher is
open, and compatibility testing across supported Plasma feature releases.
