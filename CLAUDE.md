# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

The chezmoi source directory (`~/.local/share/chezmoi`) for a macOS dotfile setup. Everything here is a *source* file that chezmoi transforms into a target file in `$HOME`. Editing files in `$HOME` directly is wrong — edit here and re-apply.

## Commands

```bash
chezmoi diff                  # preview what apply would change (uses delta if installed)
chezmoi apply -v              # render templates + run scripts into $HOME
chezmoi apply -v --dry-run    # dry run
chezmoi execute-template < dot_config/git/config.tmpl   # render one template to stdout
chezmoi data                  # dump the template data available to all templates
chezmoi cd                    # shell into this directory
chezmoi state delete-bucket --bucket=scriptState        # force run_once_/run_onchange_ scripts to rerun
reload                        # alias: rbw sync && chezmoi apply && exec zsh
```

There are no builds, linters, or tests. Verification is `chezmoi diff` / `chezmoi execute-template`.

## Naming conventions (chezmoi, not arbitrary)

Source filenames encode target attributes; renaming changes behaviour:

- `dot_` → leading `.` (`dot_zshrc.tmpl` → `~/.zshrc`)
- `private_` → mode 0600 (`private_dot_ssh/` → `~/.ssh` 0700)
- `symlink_` → the file's rendered *contents* are the symlink target (`symlink_dot_aws.tmpl` contains `~/.config/aws`, so `~/.aws` symlinks there)
- `.tmpl` → rendered as a Go text/template with the data below
- Scripts in `.chezmoiscripts/` are ordered by `run_{once,onchange}_{before,after}_NN-name.sh.tmpl`

## Template data model

`.chezmoi.toml.tmpl` is the config template: on first `chezmoi init` it prompts (via `promptBoolOnce`/`promptStringOnce`) for `use_secrets`, `personal_computer`, `dev_computer`, `email`, and writes them into `[data]`. Those three booleans are the machine-class switches that gate almost everything else — package sets, mise install, secret rendering. Also defined there: XDG path vars (`.xdgConfigDir`, `.xdgDataDir`, `.xdgScriptsDir`, …) that templates use instead of hardcoding paths.

Static data lives in `.chezmoidata/`, auto-merged into the template namespace:
- `packages.toml` → `.packages.homebrew.{common,dev_computer,personal_computer}.{formulae,casks}` (darwin) and `.packages.apt.{common,dev_computer,personal_computer}.packages` (Debian-likes), each plus `to_remove`
- `packages.yaml` → `.versions.<tool>` = pinned versions for the tools installed from a release download (`gron`, `herdr`, `rbw`). Nothing else belongs here: apt owns upgrades for repo-backed packages, and `claude` self-updates.
- `bitwarden.toml` → `.bitwarden.items.<name>` = Bitwarden item UUIDs

## Secrets: Bitwarden

Secrets are never stored here. Templates pull them at apply time with chezmoi's `rbwFields` function keyed by the UUIDs in `.chezmoidata/bitwarden.toml`, e.g. `dot_config/shell/private_private.sh.tmpl` (GitHub tokens) and `dot_config/aws/private_credentials.tmpl` (S3 keys for the `runpod` profile). Adding a secret = add the item UUID to `bitwarden.toml`, then reference `(rbwFields .bitwarden.items.<name>).<field>.value`.

The client is [`rbw`](https://github.com/doy/rbw), not the official `bw`. `rbwFields` shells out to `rbw get --raw <needle>`, and a needle can be a name, URI *or* UUID — which is why the migration off `bw` needed no change to `bitwarden.toml`.

There is no session file and no `BW_SESSION` plumbing: `rbw-agent` holds the vault key in memory the way `ssh-agent` holds keys. The prerequisites hook unlocks the agent before chezmoi reads the source state, so an apply costs one pinentry prompt no matter how many secrets it renders — `bw` needed one per `bitwardenFields` call, because the session file it wrote was never in chezmoi's environment. The hook also sets `lock_timeout` to 86400 (rbw's default is 3600), so a working day's worth of applies costs one prompt in total.

