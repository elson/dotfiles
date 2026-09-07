# Tool Version Management

## Workflow

### 1. Check current state

Before making changes, understand what's already in place:

```bash
mise ls                    # list installed tools and active versions
mise config ls             # list loaded config files and their precedence
mise current               # show currently active tool versions
```

### 2. Search and discover tools

```bash
mise search <query>        # search available tools by name
mise ls-remote <tool>      # list all available versions for a tool
mise latest <tool>         # show latest stable version
mise outdated              # check which installed tools have newer versions
```

### 3. Install and pin tools

**Project-level** (writes to `./mise.toml` in current directory):
```bash
mise use node@22           # install and pin node 22 (latest 22.x)
mise use python@3.12       # install and pin python 3.12
mise use node@22 go@1.22   # install multiple tools at once
```

**Global** — not on this machine. `~/.config/mise/config.toml` is a chezmoi target rendered from `dot_config/mise/config.toml.tmpl`, so `mise use -g` writes a file the next `chezmoi apply` overwrites. Edit that source template and apply; the `chezmoi-packages` skill covers the global-versus-project decision.

### 4. Version specifiers

| Specifier | Meaning | Example |
|---|---|---|
| `22` | Latest matching major | `node@22` → 22.x.x |
| `22.1` | Latest matching minor | `node@22.1` → 22.1.x |
| `22.1.0` | Exact version | `node@22.1.0` |
| `latest` | Latest stable | `node@latest` |
| `lts` | Latest LTS | `node@lts` |
| `prefix:1.19` | Latest with prefix | `go@prefix:1.19` |
| `sub-1:lts` | One version behind LTS | `node@sub-1:lts` |

### 5. Multiple versions

Python example — install two versions, first one is the default:
```toml
# mise.toml
[tools]
python = ["3.12", "3.11"]
```

### 6. Other useful commands

```bash
mise install               # install all tools from config (no pinning)
mise install node@22       # install specific version without pinning
mise uninstall node@22     # remove an installed version
mise unuse node            # remove tool from current config
mise upgrade               # upgrade tools to latest compatible versions
mise prune                 # remove unused tool versions to free space
mise which node            # show path to the active node binary
mise where node@22         # show installation directory
mise exec node@20 -- node -v  # run command with specific version (no config change)
mise shell node@20         # activate version for current shell session only
mise reshim                # rebuild shim binaries (if using shims)
```

### 7. Config file format

```toml
# mise.toml
[tools]
node = "22"
python = "3.12"
go = "1.22"
ruby = "3.3"

# with options
node = { version = "22", postinstall = "corepack enable" }

# from package managers
"npm:typescript" = "latest"
"npm:@anthropic-ai/claude-code" = "latest"
```

### 8. Package backends

Install tools from different ecosystems:

```bash
mise use "npm:typescript"              # from npm
mise use "pipx:black"                  # from pip
mise use "github:BurntSushi/ripgrep"   # from GitHub releases
```

## Language-specific notes

### Node.js
- Reads `.nvmrc` / `.node-version` files (when enabled via `mise settings add idiomatic_version_file_enable_tools node`)
- Default npm packages: add to `~/.default-npm-packages` (one per line)
- Enable corepack: `node = { version = "22", postinstall = "corepack enable" }`

### Python
- Downloads precompiled binaries by default (fast install)
- Virtual environment support in config:
  ```toml
  [tools.python]
  version = "3.12"

  [tools.python.virtualenv]
  path = ".venv"
  create = true
  ```
- Uses uv for venv creation if available
- Compile from source: `mise settings python.compile=1`
- Default packages: `~/.default-python-packages`

### Go
- For Go ≤1.20, use prefix syntax: `go@prefix:1.20`
- Default packages: `~/.default-go-packages`
- Reads `.go-version` files

## Troubleshooting

```bash
mise doctor                # diagnose setup issues
mise config ls             # check config file precedence
mise settings ls           # show all settings
mise self-update           # update mise itself
```
