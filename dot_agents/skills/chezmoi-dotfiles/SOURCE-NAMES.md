# Source names

A source filename is not decoration: it encodes the target's name, permissions and type. Renaming a source file changes what apply writes. Verified against chezmoi v2.72.0.

Read a name by stripping prefixes left to right, then the suffix.

| In the source name | Effect on the target |
| --- | --- |
| `dot_zshrc` | leading dot — `~/.zshrc` |
| `private_netrc` | mode 0600, or 0700 on a directory |
| `readonly_settings.conf` | mode 0444 |
| `executable_script.sh` | adds the execute bit |
| `symlink_aws` | target is a **symlink**, and the file's rendered contents are the link's destination |
| `exact_cfg/` | directory is exhaustive: apply **deletes** anything in the target directory that the source does not name |
| `create_seeded` | write once if the target is absent, then never touch it again — for files the app owns after seeding |
| `modify_hosts` | source is an executable that receives the current target on stdin and prints the new one |
| `remove_stale` | delete the target |
| `literal_dot_odd` | stop interpreting: the rest of the name is used verbatim, for a target genuinely called `dot_odd` |
| `encrypted_secret` | source is encrypted, decrypted at apply time |
| `*.tmpl` | rendered as a Go text/template; the suffix is dropped from the target name |

Prefixes stack in that order: `exact_private_dot_ssh/` is `~/.ssh`, mode 0700, exhaustive.

## Going between the two

```bash
chezmoi source-path ~/.ssh/config    # target  → source (exit 1 if unmanaged)
chezmoi target-path <source-file>    # source  → target
```

Derive neither by hand. `source-path` also answers whether the file is managed at all, which is the check that belongs before any edit.

## Scripts

Files under `.chezmoiscripts/` are not targets. They are named `run_<when>_<name>` and execute during apply:

- `run_` every apply, `run_once_` the first time this content is seen, `run_onchange_` whenever the **rendered** content changes.
- `_before_` / `_after_` place the script either side of the file phase; without one it runs between them.

A `run_onchange_` script re-runs on any rendered-content change, so editing a comment in one is enough to trigger it.
