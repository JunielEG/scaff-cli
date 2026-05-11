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

| Command               | Description                                               |
| --------------------- | --------------------------------------------------------- |
| `scaffx tree`         | Shows a visual tree of the current directory              |
| `scaffx tree <depth>` | Limits the tree depth (e.g. `scaffx tree 2`)              |
| `scaffx snapshot`     | Generates `<root>.yaml` with the current folder structure |

---

## Flags

Flags can be combined with any command that supports them.

| Flag           | Description                                                                                | Works with         |
| -------------- | ------------------------------------------------------------------------------------------ | ------------------ |
| `--files-only` | Include only files                                                                         | `tree`, `snapshot` |
| `--dirs-only`  | Include only directories                                                                   | `tree`, `snapshot` |
| `--clean`      | Skip entries matched by `.gitignore` or [`scaffx.ignore`](./templates/files/scaffx.ignore) | `tree`, `snapshot` |

> `--files-only` and `--dirs-only` cannot be used together.

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
root:
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
