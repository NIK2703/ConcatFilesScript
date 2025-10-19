# `concat_files.sh` — File Concatenator

Recursively bundles project files into clean, readable text files — perfect for LLM context, code snapshots, or archiving.

## ✅ Features

- Respects `.gitignore` and custom `--ignore` rules  
- Optional line numbering and file headers  
- Splits output into parts if size limit exceeded  
- `--uncommitted-changes` — concatenate only files modified since last commit (including unstaged)  
- Output saved in `_concat/`

## 🚀 Quick Start

```sh
chmod +x concat_files.sh

# Bundle all tracked files (respect .gitignore)
./concat_files.sh --gitignore

# Bundle only changed files (since last commit)
./concat_files.sh --uncommitted-changes

# For LLM context: 100KB chunks, line numbers, ignore build artifacts
./concat_files.sh --gitignore --ignore build dist node_modules --line-numbers --max-size 102400
```

## 📋 Usage

```text
./concat_files.sh [OPTIONS]

Options:
  --ignore PATTERN...     Ignore files/dirs by name (e.g. build, *.log)
  --gitignore             Respect .gitignore
  --uncommitted-changes   Include only files changed since last commit
  --line-numbers          Add line numbers to content
  --max-size N            Split output into N-byte chunks
  --max-input-size N      Skip source files larger than N bytes
  --help                  Show help
```

## 📁 Output

- `_concat/<project>.txt` (single file)  
- `_concat/<project>_part1.txt`, `_concat/<project>_part2.txt`, … (if split)

Each file block starts with:
```text
### FILE: ./src/main.cpp
1: #include <iostream>
2: ...
```
