# Changelog

All notable changes to Setatus are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions
follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- The OpenCode limits card breaks today's tokens into input, output, cache read, and cache
  write, with the cache hit rate and cost beside them.

## [0.5.0] - 2026-11-18

### Added

- OpenCode usage limits fall back to the credential stored by OpenCode itself
  (`~/.local/share/opencode/opencode.db`) when 9router is not installed, so a direct
  OpenCode setup no longer needs a manually entered key. Expired OAuth tokens are skipped.

### Changed

- New app icon: a bold S ribbon on the neo-brutalist cream tile, without the offset
  shadow so it stays centred at Dock and Finder sizes. The vector source is
  `Assets/icon-app-s-ribbon.vectorcraft`.
- Today's requests, tokens, and model breakdown come from OpenCode's local session stats,
  which count 9router and direct traffic once; 9router's `usageDaily` table is only a
  fallback when its service is not running.

## [0.4.1] - 2026-11-18

### Changed

- **Set API key** moved out of the popover into the right-click menu (`Set API Key…`),
  entered in a secure alert field; leaving it empty still falls back to 9router's key.

### Fixed

- The popover no longer jumps toward the centre of the screen when the panel grows or
  shrinks while open (slider release adds the fan/charge status line). It now anchors to a
  1 pt rect at the centre of the status item instead of the item's full bounds, so AppKit
  cannot re-anchor it to the button's far edge during a resize.

## [0.4.0] - 2026-11-18

### Changed

- Popover restyled as neo-brutalist: flat cards with 3 pt ink strokes and offset shadows,
  block meters and sliders instead of thin gauges, on a single cream surface with light and
  dark palettes.
- Header replaced the wordmark image with a yellow square and a bold `SETATUS` label; the
  refresh button and last-update time follow the same flat style.
- **Charge limit** moved out of the System card into its own card, with the target percent
  as a hero number and a Paused / SMC limit pill.
- Panel is 356 pt wide (was 340) and auto-sizes from its SwiftUI content via
  `NSHostingController.sizingOptions` instead of a fixed height.
- Tightened card spacing and Ports/Processes list heights so the whole panel fits under the
  menu bar even with the API key field open (~843 pt, 879 pt with the field, 881 pt
  available), and the popover stays anchored below the status item.

### Fixed

- The menu bar title stops refreshing while the popover is open, so the status item no
  longer resizes underneath it and closes the panel mid-read.

### Removed

- FigCraft design sources and generator scripts (`Design/`, `scripts/make-ui.mjs`,
  `scripts/make-ui-v2.mjs`).

## [0.3.0] - 2026-11-18

### Fixed

- The menu bar item collapses to the app icon (plain `S` when no icon is bundled) when its
  title would spill under the notch or off-screen, instead of silently disappearing. The
  full title stays in the tooltip, and the icon opens the same popover.
- Charge limit no longer leaves charging inhibited below the resume point: `CHTE` reads
  back `0x01000000` for `1`, so the helper now treats any non-zero value as inhibited
  and can release the key instead of re-writing it every second.

## [0.2.0] - 2026-11-17

### Added

- **Charge limit** slider in the popover. The root helper pauses charging at the chosen
  percent (50–100, 100 is off) through the SMC charging key — `CHTE` on current Apple
  Silicon firmware, `CHWA`/`CH0B` on older ones — with a 2-point resume hysteresis,
  verifies the key each tick, and reports its state back to the app.
- **Speed test** button in the Internet card, measuring download and upload against
  `speed.cloudflare.com`.
- **Uninstall Setatus…** menu action that stops the helper, removes the login item and
  config, deletes the app after confirmation, and confirms when it is done.
- `--charge`, `--charge-write`, `--smc`, and `--speedtest` command line probes.

### Changed

- Ports card lists every TCP listening port (no allowlist), one row per port, with the
  kill button before the process name.
- A live charge limit is re-sent every 2 s so the helper no longer drops it 30 s after the
  slider moves; a helper restart still releases the key.
- README documents charge control, the Cloudflare speed test, uninstall, and the new
  command line flags.

### Fixed

- Ports, processes, fan, and usage numbers are no longer grouped by locale (`:5173` used
  to render as `:5.173`).
- Charge control is no longer skipped when `fan.json` is stale.
- Turning the limit back to 100 releases an inhibit left behind by an earlier build.

## [0.1.3] - 2026-11-16

### Added

- Activity card with a **Ports / Processes** switch. Ports lists every process listening
  on a TCP port; Processes lists the top 20 by RAM, both with inline SIGTERM confirmation.
- Setatus wordmark and Finder app icon.

### Changed

- Popover redesigned as cards on one surface: OpenCode limits, System, Fan, Internet,
  Activity, and API key.
- Fan helper now runs as a launchd daemon (`RunAtLoad`, `KeepAlive`). It idles on a stale
  or invalid request instead of exiting, re-asserts control after wake, and validates the
  request file.
- Documentation rewritten for the v2 popover and the daemon-based helper.

## [0.1.2] - 2026-11-10

### Added

- Menu bar metric labels and a per-metric choice between percentage and temperature.
- Menu bar menu entries to toggle metrics and reset to defaults.

## [0.1.1] - 2026-11-10

### Fixed

- Shell and SMC calls no longer block the main thread, which caused menu bar hangs.

## [0.1.0] - 2026-11-10

### Added

- Initial MVP: a menu bar monitor for OpenCode usage, CPU/GPU/RAM load, fans, network,
  power, and temperatures.
- Popover with OpenCode limit windows, system tiles, fan control, and internet stats.
- Privileged fan helper, Launch at Login, and `--selfcheck` / `--killtest` checks.

[Unreleased]: https://github.com/albae69/setatus/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/albae69/setatus/releases/tag/v0.5.0
[0.4.1]: https://github.com/albae69/setatus/releases/tag/v0.4.1
[0.4.0]: https://github.com/albae69/setatus/releases/tag/v0.4.0
[0.3.0]: https://github.com/albae69/setatus/releases/tag/v0.3.0
[0.2.0]: https://github.com/albae69/setatus/releases/tag/v0.2.0
[0.1.3]: https://github.com/albae69/setatus/releases/tag/v0.1.3
[0.1.2]: https://github.com/albae69/setatus/releases/tag/v0.1.2
[0.1.1]: https://github.com/albae69/setatus/releases/tag/v0.1.1
[0.1.0]: https://github.com/albae69/setatus/releases/tag/v0.1.0
