# `concat_files.sh` — Smart Recursive File Concatenator

A POSIX-compliant shell script to recursively concatenate files from your project into one or more output files, with powerful filtering, size control, and intelligent naming.

Perfect for code archiving, context bundling for LLMs, or creating unified source snapshots.

---

## ✨ Features

- **Recursive file collection** from all subdirectories  
- **Smart output splitting**:  
  - Single file if everything fits  
  - Multiple parts if size limit is exceeded (`--max-size`)  
- **Flexible ignore rules**:  
  - `--ignore pattern` (supports wildcards like `*.log`, `build`)  
  - `--gitignore` to automatically respect your `.gitignore`  
- **Content enrichment**:  
  - Optional line numbering (`--line-numbers`)  
  - File path header before each file (`### FILE: ./path/to/file`)  
- **Size control**:  
  - Skip large source files (`--max-input-size`)  
  - Limit output file size (`--max-size`)  
- **Clean output**:  
  - Results saved in `_concat/` (auto-created, always excluded from input)  
  - Intelligent naming: `project.txt` or `project_part1.txt`, `project_part2.txt`, …  
- **Portable**:  
  - Pure POSIX shell — works on Linux, macOS, WSL, and any system with `/bin/sh`  
  - No external dependencies (only standard Unix tools: `find`, `wc`, `awk`, etc.)

---

## 🚀 Quick Start

1. **Download the script**:
   ```sh
   curl -O https://raw.githubusercontent.com/your-username/your-repo/main/concat_files.sh
   chmod +x concat_files.sh
   ```

2. **Run it**:
   ```sh
   # Basic: concatenate all files into _concat/<dir>.txt
   ./concat_files.sh

   # With common ignores and line numbers
   ./concat_files.sh --ignore .git build '*.log' --line-numbers

   # Respect .gitignore and split into 40KB chunks
   ./concat_files.sh --gitignore --max-size 40960
   ```

3. **Check output**:
   ```sh
   ls _concat/
   # => boundary_mapper.txt          (if single file)
   # => boundary_mapper_part1.txt    (if multiple parts)
   ```

---

## 📋 Usage

```text
Usage: ./concat_files.sh [OPTIONS]

Concatenate all files (recursively) into one or more output files in '_concat/'.

OPTIONS:
  --ignore PATTERN...     Ignore files/dirs matching PATTERN anywhere (supports wildcards like *.log, build)
  --line-numbers          Prefix each line of file content with its line number
  --max-size N            Limit each output file to N bytes (default: unlimited)
  --max-input-size N      Skip source files larger than N bytes
  --gitignore             Also respect patterns from .gitignore (if exists)
  --help                  Show this help message and exit
```

### Examples

```sh
# Ignore common dev files
./concat_files.sh --ignore .git node_modules '*.pyc' 'Thumbs.db'

# Bundle code for an LLM context (with line numbers, 100KB chunks)
./concat_files.sh --gitignore --line-numbers --max-size 102400

# Only include small source files (<50KB), no splitting
./concat_files.sh --max-input-size 51200
```

---

## 📁 Output Structure

All output is placed in the `_concat/` directory (created automatically):

- **Single part**:  
  `_concat/<current_dir_name>.txt`  
  Example: `_concat/my_project.txt`

- **Multiple parts**:  
  `_concat/<current_dir_name>_part1.txt`  
  `_concat/<current_dir_name>_part2.txt`  
  …

> 💡 The `_concat` directory is **always excluded** from input scanning and **cleared on every run**.

Each file contains blocks like:

```text
### FILE: ./src/main.cpp
1: #include <iostream>
2: int main() {
3:     std::cout << "Hello\n";
4:     return 0;
5: }
```

---

## 📝 Notes

- Patterns in `--ignore` and `.gitignore` are matched against **file/directory names only** (not full paths), similar to how `git` treats unrooted patterns.
- Rules with `/` (e.g., `/build/`) are partially supported: leading `/` is stripped, and complex paths (e.g., `dir/file`) are ignored for safety.
- The script **does not follow symlinks** (uses default `find` behavior).
