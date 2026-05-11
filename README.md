# scaffx — File Structure CLI

`scaffx` is a command-line tool for inspecting and documenting project file structures. Generate visual trees, export YAML snapshots, and filter output — all from any terminal.

---

## Requirements

- **PowerShell 5.1+** — included by default on Windows 10/11

---

## Installation

> [!NOTE]
> You only need the install script — cloning the repository is just the easiest way to get it.

**1. Clone the repository:**

```bash
git clone https://github.com/JunielEG/scaff-cli.git
cd scaff-cli
```

**2. Run the install script for your platform:**

**Windows** — run `install.bat` directly or add the folder to your PATH:

```bat
install.bat
```

**Linux / macOS** — _coming soon_

**3. Open a new terminal** and verify:

```bash
scaffx
```

---

## Commands

| Command                 | Description                                                          |
| ----------------------- | -------------------------------------------------------------------- |
| `scaffx tree`           | Shows a visual tree of the current directory                         |
| `scaffx tree <depth>`   | Limits the tree depth (e.g. `scaffx tree 2`)                         |
| `scaffx snapshot`       | Generates `<root>.yaml` with the current folder structure            |
| `scaffx count`          | Shows the number of items in the current directory                   |
| `scaffx size`           | Shows the total disk size of the current directory                   |
| `scaffx find <pattern>` | Searches the tree by name — use quotes for wildcards (e.g. `*.json`) |
| `scaffx diff`           | Compares the current structure against an existing `.yaml` snapshot  |
| `scaffx watch`          | Monitors the directory for changes in real time (Ctrl+C to stop)     |
| `scaffx ignore`         | Shows which files/folders are currently being ignored                |

---

## Flags

Flags can be combined with any command that supports them.

| Flag           | Description                                                                                | Works with                          |
| -------------- | ------------------------------------------------------------------------------------------ | ----------------------------------- |
| `--files-only` | Include only files                                                                         | `tree`, `snapshot`, `count`, `find` |
| `--dirs-only`  | Include only directories                                                                   | `tree`, `snapshot`, `find`          |
| `--clean`      | Skip entries matched by `.gitignore` or [`scaffx.ignore`](./templates/files/scaffx.ignore) | `tree`, `snapshot`                  |

> `--files-only` and `--dirs-only` cannot be used together.
> Incompatible flag combinations will produce an error instead of silently misbehaving.

---

## What each command does

### `scaffx tree`

Prints a visual representation of the current directory structure.

```bash
scaffx tree
scaffx tree 2
scaffx tree --clean
scaffx tree 2 --files-only
```

```
  my-project
  ----------------------------------------
  ├── src/
  │   ├── main.cpp
  │   └── utils.cpp
  ├── include/
  │   └── utils.h
  └── CMakeLists.txt
```

If the directory exceeds 200 items, scaffx will ask for confirmation before proceeding.

---

### `scaffx snapshot`

Exports the current directory structure to a `<root>.yaml` file in the same directory.

```bash
scaffx snapshot
scaffx snapshot --clean
scaffx snapshot --dirs-only
```

```yaml
my-project:
  - src:
      - main.cpp
      - utils.cpp
  - include:
      - utils.h
  - CMakeLists.txt
```

The output file is named after the root folder (e.g. `my-project.yaml`) and is automatically excluded from its own output.

---

### `--clean`

When this flag is used, scaffx looks for an ignore file to filter out noise:

1. Looks for `.gitignore` in the current directory
2. If not found, falls back to the built-in [`scaffx.ignore`](./templates/files/scaffx.ignore)

```bash
scaffx tree --clean           # uses .gitignore if present, else scaffx.ignore
scaffx snapshot --clean       # same resolution logic
```

The header shows which source is active:

```
tree  ->  my-project  --clean (.gitignore)
tree  ->  my-project  --clean (scaffx.ignore)
```

[`scaffx.ignore`](./templates/files/scaffx.ignore) covers common noise across OS, editors, dependencies, build artifacts, and more — so it works out of the box on any project type.

---

### `scaffx count`

Counts the total number of items in the current directory recursively.

```bash
scaffx count
scaffx count --files-only
```

---

### `scaffx size`

Shows the total disk size of all files in the current directory recursively. Automatically formats the output as B, KB, MB, or GB.

```bash
scaffx size
```

If the directory exceeds 200 files, scaffx will ask for confirmation before proceeding.

---

### `scaffx find <pattern>`

Searches the directory tree by name and displays results using the same visual format as `tree`.

```bash
scaffx find *.json
scaffx find README*
scaffx find CMakeLists.txt --files-only
```

---

### `scaffx diff`

Compares the current directory structure against an existing `<root>.yaml` snapshot. Shows added (`+`) and removed (`-`) entries since the snapshot was taken.

```bash
scaffx diff
```

Requires a snapshot to exist in the current directory — run `scaffx snapshot` first.

---

### `scaffx watch`

Monitors the current directory for file system changes in real time. Prints a timestamped line for every creation, deletion, or rename. Press `Ctrl+C` to stop.

```bash
scaffx watch
```

---

### `scaffx ignore`

Shows which files and folders in the current directory are being filtered by the active ignore file (`.gitignore` or `scaffx.ignore`). Useful for verifying ignore patterns before running `tree` or `snapshot --clean`.

```bash
scaffx ignore
```

If patterns are defined but nothing matches, the active pattern list is shown to help debug incorrect entries.

---

## Quick start

```bash
cd my-project
scaffx tree
scaffx tree 2 --clean
scaffx snapshot --clean
```

---

## Installed file location

| Platform      | Path                                        |
| ------------- | ------------------------------------------- |
| Windows       | `%USERPROFILE%\ScaffoldingTools\scaff-cli\` |
| Linux / macOS | _coming soon_                               |
