---
name: chezmoi-packages
description: Installing a tool is a scope decision before it is an install command - software wanted on every personal machine is declared in chezmoi's dotfiles repo, while a tool a single project depends on belongs to that project's mise config. Use when installing or removing a tool, upgrading a pinned one, or explaining why a tool is present on one machine and missing on another.
---

# chezmoi packages

Two questions, in order. **Where does this tool belong?** — most of the damage is done by getting this one wrong. Then, only for the tools that belong here, **which mechanism installs it?**

Neither answer is `brew install` typed into a shell. That works exactly once, on one box, until it is rebuilt.

## 1. Decide the scope

- **Global** — software wanted on every personal machine: laptop, dev boxes, the lot. Editors, shells, `jq`, `ripgrep`, language runtimes used everywhere. These are declared in the dotfiles repo, and the rest of this skill is about them.
- **Project** — a tool or dependency of one codebase: its linter, its formatter, its build tooling, the runtime version that codebase pins. These belong to **that repo**, not here.

The test: *would you want this on a machine where you never open that project?* Yes is global. No is project.

When the answer is genuinely unclear, choose project. It is scoped to one repo, it travels with the code to anyone who checks it out, and promoting it to global later is a two-line edit. A wrongly-global tool installs itself on every machine you own and is the harder one to walk back.

Both can be true without conflict: `node` at a sane default globally, and a specific version pinned by a project that needs it. The project's pin wins inside the project — that is what the pin is for, not a conflict to reconcile.

### Project scope stops here

```bash
cd /path/to/project
mise use <tool>@<version>    # writes mise.toml (or the .mise.toml already there)
```

Commit that file to **the project's** repo. Nothing else in this skill applies — do not add it to `.chezmoidata/`.

**Never `mise use --global`.** It writes `~/.config/mise/config.toml`, which chezmoi renders from `dot_config/mise/config.toml.tmpl`, so the edit is saved nowhere and the next apply replaces it. Global runtimes are changed in the source template instead (step 5).

## 2. Pick the mechanism

For global tools only. Work down this list and stop at the first that fits — the choice decides which file you edit. Both data files live in the source directory (`chezmoi source-path`).

1. **In the distro archive or a Homebrew formula** — add the name to the arrays in `.chezmoidata/packages.toml`. Nothing else.
2. **Has an official apt repo** (docker, gh, tailscale, mise) — add the repo to `.chezmoiscripts/run_onchange_before_09-apt-repos.sh.tmpl` via `add_repo`, then list the package in the apt array like any other. apt then owns its upgrades, so it takes **no** pin.
3. **Release download only** (gron, herdr, rbw) — pin the version in `.chezmoidata/packages.yaml` and install it in a `run_onchange_after_2x` script, into `~/.local/bin` without sudo.
4. **Self-updating installer** (claude) — a `run_once_` script guarded by `command -v`. Nothing to pin, because the tool updates itself.

`packages.toml` holds everything a package manager installs (`packages.homebrew.*` on darwin, `packages.apt.*` on Debian-likes). `packages.yaml` holds `versions.<tool>` and **only** for mechanism 3: a pin there is a claim that nothing else upgrades the tool, so adding one for an apt- or brew-managed package creates two things that both believe they control the version.

## 3. Choose the machine class

Each manager's packages are split into three buckets, and a machine installs `common` plus whichever classes it is:

```bash
chezmoi data | jq '{dev_computer, personal_computer}'
```

`common` is the default; reach for a class only when the package genuinely does not belong everywhere. Two constraints are not preferences:

- **GUI apps are darwin-only.** The Linux boxes are headless, so a cask has no apt counterpart to add.
- **The two managers disagree on names** (`gpg` / `gnupg`, `pygments` / `python3-pygments`). Confirm the name each manager actually uses rather than copying across; some Homebrew formulae have no apt package at all, in which case mechanism 3 covers Linux.

Homebrew arrays are `formulae` and `casks`; apt has a single `packages`.

## 4. Apply

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

## 5. Remove a package

Deleting a name from an array stops it being installed on **new** machines and uninstalls it from none. Removal is its own declaration:

1. Delete the name from its `common` / `dev_computer` / `personal_computer` array.
2. Add it to `to_remove` under `[packages.homebrew]` or `[packages.apt]` — the top-level table, not a class bucket.
3. Apply. `run_onchange_after_10_remove_packages` uninstalls it where present.

`to_remove` is a converged state rather than a one-shot, so an entry stays honoured on every machine that applies later. Leave it in place until every machine has applied, then clear it.

## 6. Upgrade

- **Manager-owned** (arrays in `packages.toml`) — nothing here. `brew upgrade` and `apt upgrade` own it.
- **Pinned** (`versions.<tool>` in `packages.yaml`) — edit the version string. That is the whole upgrade: the pin is interpolated into the install script, so the rendered content changes and the `run_onchange_` script re-runs on every machine that applies. This is the only reason `packages.yaml` exists.
- **Global runtimes** — edit `dot_config/mise/config.toml.tmpl` in the source directory. `run_onchange_after_30-mise-install` embeds a hash of that file, so editing it re-triggers `mise install`.

Then commit the source, or the upgrade reaches this machine alone — see the `chezmoi-sync` skill.
