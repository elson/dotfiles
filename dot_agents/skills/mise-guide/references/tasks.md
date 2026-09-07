# Task Runner

mise includes a built-in task runner that can replace make, npm scripts, and similar tools.

## Defining tasks

### Inline in mise.toml

```toml
# mise.toml
[tasks.build]
run = "npm run build"
description = "Build the project"

[tasks.test]
run = "npm test"
description = "Run tests"

[tasks.lint]
run = ["eslint .", "prettier --check ."]  # multiple commands run sequentially
description = "Lint and format check"

# with dependencies — dev runs build first, then starts dev server
[tasks.dev]
run = "npm run dev"
depends = ["build"]
description = "Start dev server"
```

### Task options

```toml
[tasks.deploy]
run = "deploy.sh"
description = "Deploy to production"
depends = ["build", "test"]       # run these first
env = { NODE_ENV = "production" } # task-specific env vars
dir = "{{cwd}}"                   # working directory
sources = ["src/**/*"]            # file watch sources
outputs = ["dist/**/*"]           # outputs for caching
hide = false                      # show in task list
raw = false                       # true = attach stdin/stdout directly
```

### File-based tasks

Create executable scripts in a tasks directory:

```
mise-tasks/
├── build       # #!/usr/bin/env bash
├── test        # #!/usr/bin/env python
└── lint        # #!/usr/bin/env node
```

File-based tasks support frontmatter for metadata:

```bash
#!/usr/bin/env bash
#MISE description="Build the project"
#MISE depends=["lint"]
#MISE sources=["src/**/*"]
#MISE outputs=["dist/**/*"]

set -euo pipefail
npm run build
```

The default directory for file-based tasks is `mise-tasks/`, but you can configure it:

```toml
# mise.toml
[task_config]
dir = ["tasks", "scripts"]  # look for file-based tasks here
```

## Running tasks

```bash
mise run build              # run the "build" task
mise run build test         # run multiple tasks
mise run build -- --watch   # pass arguments to the task
mise run test --force       # force run even if sources unchanged
mise tasks ls               # list all available tasks
mise tasks info build       # show details about a task
```

Shorthand — if mise is set up with shell completions, you can also run:
```bash
mise build                  # shorthand for mise run build
```

## Watching for changes

```bash
mise watch -t build         # re-run "build" when source files change
mise watch -t test -t lint  # watch multiple tasks
```

This uses the `sources` field to know which files to watch.

## Task arguments and positional parameters

```toml
[tasks.greet]
run = 'echo "Hello, {{arg(name="person", default="world")}}"'

[tasks.serve]
run = "python -m http.server {{arg(i=0, name='port', default='8080')}}"
```

Usage:
```bash
mise run greet --person Alice    # Hello, Alice
mise run serve 3000              # python -m http.server 3000
```

## Best practices

1. **Use `depends`** to express task ordering instead of chaining commands with `&&`.
2. **Use `sources` and `outputs`** for build-like tasks — mise will skip re-running if outputs are newer than sources.
3. **Use file-based tasks** for complex scripts that are hard to express as one-liners in TOML.
4. **Use `description`** on every task so `mise tasks ls` is self-documenting.
5. **Use `raw = true`** for interactive tasks that need stdin (e.g., prompts, REPL).
