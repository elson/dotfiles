---
name: chezmoi-sync
description: Move dotfile changes between machines through chezmoi's source repo. Use when pulling another machine's config changes, publishing this machine's, or working out why two machines have diverged.
---

# chezmoi sync

The source directory is a git repo, and it is the only thing that crosses machines. A change that is applied but uncommitted exists on one machine; a change that is committed but unapplied exists in no shell. Both halves have to happen.

`chezmoi git` runs git in the source directory from any working directory, so none of this needs a `cd`:

```bash
chezmoi git -- status
```

## Pull another machine's changes

```bash
chezmoi update -v
```

That is `git pull --autostash --rebase` in the source repo followed by an apply. Preview it in two moves when the machine has drifted or the pull is large:

```bash
chezmoi git -- pull --autostash --rebase
chezmoi diff                 # read this before writing anything
chezmoi apply -v
```

Apply rewrites every managed target, so an unread diff here is where another machine's change lands on this one unexamined. Where a local target has been hand-edited, apply asks before discarding it and fails rather than proceed when nothing can answer — never clear that by adding `--force` (the `chezmoi-dotfiles` skill covers the guard and its one blind spot).

## Publish this machine's changes

Start from a clean picture, because uncommitted work in the source repo is easy to miss:

```bash
chezmoi git -- status
chezmoi status
```

`chezmoi git -- status` shows source edits not yet committed. `chezmoi status` shows source and targets out of step, in two columns that answer different questions:

- **First column** — how the target has changed since chezmoi last wrote it. This is local drift: somebody edited the target in place.
- **Second column** — what `chezmoi apply` will do to it.

So `MM .zshrc` is a target edit that apply is about to destroy, while ` M .zshrc` is an unapplied source change and perfectly ordinary. Scan for a non-space **first** column and resolve those before anything else — that edit exists nowhere but the target, and has to move into the source to survive (the `chezmoi-dotfiles` skill covers absorbing one).

Then commit and push:

```bash
chezmoi git -- add -A
chezmoi git -- commit -m "..."
chezmoi git -- push
```

Done when `chezmoi git -- status` is clean and the branch is not ahead of its upstream.

## Diverged machines

Rebasing the source repo is ordinary git, with one wrinkle: a conflicted rebase leaves the source in a half-resolved state, and applying from there writes half-resolved files into the home directory. Finish the rebase, then `chezmoi diff`, then apply.

When a machine looks correct but behaves as though it is behind, check the two failure points in order:

```bash
chezmoi git -- log --oneline -5     # did the commit reach this machine?
chezmoi status                      # did the apply reach the targets?
```

The first catches an unpulled or unpushed commit. The second catches a pulled commit that was never applied.

## Machine-specific by design

A file that renders differently per machine is not divergence to fix. Templates branch on `chezmoi data` — hostname, OS, and any values the config file sets — so one committed source deliberately yields different targets. Confirm which you are looking at before reconciling anything:

```bash
chezmoi execute-template < <source-file>    # what this machine renders
chezmoi data                                # the values it branches on
```

Reconcile a genuine divergence in the source. Leave a deliberate branch alone.
