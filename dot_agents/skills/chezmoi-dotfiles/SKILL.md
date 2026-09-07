---
name: chezmoi-dotfiles
description: Config files under the home directory are rendered by chezmoi from a source directory, so an edit made in place is saved nowhere and the next apply replaces it. Use before editing any dotfile or config file under the home directory, when a config change has reverted or vanished, or when putting a config file under version control.
---

# chezmoi dotfiles

chezmoi renders files from a **source** directory (`chezmoi source-path`, usually a git repo at `~/.local/share/chezmoi`) into **targets** under the home directory. The source is the writable copy: `chezmoi apply` rewrites every managed target from it, so an edit made directly to a target is saved nowhere — it reaches no other machine, and the next apply is waiting to replace it.

Work the steps in order. Step 1 is the one that prevents lost work.

## The prompt is the guard

chezmoi refuses, rather than destroys, when a command would discard work: applying over a target that changed since chezmoi last wrote it, or adding a file in a way that drops its template attribute. Each asks first, and with no TTY attached the question becomes a hard failure (`could not open a new TTY`) with the file untouched.

That failure is the answer, not an obstacle. **`--force` suppresses exactly these questions**, so reaching for it converts a refusal into the data loss the refusal existed to prevent. Pass it only when the user has said to discard that specific file; otherwise stop and report what chezmoi asked.

The guard is bounded, and knowing where it stops matters more than knowing it exists: it works from chezmoi's record of what it last wrote, so a machine with no such record — a fresh clone, a cleared state — overwrites existing targets without asking. On a machine in that state, `chezmoi diff` before the first apply is the only guard there is.

## 1. Establish whether the file is managed

Before editing any file under the home directory:

```bash
chezmoi source-path ~/.zshrc
```

**Exit 0** prints the source file: the target is managed, go to step 2. **Exit 1** prints `not managed`: chezmoi does not own it, edit it in place, and offer step 5.

Managed is per-file, so check the file you are about to touch rather than inferring from a sibling. `chezmoi managed` lists every managed target when you want the whole picture.

## 2. Edit the source, never the target

Apply your change to the path step 1 printed.

A source file ending in `.tmpl` is a Go template rendered at apply time, and the target is its output. Edit the template expression, not the rendered value you see in the target — and read [`SOURCE-NAMES.md`](SOURCE-NAMES.md), because the filename encodes the target's name and permissions.

To preview what a template renders to:

```bash
chezmoi execute-template < ~/.local/share/chezmoi/dot_gitconfig.tmpl
```

## 3. Preview, then apply

```bash
chezmoi diff                 # every pending change
chezmoi diff ~/.zshrc        # just this target
chezmoi apply -v ~/.zshrc    # write it out
```

Read the diff before applying. The step is done when `chezmoi status` is clean for the file you touched.

## 4. Commit the source

The source directory is a git repo, and an uncommitted change reaches no other machine. See the `chezmoi-sync` skill for the commit, push, and pull loop.

## 5. Put a new file under management

```bash
chezmoi add ~/.config/app/config.toml
chezmoi status                            # expect the file to appear as managed
```

chezmoi copies the target into the source and names it by the encoding in [`SOURCE-NAMES.md`](SOURCE-NAMES.md). Then commit (step 4).

## 6. Absorb an edit already made to a target

Someone edited a target in place and the change is worth keeping. `chezmoi status` marks it in the **first** column (`MM`), and the next apply destroys it, so recover it now.

Read the drift first:

```bash
chezmoi diff ~/.zshrc    # source (left) against the edited target (right)
```

Then move it into the source by hand: open the source file from step 1 and make the equivalent edit there. Hand-editing is the reliable route for every case, and the only correct one when the source is a `.tmpl`, because a target edit has to be re-expressed as a template expression and no command can do that for you.

Two commands look like shortcuts here and lose work instead:

- **`chezmoi re-add`** copies a modified target back into its source, but it **skips templates in silence** — no output, no error, no change. The edit then dies at the next apply, looking as though the command had worked.
- **`chezmoi add --force`** on a managed template **replaces the template with the rendered output**: `dot_gitconfig.tmpl` becomes `dot_gitconfig`, every `{{ ... }}` expression collapsed to the value it produced on this machine. Where a template pulls from a password manager, that writes a plaintext secret into a git repo. Plain `chezmoi add` asks first (`adding .zshrc would remove template attribute, continue?`) — see the guard above.

`chezmoi re-add` is safe on a non-template source, and that is its whole remit.
