# mk-setup

Reusable development setup resources (dev container configuration and APM project files)
plus a helper script to copy them into any other project folder. Test change.

## Contents

| Resource | Description |
| --- | --- |
| `.devcontainer/` | Dev container definition (`devcontainer.json`, `devcontainer-lock.json`, `setup.sh`) |
| `apm.yml` | APM project manifest (targets, dependencies, includes) |
| `apm.lock.yaml` | Resolved APM dependency lock file |
| `mk-setup.sh` | Copies the resources above into a target folder |

## Usage

```bash
./mk-setup.sh [options] <target-folder>
```

The script resolves the resources relative to its own location, so it can be called
from anywhere using an absolute path:

```bash
/path/to/mk-setup/mk-setup.sh ~/projects/my-app
```

If the target folder does not exist, it is created.

### Options

| Option | Description |
| --- | --- |
| `-f`, `--force` | Overwrite resources that already exist in the target folder |
| `-n`, `--dry-run` | Print what would be copied without changing anything |
| `-h`, `--help` | Show usage information |

### Examples

Preview the copy without touching the file system:

```bash
./mk-setup.sh --dry-run ~/projects/my-app
```

Copy into a new project (existing entries are skipped):

```bash
./mk-setup.sh ~/projects/my-app
```

Refresh an existing setup, replacing the current files:

```bash
./mk-setup.sh --force ~/projects/my-app
```

### Behaviour notes

- Existing entries in the target folder are **skipped** unless `--force` is given.
- With `--force`, a resource is removed and re-copied, so stale files inside
  `.devcontainer/` are not left behind.
- The script refuses to run when the target folder is the source folder itself.
- A missing source resource produces a warning and is skipped; the remaining
  resources are still copied.
- The script exits with code `2` on invalid arguments and `1` when the target
  equals the source folder.

## Requirements

- `bash` (the script uses `#!/usr/bin/env bash` and bash-specific features)
- Standard POSIX tools: `cp`, `rm`, `mkdir`

Make the script executable once after cloning:

```bash
chmod +x mk-setup.sh
```
