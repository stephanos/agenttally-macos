# AgentTally

[![release](https://img.shields.io/github/v/release/stephanos/agenttally-macos)](https://github.com/stephanos/agenttally-macos/releases/latest)

`AgentTally` is a standalone macOS menu bar app for tracking AI agent spending.

The app shows Claude Code and Codex spend for today and the current month, and refreshes every 60s.

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

AgentTally checks GitHub Releases for updates once per day and includes a
`Check for Updates...` menu item.

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

For screenshot/demo work with canned fixture data instead of live usage:

```sh
mise run demo
```

`mise` manages the Bun toolchain for this project and uses the system Swift toolchain. The build tasks install the local `ccusage` dependency, compile the helper, and stage both binaries into `AgentTally.app`.

## Releases

To cut a new release:

```sh
mise run check
git tag -a v0.10 -m "v0.10"
git push origin v0.10
```

Pushing the tag runs the GitHub Actions release workflow, which builds the app,
uploads `AgentTally.app.zip`, publishes `appcast.xml`, and makes the release
available to Sparkle. After the workflow completes, verify the new version at:

- <https://github.com/stephanos/agenttally-macos/releases>
- <https://github.com/stephanos/agenttally-macos/releases/latest/download/appcast.xml>

Release archives are signed for Sparkle updates with an EdDSA key. For local
releases, the private key is read from the macOS Keychain. For GitHub Actions,
set `SPARKLE_PRIVATE_ED_KEY` to the value exported by:

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle_private_key
```

The app bundle is ad-hoc code signed by default so Sparkle can verify release
archives without requiring an Apple Developer ID certificate. Set
`CODESIGN_IDENTITY` to use a real signing identity later.
