---
id: meta-0011
status: proposed
date: 2026-11-26
approved_by:
references:
  - meta-0006-hardening-and-stack-neutral-implement.md
  - meta-0010-pilot-findings.md
---

# meta-0011 Tools travel with the project: pinned yq, jq and renderer inside `harness/deps/`

Meta ADR (workflow change, exempt from the project ADR hardcap — see
`WORKFLOW_CHANGES.md`). **Proposed** — nothing in `workflow.yaml` or `gates/`
changes until the user approves it (set `status: accepted` and
`approved_by: user`).

## Context and Problem Statement

1. **The gates' tools are installed system-wide.** Every gate needs mikefarah
   `yq` v4 and `jq`. Today the user installs them with winget, brew or apt, and
   `_lib.sh` probes six install directories to find them. The owner does not
   want system-wide installs for this (2026-11-25): a project should carry its
   own tools. The version is also whatever the machine has — CI pins yq
   v4.53.3 and the self-tests run against that, but a developer machine runs
   any v4, and yq's v4 minors differ in details the gates use.
2. **The renderer is found by a Claude Code path.** `AGENTS.md`, the `design`
   gate's hint, `workflow.yaml` (`render_tool`) and `harness/README.md` name
   `~/.claude/skills/mermaid-render/render.sh`. OpenCode keeps its own skills
   in `~/.config/opencode/skills`; with an OpenCode-only install the agent is
   told to run a script that does not exist. (The skills themselves already
   point at their own directory — no ADR needed for that; the harness
   contract is what still names the Claude path.)

## Decision Drivers

- Running the gates needs no admin rights and no package manager.
- One tool version everywhere: CI, every machine, every agent.
- Nothing is downloaded without a pinned checksum; nothing binary goes into
  git history.
- The agent never fetches tools on its own — downloading is the user's call.
- Works offline once fetched; works in Git Bash, Linux and macOS.

## Considered Options

**For the tools**

1. **System-wide, as today** — document the versions, change nothing else.
2. **Commit the binaries** into each project — works from a fresh clone, but
   about 15 MB per platform, five platforms, again with every version bump,
   in every project's history.
3. **Pinned bootstrap into a git-ignored folder** — a script inside the
   harness fetches the pinned versions for this machine, checks each against a
   SHA-256 written in the repo, and puts them in `harness/deps/bin/`, ignored
   by git like `.venv` or `node_modules`. The gates look there first.
4. **A version manager** (mise, asdf, aqua) — pins versions in the repo too,
   but needs the manager itself installed system-wide: the dependency moves,
   it does not go away.

**For the renderer**

- **A. Resolver** — the gates look for the mermaid-render skill in every
  known skill directory (Claude Code, OpenCode, `.agents`, project-level) and
  print the path they found. One copy of the script; the harness still needs
  a skill installed in the user's home.
- **B. The renderer travels with the project** — `harness/deps/render.sh` is
  a copy of the skill's `render.sh`; its Mermaid library is pinned and fetched
  like yq and jq. Every agent runs the same command, `bash
  harness/deps/render.sh …`, and the harness needs no skill to work. The skill
  stays for ad-hoc use and is the source the copy is checked against.

## Decision Outcome

Proposed: **option 3** for the tools and **B** for the renderer.

Open for the owner: **does the system copy still count when `deps/bin` is
empty?** Proposed **yes** — the gates prefer `harness/deps/bin` and fall back
to a system yq/jq (still checked for mikefarah v4), so CI and existing
machines keep working and the missing-tool message names `setup.sh` first.
The strict alternative refuses system tools entirely; it guarantees the pin
but breaks every existing setup until `setup.sh` has run.

### What changes

- **`harness/deps/setup.sh`** — detects the platform (Linux and macOS on
  amd64/arm64, Windows on amd64), reads `harness/deps/deps.lock`, downloads
  with curl (wget as fallback), verifies the SHA-256, and installs into
  `harness/deps/bin/` (`yq`, `jq`) and `harness/deps/vendor/`
  (`mermaid.min.js`). A file whose checksum already matches is not fetched
  again; a mismatch leaves nothing behind. `--check` is pure: exit 1 when
  anything is missing or differs. `HARNESS_DEPS_MIRROR` replaces the download
  host (proxies, offline mirrors, the self-tests).
- **`harness/deps/deps.lock`** — plain text, one line per tool and platform:
  name, platform, URL, SHA-256. Plain text because yq is one of the things it
  installs. Pinned: yq v4.53.3 and jq 1.8.2 (checksums from GitHub's release
  asset digests; the Windows binaries winget installed match them byte for
  byte), Mermaid 11.16.0 (the build the skill vendors, identical to
  jsDelivr's copy).
- **`harness/deps/.gitignore`** — `bin/`, `vendor/`; it travels with the
  directory.
- **`_lib.sh`** — puts `harness/deps/bin` (found relative to the gate
  scripts) first on `PATH`; the system probes stay as the fallback; the
  missing-tool message names `bash harness/deps/setup.sh` first.
- **Renderer** — `harness/deps/render.sh` is the skill's `render.sh`;
  `tools/check-repo.sh` keeps the two identical. `AGENTS.md`, `design.sh`'s
  hint, `workflow.yaml` (`render_tool: deps/render.sh`) and
  `harness/README.md` say `bash harness/deps/render.sh`.
- **`init.sh`** copies `harness/deps/` without `bin/` and `vendor/` and names
  `setup.sh` as the next step; it downloads nothing. `tools/sync-skill.sh`
  keeps `bin/` and `vendor/` out of the skill assets.
- **`AGENTS.md`** — `setup.sh` downloads binaries: the agent runs it only when
  the user asked for it. A missing tool stays exit 2 (environment), where a
  loop stops.
- **CI** installs through `setup.sh` instead of `sudo wget`, so the real
  download and checksum path runs on every push.
- **`tools/check-repo.sh`** — the tombstone `sha256` (left from the removed
  sign-off) skips `harness/deps/`: a download checksum is a different thing.

### Confirmation

Extend `tests/gates/test_gates.sh`, one check per claim, without network:

- `setup.sh` from a local mirror with a test lock installs, and `--check`
  passes;
- a tampered download fails with "checksum mismatch" and leaves nothing in
  `bin/`;
- a second run fetches nothing (the mirror is gone and it still passes);
- an installed binary changed afterwards fails `--check`;
- an unsupported platform fails with a message naming it;
- the gates prefer `harness/deps/bin` over a system `yq`;
- a scaffold carries `deps/` without `bin/` and `vendor/`.

CI additionally runs `setup.sh` against GitHub and jsDelivr on Linux, then the
full suite with nothing but those tools.

### Not in this ADR

- `bash` ≥ 4 and `git` stay system tools (macOS still needs
  `brew install bash`).
- The project's own tools (pytest, behave, …) are `project.yaml`'s business —
  a virtual environment, as in the pilot, is already local.

### Consequences

- Good: a fresh machine needs bash, git and one `setup.sh` — no admin rights,
  no package manager.
- Good: every machine and CI run the same pinned versions, checked against
  checksums in the repo.
- Good: one render command for every agent; the harness works without any
  skill installed.
- Bad: one more script and lock file to maintain; a version bump means new
  checksums for five platforms.
- Bad: the first `setup.sh` needs network, about 15 MB per machine.
- Bad: two copies of `render.sh` (kept identical by `check-repo.sh`).
- Neutral: with the fallback, a machine that skips `setup.sh` runs on its
  system tools — the pin is only as strong as that habit.
