---
name: chezmoi-packages
description: Packages on this machine are declared in chezmoi's data files and installed by its scripts, so a bare brew or apt install is recorded nowhere and reaches no other machine. Use when installing or removing a tool, upgrading a pinned one, or explaining why a tool is present on one machine and missing on another.
---

# chezmoi packages

Installing a package is a **declaration**, not a command: name it in the source repo, apply, and the install scripts converge every machine. `brew install` and `apt install` typed straight into a shell work exactly once, on one box, until it is rebuilt.

Two data files hold every declaration, and both live in the source directory (`chezmoi source-path`):

| File | Holds |
| --- | --- |
| `.chezmoidata/packages.toml` | everything a package manager installs — `packages.homebrew.*` on darwin, `packages.apt.*` on Debian-likes |
| `.chezmoidata/packages.yaml` | `versions.<tool>` — pinned versions, and **only** for tools installed by downloading a release |

Language runtimes and their tooling are not packages here: they live in `dot_config/mise/config.toml.tmpl`.

## 1. Pick the mechanism

Work down this list and stop at the first that fits. The choice decides which file you edit.

1. **In the distro archive or a Homebrew formula** — add the name to the arrays in `packages.toml`. Nothing else.
2. **Has an official apt repo** (docker, gh, tailscale, mise) — add the repo to `.chezmoiscripts/run_onchange_before_09-apt-repos.sh.tmpl` via `add_repo`, then list the package in the apt array like any other. apt then owns its upgrades, so it takes **no** pin in `packages.yaml`.
3. **Release download only** (gron, herdr, rbw) — pin the version in `packages.yaml` and install it in a `run_onchange_after_2x` script, into `~/.local/bin` without sudo.
4. **Self-updating installer** (claude) — a `run_once_` script guarded by `command -v`. Nothing to pin, because the tool updates itself.

A pin in `packages.yaml` is a claim that nothing else upgrades the tool. Adding one for a package that apt or Homebrew already owns creates two things that both believe they control the version.

## 2. Choose the machine class

Each manager's packages are split into three buckets, and a machine installs `common` plus whichever classes it is:

```bash
chezmoi data | jq '{dev_computer, personal_computer}'
```

`common` is the default; reach for a class only when the package genuinely does not belong everywhere. Two constraints are not preferences:

- **GUI apps are darwin-only.** The Linux boxes are headless, so a cask has no apt counterpart to add.
- **The two managers disagree on names** (`gpg` / `gnupg`, `pygments` / `python3-pygments`). Confirm the name each manager actually uses rather than copying across; some Homebrew formulae have no apt package at all, in which case mechanism 3 covers Linux.

Homebrew arrays are `formulae` and `casks`; apt has a single `packages`.

## 3. Apply

```bash
chezmoi status               # expect: R .chezmoiscripts/<the installer for this OS>
chezmoi apply -v
```

The install scripts are `run_onchange_`, keyed on their **rendered** content. Adding a package changes the rendered script, so apply re-runs it — there is no separate install command and nothing to trigger by hand.

That `R` line is the check that the declaration landed, and it appears only on a real change. No `R` means the edit did not reach the script this machine runs: wrong manager for this OS, or a class bucket this machine is not in.

Done when the tool is on `PATH` and `chezmoi diff` is empty. If a script needs re-running without a content change:

```bash
chezmoi state delete-bucket --bucket=scriptState
```

That forces every `run_once_` and `run_onchange_` script to run again, not just the one you meant.

## 4. Remove a package

Deleting a name from an array stops it being installed on **new** machines and uninstalls it from none. Removal is its own declaration:

1. Delete the name from its `common` / `dev_computer` / `personal_computer` array.
2. Add it to `to_remove` under `[packages.homebrew]` or `[packages.apt]` — the top-level table, not a class bucket.
3. Apply. `run_onchange_after_10_remove_packages` uninstalls it where present.

`to_remove` is a converged state rather than a one-shot, so an entry stays honoured on every machine that applies later. Leave it in place until every machine has applied, then clear it.

## 5. Upgrade

- **Manager-owned** (arrays in `packages.toml`) — nothing here. `brew upgrade` and `apt upgrade` own it.
- **Pinned** (`versions.<tool>` in `packages.yaml`) — edit the version string. That is the whole upgrade: the pin is interpolated into the install script, so the rendered content changes and the `run_onchange_` script re-runs on every machine that applies. This is the only reason `packages.yaml` exists.
- **Language runtimes** — edit `dot_config/mise/config.toml.tmpl`. `run_onchange_after_30-mise-install` embeds a hash of that file, so editing it re-triggers `mise install`.

Then commit the source, or the upgrade reaches this machine alone — see the `chezmoi-sync` skill.