`rbw-agent` also serves an SSH agent socket in its runtime dir (`$XDG_RUNTIME_DIR/rbw`, or `${TMPDIR}/rbw-<uid>` where the platform has no runtime dir, which is always the case on macOS). `dot_config/shell/exports.sh.tmpl` computes that path at shell startup and points `SSH_AUTH_SOCK` at it *only if the socket exists*, so a shell started before the agent keeps whatever agent the session already had. This replaced the Bitwarden desktop app's socket, which was darwin-only.

## Script ordering on a fresh machine

Scripts with a `before_`/`after_` prefix run in those phases; a plain `run_once_NN` runs in the file phase, *between* them. Nothing in `.chezmoiscripts/` runs early enough to install a prerequisite that templates or `before_` scripts need — that job belongs to the hook in step 0.

0. **`.install-prerequisites.sh`** — not a script target at all. It is wired to `hooks.read-source-state.pre` in `.chezmoi.toml.tmpl`, so chezmoi runs it *before reading the source state*: earlier than any `run_` script and before any `rbwFields` template is rendered. Installs Xcode CLT + Homebrew (darwin), the apt basics (Debian), and `rbw` when `use_secrets` — then unlocks the rbw agent. See "The prerequisites hook" below.
1. `run_onchange_before_09-apt-repos` (Debian) — add the mise / gh / docker / tailscale apt repos
2. `run_onchange_before_10-homebrew-packages` (darwin) / `run_onchange_before_11-apt-packages` (Debian) — install the enabled machine classes' packages; the darwin one skips casks when `is_ci_workflow`
3. (files applied)
4. `run_onchange_after_10_remove_packages` (both OSes), `run_onchange_after_20-release-tools` + `run_onchange_after_21-rbw` (Debian), `run_once_after_22-claude-code` (both), `run_onchange_after_30-mise-install` (dev machines that have `mise`)
5. **`.chezmoi-summary.sh`** — another hook, on `hooks.apply.post`. Prints the completion banner and, when the session predates the apply, how to pick up the new login shell and PATH.

### The prerequisites hook

There are two root-level hook scripts, both dot-prefixed so chezmoi does not treat them as targets: `.install-prerequisites.sh` on `hooks.read-source-state.pre`, and `.chezmoi-summary.sh` on `hooks.apply.post`. The summary is registered on `apply.post` alone because `init.post` *also* fires during `chezmoi init --apply` (verified in a sandbox), which would print it twice.

`.install-prerequisites.sh` sits at the repo root; the leading dot keeps chezmoi from treating it as a target. It replaced `run_once_00-install-pre-requisites`, which could not work: as a plain `run_once_`, it ran *after* the `before_` package scripts, so on a bare machine Homebrew did not exist when `before_10` wanted it, and the Bitwarden client did not exist when the secret templates rendered. That is what made a fresh machine need two applies.

Two rules for anything added to it:

1. **Exit fast when the tool is present.** The hook runs on every command that reads the source state — `apply`, `diff`, `status`, `data`.
2. **Never exit non-zero.** A failing hook blocks every chezmoi command, including the `chezmoi diff` you would debug it with. Warn to stderr and let the `run_` scripts retry; they all keep their own presence checks for exactly this reason.

It is a plain `sh` script, not a template, so it cannot interpolate chezmoi data. It reads the `rbw` pin straight out of `.chezmoidata/packages.yaml` with `sed`, and reads `use_secrets` out of the generated `~/.config/chezmoi/chezmoi.toml` with `grep` — deliberately not `chezmoi data`, which would re-enter the hook.

Changing the hook stanza means existing machines need `chezmoi init` re-run to regenerate their config; the `promptOnce` values already stored are not re-asked.

### Which mechanism for a new tool

- **In the Debian archive** → add to the `packages.apt.*` array. Done.
- **Has an official apt repo** (docker, gh, tailscale, mise) → add the repo to `run_onchange_before_09-apt-repos` via `add_repo`, then list the package in the apt array like any other. More maintainable than a vendor install script, and apt handles upgrades.
- **Release download only** (gron, herdr, rbw) → pin it in `.chezmoidata/packages.yaml` and install it in a `run_onchange_after_2x` script, into `~/.local/bin` without sudo. The pin is what triggers the re-run. `rbw` is the exception that proves the rule: templates need it *before* any script runs, so the hook installs it too, and `after_21-rbw` exists only to move an already-installed box onto a bumped pin.
- **Self-updating installer** (claude) → `run_once_`, guarded by `command -v`. Nothing to pin.

