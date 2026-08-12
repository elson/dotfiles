# dotfiles

Personal dotfiles managed with [chezmoi](https://www.chezmoi.io). One command takes a
fresh machine from nothing to a configured shell, package set, and secrets — on macOS
and on Debian-likes (Debian, Ubuntu, Proxmox).

- **Two OS families, one source tree.** Homebrew on darwin, apt plus vendor repos on
  Debian-likes. Every OS-specific script simply renders empty on the other platform.
- **Machine classes, not hostnames.** Three booleans answered once (`personal_computer`,
  `dev_computer`, `use_secrets`) decide which package sets and files apply. A headless
  homelab box and a daily driver run the same repo.
- **Secrets stay in Bitwarden.** Nothing encrypted is committed here; templates pull
  fields from the vault at apply time.
- **Templates, not symlink farms.** Files are rendered into `$HOME`; the source of truth
  is always this repo.

## Prerequisites

**Both platforms** — internet access, and a Bitwarden account if you answer `true` to
`use_secrets` (answer `false` to skip every secret-backed file cleanly).

**macOS** — nothing else. Xcode Command Line Tools and Homebrew are installed for you.

**Debian-likes** — `curl` and `sudo` rights. The apt and vendor-repo scripts need root;
everything installed from a release download goes to `~/.local/bin` without sudo.

## Bootstrap

Install chezmoi, clone this repo, and apply it in one shot.

**macOS**

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply elson
```

**Debian / Ubuntu / Proxmox**

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin init --apply elson
```

`-b ~/.local/bin` keeps chezmoi itself out of `/usr/local`; that directory is added to
`PATH` by the shell config this repo installs.

One apply is enough. Prerequisites that everything else depends on — Xcode CLT and
Homebrew on macOS, `curl`/`git`/`gnupg`/`unzip` on Debian, and the Bitwarden CLI on both —
are installed by [`.install-prerequisites.sh`](.install-prerequisites.sh), which chezmoi
runs as a `read-source-state.pre` hook *before* it reads this repo. So Homebrew exists by
the time the package scripts run, and `bw` exists by the time a `bitwardenFields` template
is rendered.

You will be prompted for your Bitwarden master password partway through the first apply.

### Setup prompts

Asked once on `chezmoi init`, then stored in `~/.config/chezmoi/chezmoi.toml` and never
asked again:

| Prompt | Data key | What it gates |
|---|---|---|
| Use secrets from Bitwarden? | `use_secrets` | The Bitwarden unlock script, `~/.config/aws/credentials`, `~/.config/shell/private.sh`, and the `bw` installer on Linux. `false` makes those targets disappear via `.chezmoiignore`. |
| Is this a personal computer for daily driving? | `personal_computer` | GUI apps — browsers, Slack, Obsidian, Docker Desktop, Tailscale (darwin only; the Linux boxes are headless). |
| Do you do development on this computer? | `dev_computer` | mise, terraform, tflint, ansible, gh, Claude Code, and the `mise install` run. |
| Email address | `email` | Git identity and the Bitwarden login. |

To change an answer later, edit `~/.config/chezmoi/chezmoi.toml` directly or re-run
`chezmoi init` after deleting the relevant line.

### What bootstrap actually does

In execution order, not filename order — the hook runs first, then `before_` scripts, then
the file phase, then `after_` scripts:

0. **`.install-prerequisites.sh`** — Xcode CLT + Homebrew (macOS), `curl`/`git`/`gnupg`/
   `unzip` (Debian), and the Bitwarden CLI. Runs before chezmoi even reads the repo.
1. **`before_09-apt-repos`** *(Debian)* — adds the mise, HashiCorp, GitHub CLI, Docker,
   and Tailscale apt repos, skipping any that don't publish for the box's codename.
2. **`before_10-homebrew-packages`** *(darwin)* / **`before_11-apt-packages`** *(Debian)* —
   installs the enabled machine classes' packages.
3. **`10-bitwarden-session`** — logs in and unlocks the vault, writing `BW_SESSION` to
   `~/.zshrc_bitwarden_session`. Skipped entirely unless `use_secrets`.
4. **files applied** — templates rendered into `$HOME`.
5. **`after_10_remove_packages`**, **`after_20-release-tools`** (gron, tflint),
   **`after_21-bitwarden-cli`**, **`after_22-claude-code`**, **`after_30-mise-install`**.

## What's managed

| Target | Notes |
|---|---|
| `~/.zshrc`, `~/.config/shell/{aliases,exports,private}.sh` | zsh plus antigen, downloaded as an external |
| `~/.config/git/config` | identity from the `email` prompt |
| `~/.config/ghostty/config` | terminal, darwin |
| `~/.config/mise/config.toml` | dev machines; editing it re-triggers `mise install` |
| `~/.config/aws/`, `~/.aws` → symlink | `credentials` rendered from Bitwarden |
| `~/.ssh/config`, `~/.ssh/keys/*.pub` | homelab hosts; public keys only |
| `~/.agents/skills/`, `~/.claude/skills` → symlink | agent skills; `~/.agents/skills` is the source of truth |

## Packages

Package lists live in [`.chezmoidata/packages.toml`](.chezmoidata/packages.toml), split by
machine class. Three install mechanisms, deliberately kept in separate scripts so a
failure in one can't block the others:

| Situation | Mechanism |
|---|---|
| In the Debian archive / a Homebrew formula | add to the `packages.apt.*` or `packages.homebrew.*` array |
| Has an official apt repo (docker, gh, tailscale, mise, terraform) | add the repo to `before_09-apt-repos`, then list the package in the apt array — apt then owns upgrades |
| Release download only (gron, tflint, bw) | pin the version in [`.chezmoidata/packages.yaml`](.chezmoidata/packages.yaml) and install it in an `after_2x` script; bumping the pin is what re-runs it |
| Self-updating installer (claude) | `run_once_`, guarded by `command -v` |

Not managed on purpose: **chezmoi** (installed by the bootstrap command above, before this
repo exists) and **awscli** (use the official installer where it's needed).

## Day-to-day

```sh
chezmoi diff                 # preview what apply would change
chezmoi apply -v             # render templates + run scripts into $HOME
chezmoi edit ~/.zshrc        # edit the source file behind a target
chezmoi status               # what's out of sync
chezmoi update               # git pull + apply
chezmoi cd                   # shell into the source directory
reload                       # alias: bw sync && chezmoi apply && exec zsh
```

Edit files **here**, never in `$HOME` — `chezmoi apply` overwrites the target.

## Secrets

No encrypted blobs are committed. Item UUIDs live in
[`.chezmoidata/bitwarden.toml`](.chezmoidata/bitwarden.toml), and templates pull fields at
apply time:

```
{{ (bitwardenFields "item" .bitwarden.items.<name>).<field>.value }}
```

To add a secret: put the item's UUID in `bitwarden.toml`, then reference it from a
`private_` template. The vault must be unlocked — run `bw unlock` before `chezmoi apply`
if you hit a prompt mid-apply.

## Post-bootstrap

- `gh auth login` on dev machines.
- macOS: enable the Bitwarden desktop app's SSH agent — `exports.sh` already points
  `SSH_AUTH_SOCK` at it.
- Linux: `sudo tailscale up` to join the tailnet, and `sudo usermod -aG docker "$USER"`
  if you want Docker without sudo.

## Troubleshooting

**Packages didn't install on a fresh machine.** The prerequisites hook warns to stderr and
never fails the command, so a Homebrew or apt failure leaves the package scripts with
nothing to work with. Scroll back for a `⚠️  install-prerequisites:` line, fix the cause,
then re-run `chezmoi apply -v`.

**Every chezmoi command feels slow, or the hook misbehaves.** `.install-prerequisites.sh`
runs on every source-state read. Test it in isolation with `./.install-prerequisites.sh`
from the source directory — it should be a sub-second no-op once everything is installed.

**Existing machine doesn't run the hook.** Hooks live in the generated
`~/.config/chezmoi/chezmoi.toml`. Re-run `chezmoi init` to regenerate it; your saved
prompt answers are not re-asked.

**`chezmoi diff` prompts for a master password, or fails rendering
`.config/aws/credentials`.** The vault is locked. Run `bw unlock`, or re-init with
`use_secrets = false`.

**A `run_once_`/`run_onchange_` script won't re-run.** chezmoi remembers it. Force it with:

```sh
chezmoi state delete-bucket --bucket=scriptState
```

**A vendor apt repo was skipped.** `before_09-apt-repos` checks each repo's
`dists/<codename>/Release` before adding it and skips ones that don't publish for the
box's release, rather than leaving `apt-get update` broken. Upgrade the box's codename or
install that tool another way.

**Editing a data file didn't re-trigger its script.** `run_onchange_` scripts key off
their *rendered* content. If the script doesn't interpolate the data it depends on, embed
a hash — `30-mise-install` does this with
`{{ include "dot_config/mise/config.toml.tmpl" | sha256sum }}`.

Repo internals and conventions are documented in [CLAUDE.md](CLAUDE.md).
