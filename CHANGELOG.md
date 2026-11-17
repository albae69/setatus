# Changelog

All notable changes to Setatus are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions
follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
- FigCraft sources and refreshed previews for the v2 popover.

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

[Unreleased]: https://github.com/albae69/setatus/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/albae69/setatus/releases/tag/v0.2.0
[0.1.3]: https://github.com/albae69/setatus/releases/tag/v0.1.3
[0.1.2]: https://github.com/albae69/setatus/releases/tag/v0.1.2
[0.1.1]: https://github.com/albae69/setatus/releases/tag/v0.1.1
[0.1.0]: https://github.com/albae69/setatus/releases/tag/v0.1.0
