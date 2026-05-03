# AgentTally

[![release](https://img.shields.io/github/v/release/stephanos/agenttally-macos)](https://github.com/stephanos/agenttally-macos/releases/latest)

`AgentTally` is a standalone macOS menu bar app for tracking AI agent spending.

Right now, only Claude Code is supported. The app shows your Claude Code spend for today and the current month, and refreshes every 60s.

<p align="center">
  <img src="docs/menu-bar.png" alt="AgentTally menu bar screenshot">
</p>

## Install

Download the latest packaged build from GitHub Releases:

- <https://github.com/stephanos/agenttally-macos/releases>

Then:

1. Download `AgentTally.app.zip`
2. Unzip it
3. Move `AgentTally.app` to `/Applications`
4. Open `AgentTally.app`

On first launch, macOS may ask you to confirm opening the app.

## Development

To build from source, you need:

- `mise`

From this directory:

```sh
mise trust
mise install
mise run install
```

The install task copies the bundle to `/Applications/AgentTally.app` and launches it.
It also enables "Open at Login" by default the first time the app runs.

For local development:

```sh
mise run dev
```

`mise` manages the Bun toolchain for this project and uses the system Swift toolchain. The build tasks install the local `ccusage` dependency, compile the helper, and stage both binaries into `AgentTally.app`.
