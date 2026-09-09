---
name: chezmoi-packages
description: Installing a tool is a scope decision before it is an install command - software wanted on every personal machine is declared in chezmoi's dotfiles repo, while a tool a single project depends on belongs to that project's mise config. Use when installing or removing a tool, upgrading a pinned one, or explaining why a tool is present on one machine and missing, or at a different version, on another.
---

# chezmoi packages

Two questions, in order. **Where does this tool belong?** — most of the damage is done by getting this one wrong. Then, only for the tools that belong here, **which mechanism installs it?**

Neither answer is `brew install` typed into a shell. That works exactly once, on one box, until it is rebuilt.

## 1. Decide the scope

- **Global** — software wanted on every personal machine: laptop, dev boxes, the lot. Editors, shells, `jq`, `ripgrep`, language runtimes used everywhere. These are declared in the dotfiles repo, and the rest of this skill is about them.
- **Project** — anything one codebase needs to build, test or run: its toolchain, its linter, its libraries. These belong to **that repo**, not here, and they split into two layers of their own.

The test: *would you want this on a machine where you never open that project?* Yes is global. No is project.

When the answer is genuinely unclear, choose project. It is scoped to one repo, it travels with the code to anyone who checks it out, and promoting it to global later is a two-line edit. A wrongly-global tool installs itself on every machine you own and is the harder one to walk back.

Both can be true without conflict: `node` at a sane default globally, and a specific version pinned by a project that needs it. The project's pin wins inside the project — that is what the pin is for, not a conflict to reconcile.

### Project scope: two layers

A project provisions itself in two layers, each owned by the one above it:

- **Toolchain** — the interpreters, compilers and CLIs the project builds *with*: node, python, java, rust, terraform. Declared in the project's `mise.toml`, installed by mise.
- **Dependencies** — the libraries the application imports. Declared in the manifest the toolchain already owns (`package.json`, `pyproject.toml`, `Cargo.toml`) and installed by that toolchain's own package manager.

The line between them: a **toolchain** has to be on `PATH` before the project's package manager can run at all; a **dependency** is something that package manager installs. Do not promote a dependency into `mise.toml` to make it available — that puts the toolchain layer to work doing the dependency layer's job, and it breaks for anyone who builds the project without mise.

```bash
cd /path/to/project
mise use <tool>@<version>    # toolchain → mise.toml (or the .mise.toml already there)
npm install <pkg>            # dependency → whatever manager the project already uses
```

Commit those files to **the project's** repo. Nothing else in this skill applies — neither goes in `.chezmoidata/`. The `mise-guide` skill covers mise itself in depth: tool versions, the `[env]` section, and the `[tasks]` runner.

The split exists so that `git clone` is the only bespoke step: mise provisions the toolchain, the toolchain provisions the dependencies, and the project builds and tests with no environment configuration on top. That is also **why `mise` is in the global set** — it is the one globally-installed thing that makes every other repo self-provisioning, so bootstrapping it onto every machine is what buys the rest.

### After a clone, "automatic" is two commands

mise installs nothing on `cd` alone, and a config it has never seen is untrusted:

```bash
mise trust      # a freshly cloned mise.toml is untrusted
mise install    # materialise the toolchain it declares
```

Skip either and it fails quietly rather than loudly: `cd` in, and the tool resolves to the machine's **system** copy at whatever version that happens to be — `/usr/bin/jq` where the project asked for `jq@1.7.1` — with no warning under the default `status.missing_tools`. A project that builds on one machine and not another is usually this.

**Never `mise use --global`.** It writes `~/.config/mise/config.toml`, which chezmoi renders from `dot_config/mise/config.toml.tmpl`, so the edit is saved nowhere and the next apply replaces it. Global runtimes are changed in the source template instead (step 6).

## 2. Pick the mechanism

For global tools only. Work down this list and stop at the first that fits — the choice decides which file you edit. Both data files live in the source directory (`chezmoi source-path`).

1. **In the distro archive or a Homebrew formula** — add the name to the arrays in `.chezmoidata/packages.toml`. Nothing else.
2. **Has an official apt repo** (docker, gh, tailscale, mise) — add the repo to `.chezmoiscripts/run_onchange_before_09-apt-repos.sh.tmpl` via `add_repo`, then list the package in the apt array like any other. apt then owns its upgrades, so it takes **no** pin.
3. **A mise backend has it** (gron, herdr) — add it to `[tools]` in `dot_config/mise/config.toml.tmpl`. Cross-platform in one declaration, which is why these two moved off mechanism 4. Pin an exact version, not `latest` — see step 6.
4. **Release download only** (rbw) — pin the version in `.chezmoidata/packages.yaml` and install it in a `run_onchange_after_2x` script, into `~/.local/bin` without sudo.
5. **Self-updating installer** (claude) — a `run_once_` script guarded by `command -v`. Nothing to pin, because the tool updates itself.

`packages.toml` holds everything a package manager installs (`packages.homebrew.*` on darwin, `packages.apt.*` on Debian-likes). `packages.yaml` holds `versions.<tool>` and **only** for mechanism 4: a pin there is a claim that nothing else upgrades the tool, so adding one for an apt- or brew-managed package creates two things that both believe they control the version.

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
- **Global mise tools** — edit `dot_config/mise/config.toml.tmpl` in the source directory. `run_onchange_after_30-mise-install` embeds a hash of that file, so editing it re-triggers `mise install`. That works for an **exact** version and only for an exact version, per the trap below.

### A floating mise version drifts per machine

`latest`, `lts` and `3` are resolved **once**, when the tool is first installed, and then frozen — `installs/herdr/latest` is a symlink to whatever was current that day. `mise install` only fills gaps, so it never re-resolves one that is already satisfied, and the apply script's hash never changes because the version string never changes. Two machines that first installed a tool months apart therefore sit on different versions indefinitely, with `chezmoi diff` clean on both:

```bash
mise ls <tool>              # what this machine froze
mise latest <tool>          # what the string resolves to today
mise upgrade <tool>         # re-resolve it, this machine only
```

`mise upgrade` is a per-machine repair, not a fix — the next machine drifts the same way. Converge them by pinning an exact version in the template: the rendered content then changes, the `run_onchange_` fires everywhere, and every machine lands on the same version. Keep a floating string only where the drift is the point (the `dev_computer` language runtimes deliberately track `lts` / a major).

Then commit the source, or the upgrade reaches this machine alone — see the `chezmoi-sync` skill.
