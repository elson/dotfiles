# Environment Variable Management

mise can manage per-project environment variables, replacing direnv.

## Setting environment variables

### In mise.toml

```toml
# mise.toml
[env]
NODE_ENV = "development"
DATABASE_URL = "postgres://localhost:5432/mydb"
API_KEY = "sk-xxx"
```

### From .env files

```toml
# mise.toml
[env]
_.file = ".env"                    # load from .env file
_.file = [".env", ".env.local"]    # load multiple, later files override
```

### Path manipulation

```toml
[env]
_.path = ["./bin", "./node_modules/.bin"]  # prepend to PATH
```

### Conditional / computed values

```toml
[env]
# reference other env vars
PROJECT_ROOT = "{{cwd}}"
LOG_DIR = "{{env.PROJECT_ROOT}}/logs"
```

### Environment-specific config

Create environment-specific config files that layer on top of the base config:

```
mise.toml                  # base config (always loaded)
mise.development.toml      # loaded when MISE_ENV=development
mise.production.toml       # loaded when MISE_ENV=production
mise.local.toml            # local overrides (git-ignored)
```

Activate with:
```bash
MISE_ENV=development mise ...
# or
mise -E development ...
```

## Useful commands

```bash
mise env                   # show all env vars that mise would set
mise env --json            # show as JSON
mise set KEY=VALUE         # set an env var in mise.toml
# mise set -g KEY=VALUE    # NOT on this machine: ~/.config/mise/config.toml is chezmoi-managed
mise unset KEY             # remove an env var from mise.toml
mise config ls             # see which config files are loaded
```

## Security

- mise requires `mise trust` on new config files before loading env vars from them
- `mise.local.toml` should be git-ignored (may contain secrets)
- Use `.env` files for secrets and add them to `.gitignore`
- Use `MISE_TRUSTED_CONFIG_PATHS` to auto-trust specific directories

## Best practices

1. **Commit `mise.toml`** with non-secret env vars so the team shares the same config.
2. **Git-ignore `mise.local.toml` and `.env`** for secrets and personal overrides.
3. **Use `_.file = ".env"`** to load secrets from a dotenv file rather than putting them directly in mise.toml.
4. **Use environment-specific configs** (`mise.development.toml`, etc.) instead of complex conditional logic.
