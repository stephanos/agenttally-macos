# Usage Tracking Hardening Design

## Goal

Address four concrete issues in the native usage tracking pipeline with four separate code commits:

1. Pricing refresh cadence should honor the controller's hourly online refresh decision.
2. Cancelled refreshes must not apply stale results after a newer refresh starts.
3. Claude usage parsing must handle fractional-second timestamps like the Codex tracker does.
4. Codex home/path resolution should be consistent between fingerprint scanning and usage loading.

## Non-Goals

- No UI changes.
- No broad architecture rewrite of the native usage subsystem.
- No bundling of multiple fixes into a single commit.
- No unrelated refactors beyond helper extraction that is directly required by one of the four fixes.

## Current Problems

### 1. Pricing refresh cadence mismatch

`UsageRefreshController` decides whether a refresh should use online pricing once per hour when the machine is not on battery power. `UsagePricingStore` currently returns any cache younger than 24 hours before it even considers a network fetch. That means the controller can request an online pricing refresh and still get stale cached pricing.

### 2. Refresh cancellation race

`AppDelegate.refreshUsage()` cancels any previous refresh task before starting a new one, but the cancelled task can still continue through successful awaits and apply its snapshot afterward. That creates a stale-result overwrite risk.

### 3. Claude fractional-second timestamp gap

The Codex tracker already supports timestamps with fractional seconds. The Claude tracker still uses a plain `ISO8601DateFormatter()` parser, which drops valid entries like `2026-05-04T08:01:00.123Z`.

### 4. Codex home resolution drift

The Codex tracker treats an empty `CODEX_HOME` as "unset" and falls back to `~/.codex`, while `UsageDataScanner` resolves empty `CODEX_HOME` to `.`. That can make fingerprinting and loading observe different directories.

## Design

### Commit 1: Make online pricing refresh actually refresh

Keep the refresh controller's policy unchanged: battery uses offline pricing, plugged-in uses online pricing at most once per hour. Change pricing loading so the caller can explicitly request a network refresh attempt even when a cache exists. The online path should still fall back to cached or bundled pricing if the request fails, but it must not silently short-circuit to a fresh-enough cache when the caller asked for online data.

This change should stay scoped to pricing-store behavior and its tests.

### Commit 2: Prevent stale cancelled refreshes from applying

Treat each refresh cycle as having an identity or explicit cancellation checkpoints. After any awaited operation that can outlive the current refresh cycle, the task must confirm it is still the active refresh before mutating cached data or applying state.

The fix should stay in the app-layer orchestration path rather than changing tracker behavior. The goal is simple: once a newer refresh supersedes an older one, the older one must not update state.

### Commit 3: Add fractional-second parsing to Claude

Mirror the proven Codex timestamp parsing approach in the Claude tracker: first try an ISO8601 parser configured for fractional seconds, then fall back to the plain parser. Add a Claude regression test that uses fractional-second timestamps and proves the entry contributes cost.

This commit should not change any other Claude usage semantics.

### Commit 4: Unify Codex home resolution

Define one consistent rule for `CODEX_HOME`:

- missing or empty `CODEX_HOME` means use `~/.codex`
- otherwise use the provided path

Apply that same rule to both Codex usage loading and usage-data fingerprint scanning. If a small shared helper is the cleanest way to keep the two call sites in sync, that helper is in scope for this commit.

## Testing Strategy

Each commit should include or update focused regression tests:

1. Pricing store/controller tests proving an online refresh attempts network fetch despite a fresh cache, while still falling back safely on failure.
2. App-level refresh orchestration tests proving cancelled refreshes do not apply stale results.
3. Claude tracker test proving fractional-second timestamps are counted.
4. Scanner/tracker tests proving empty and missing `CODEX_HOME` resolve the same way.

After the fourth commit, run the full existing verification commands for the repo.

## Commit Boundaries

The implementation must produce four separate commits in this order:

1. `Fix pricing refresh cadence`
2. `Prevent stale refresh overwrites`
3. `Handle Claude fractional-second timestamps`
4. `Unify Codex home resolution`

Each commit should be independently understandable and scoped to one issue from this spec.
