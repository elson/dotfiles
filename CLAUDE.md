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
reload                        # alias: bw sync && chezmoi apply && exec zsh
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

`.chezmoi.toml.tmpl` is the config template: on first `chezmoi init` it prompts (via `promptBoolOnce`/`promptStringOnce`) for `use_secrets`, `personal_computer`, `dev_computer`, `email`, and writes them into `[data]`. Those three booleans are the machine-class switches that gate almost everything else — package sets, mise install, secret rendering. Also defined there: XDG path vars (`.xdgConfigDir`, `.xdgDataDir`, `.xdgScriptsDir`, …) that templates use instead of hardcoding paths, and `.bwSessionFile`.

Static data lives in `.chezmoidata/`, auto-merged into the template namespace:
- `packages.toml` → `.packages.homebrew.{common,dev_computer,personal_computer}.{formulae,casks}` (darwin) and `.packages.apt.{common,dev_computer,personal_computer}.packages` (Debian-likes), each plus `to_remove`
- `bitwarden.toml` → `.bitwarden.items.<name>` = Bitwarden item UUIDs

## Secrets: Bitwarden

Secrets are never stored here. Templates pull them at apply time with chezmoi's `bitwardenFields` function keyed by the UUIDs in `.chezmoidata/bitwarden.toml`, e.g. `dot_config/shell/private_private.sh.tmpl` (GitHub tokens) and `dot_config/aws/private_credentials.tmpl` (S3 keys for the `runpod` profile). Adding a secret = add the item UUID to `bitwarden.toml`, then reference `(bitwardenFields "item" .bitwarden.items.<name>).<field>.value`.

`run_once_10-bitwarden-session.sh.tmpl` logs in/unlocks `bw` and writes `export BW_SESSION=…` to `~/.zshrc_bitwarden_session`, which the private shell file sources. Applying with a locked vault will prompt or fail — run `bw unlock` first.

## Script ordering on a fresh machine

1. `run_once_00-install-pre-requisites` — darwin: Xcode CLT, Homebrew, `bw`; Debian: `apt-get install curl git gnupg`
2. `run_once_10-bitwarden-session` — unlock vault, persist session (skipped entirely unless `use_secrets`)
3. `run_onchange_before_10-homebrew-packages` (darwin) / `run_onchange_before_11-apt-packages` (Debian) — install the enabled machine classes' packages; the darwin one skips casks when `is_ci_workflow`
4. (files applied)
5. `run_onchange_after_10_remove_packages` (both OSes), `run_onchange_after_30-mise-install` (dev machines that have `mise`)

Shared bash helpers (`_inArray_`, `get_json_value_sed`) live in `.chezmoitemplates/shared_script_utils.bash` and are pulled in with `{{ template "shared_script_utils.bash" . }}` — that's the only way to share code between scripts.

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

Package names diverge between the two managers (`gpg`/`gnupg`, `pygments`/`python3-pygments`), and several Homebrew formulae have no apt equivalent — `.chezmoidata/packages.toml` documents which and why. GUI apps stay darwin-only: the Linux boxes are headless.

`.chezmoiignore` is itself a template. It drops the secret-backed targets (`.config/aws/credentials`, `.config/shell/private.sh`) when `use_secrets` is false, which is what lets a machine without Bitwarden apply cleanly. It also ignores this file and `README.md`, which would otherwise be applied into `$HOME` as `~/CLAUDE.md`.

## Other structure

- `.chezmoiexternal.toml` — downloads antigen.zsh into `~/.local/scripts/`; `dot_zshrc.tmpl` sources it and defines the zsh plugin set.
- `dot_config/shell/{aliases,exports}.sh.tmpl` — sourced by `.zshrc`; `exports.sh.tmpl` points AWS at `~/.config/aws` and, on darwin only, sets `SSH_AUTH_SOCK` to the Bitwarden desktop app's agent socket (that app is macOS-only, so Linux keeps whatever agent the session provides).
- `private_dot_ssh/config` — homelab hosts (Star Trek names → LAN IPs); public keys only in `private_keys/`.
- `dot_agents/skills/` — agent skills, stored as real files and applied to `~/.agents/skills`. This is the single source of truth: `dot_claude/symlink_skills.tmpl` points `~/.claude/skills` at it, so Claude Code sees the same set. Add a skill under `dot_agents/skills/`, not under `~/.claude/skills`.