Keep these groups in separate scripts so an apt failure cannot block a download installer, and vice versa.

Shared bash helpers (`_inArray_`, `_debArch_`, `_versionStamp_`) live in `.chezmoitemplates/shared_script_utils.bash`, and the apt preamble (`SUDO` plus a locale-safe `apt_get`) in `.chezmoitemplates/debian_apt.bash`. Both are pulled in with `{{ template "<name>" . }}` — that's the only way to share code between scripts. Never write a literal `template` action for a file inside that same file, even in a comment: chezmoi executes it and recurses until it hits the template depth limit.

`run_onchange_*` scripts rerun when their *rendered* content changes. `30-mise-install` therefore embeds a hash comment (`{{ include "dot_config/mise/config.toml.tmpl" | sha256sum }}`) so editing the mise config retriggers `mise install`. Use the same trick when a script must react to a data file it doesn't otherwise interpolate.

## Cross-platform rules

Targets are macOS (Homebrew) and Debian-likes — Debian, Ubuntu, Proxmox (apt). Two rules keep it working:

**Detect the distro with `dig`, never `.chezmoi.osRelease.id`.** chezmoi renders templates with `missingkey=error`, and `osRelease` is an *empty map* off Linux, so a plain field access aborts the whole apply on macOS — `| default ""` does not save you, the lookup has already failed. The working idiom, used by every OS-gated script here:

```
{{- $id := dig "id" "" .chezmoi.osRelease -}}
{{- $idLike := dig "idLike" "" .chezmoi.osRelease -}}
{{- if and (eq .chezmoi.os "linux") (or (eq $id "debian") (contains "debian" $idLike)) -}}
```

Debian sets `ID=debian` with no `ID_LIKE`; Ubuntu sets `ID=ubuntu` with `ID_LIKE=debian` — hence checking both.

**A script whose OS guard is false renders empty, and chezmoi skips empty scripts.** That is the mechanism for per-OS scripts; no other guard is needed.

To verify a Linux branch from macOS, force the guard and syntax-check the result — the OS cannot be overridden at runtime:

```bash
sed -E 's/dig "id" "" \.chezmoi\.osRelease/"debian"/g; s/\(eq \.chezmoi\.os "linux"\)/true/g' \
  .chezmoiscripts/run_onchange_before_11-apt-packages.sh.tmpl | chezmoi execute-template | bash -n
```

Package names diverge between the two managers (`gpg`/`gnupg`, `pygments`/`python3-pygments`), and a few Homebrew formulae have no apt package at all — `.chezmoidata/packages.toml` documents which, and which script installs them instead. GUI apps stay darwin-only: the Linux boxes are headless.

The scripts that need the distro codename or architecture read them from `/etc/os-release` and `dpkg --print-architecture` **at runtime**, not from `.chezmoi.osRelease` at template time. That keeps the rendered content byte-identical on every box, so a `run_onchange_` script re-runs only on a real change (a version bump, a repo edit) rather than because a different machine applied it.

`.chezmoiignore` is itself a template. It drops the secret-backed targets (`.config/aws/credentials`, `.config/shell/private.sh`) when `use_secrets` is false, which is what lets a machine without Bitwarden apply cleanly. It also ignores this file and `README.md`, which would otherwise be applied into `$HOME` as `~/CLAUDE.md`.

## Other structure

- `.chezmoiexternal.toml` — downloads antigen.zsh into `~/.local/scripts/`; `dot_zshrc.tmpl` sources it and defines the zsh plugin set.
- `dot_config/shell/{aliases,exports}.sh.tmpl` — sourced by `.zshrc`; `exports.sh.tmpl` points AWS at `~/.config/aws` and, on darwin only, sets `SSH_AUTH_SOCK` to the Bitwarden desktop app's agent socket (that app is macOS-only, so Linux keeps whatever agent the session provides).
- `private_dot_ssh/config` — homelab hosts (Star Trek names → LAN IPs); public keys only in `private_keys/`.
- `dot_agents/skills/` — agent skills, stored as real files and applied to `~/.agents/skills`. This is the single source of truth: `dot_claude/symlink_skills.tmpl` points `~/.claude/skills` at it, so Claude Code sees the same set. Add a skill under `dot_agents/skills/`, not under `~/.claude/skills`.
