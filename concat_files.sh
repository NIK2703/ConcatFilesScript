#!/bin/sh
# Default: no limits
MAX_OUTPUT_SIZE_SET=0
MAX_OUTPUT_SIZE=0
MAX_INPUT_SIZE_SET=0
MAX_INPUT_SIZE=0
OUTPUT_DIR="_concat"
LINE_NUMBERS="false"
IGNORE_PATTERNS=""
USE_GITIGNORE="false"
UNCOMMITTED_CHANGES="false"  # <-- added

# Get current directory name for output filename
DIR_NAME=$(basename "$PWD")

# Show help message
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]
Concatenate all files (recursively) into one or more output files in '_concat/'.
OPTIONS:
  --ignore PATTERN...     Ignore files/dirs matching PATTERN anywhere (supports wildcards like *.log, build)
  --line-numbers          Prefix each line of file content with its line number
  --max-size N            Limit each output file to N bytes (default: unlimited)
  --max-input-size N      Skip source files larger than N bytes
  --gitignore             Also respect patterns from .gitignore (if exists)
  --uncommitted-changes   Only include files changed since last commit (including unstaged)
  --help                  Show this help message and exit
Examples:
  $0 --ignore .git build '*.log'
  $0 --gitignore --line-numbers --max-size 40960
  $0 --max-input-size 100000
  $0 --uncommitted-changes
Output files:
  - If single part:   _concat/<dir>.txt
  - If multiple parts: _concat/<dir>_part1.txt, _concat/<dir>_part2.txt, ...
Note: The '_concat' directory is always ignored and recreated on each run.
EOF
}

# Parse command-line arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --help)
            show_help
            exit 0
            ;;
        --ignore)
            shift
            while [ $# -gt 0 ] && ! echo "$1" | grep -q '^--'; do
                if [ -z "$IGNORE_PATTERNS" ]; then
                    IGNORE_PATTERNS="$1"
                else
                    IGNORE_PATTERNS="$IGNORE_PATTERNS $1"
                fi
                shift
            done
            ;;
        --line-numbers)
            LINE_NUMBERS="true"
            shift
            ;;
        --max-size)
            shift
            if [ $# -eq 0 ] || ! echo "$1" | grep -q '^[0-9][0-9]*$'; then
                echo "Error: --max-size requires a numeric argument" >&2
                exit 1
            fi
            MAX_OUTPUT_SIZE="$1"
            MAX_OUTPUT_SIZE_SET=1
            shift
            ;;
        --max-input-size)
            shift
            if [ $# -eq 0 ] || ! echo "$1" | grep -q '^[0-9][0-9]*$'; then
                echo "Error: --max-input-size requires a numeric argument" >&2
                exit 1
            fi
            MAX_INPUT_SIZE="$1"
            MAX_INPUT_SIZE_SET=1
            shift
            ;;
        --gitignore)
            USE_GITIGNORE="true"
            shift
            ;;
        --uncommitted-changes)  # <-- added
            UNCOMMITTED_CHANGES="true"
            shift
            ;;
        *)
            echo "Unknown argument: $1" >&2
            echo "Run '$0 --help' for usage." >&2
            exit 1
            ;;
    esac
done

# Collect all file/directory patterns to ignore
FILE_PATTERNS=""
# Always ignore _concat (as file or directory)
FILE_PATTERNS="_concat"
# Add user-provided --ignore patterns
if [ -n "$IGNORE_PATTERNS" ]; then
    for pat in $IGNORE_PATTERNS; do
        FILE_PATTERNS="$FILE_PATTERNS $pat"
    done
fi
# Parse .gitignore if requested
if [ "$USE_GITIGNORE" = "true" ] && [ -f ".gitignore" ]; then
    while IFS= read -r line; do
        # Trim whitespace
        line=$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        # Skip empty lines and comments
        if [ -z "$line" ] || printf '%s' "$line" | grep -q '^[#;]'; then
            continue
        fi
        # Skip negations and ** patterns (not supported)
        if printf '%s' "$line" | grep -q '!' || printf '%s' "$line" | grep -q '\*\*'; then
            continue
        fi
        # Remove trailing slash (not needed for file matching)
        line=$(printf '%s' "$line" | sed 's|/$||')
        # Handle patterns with slashes
        if printf '%s' "$line" | grep -q '/'; then
            if printf '%s' "$line" | grep -q '^/'; then
                # Convert /name → name
                line=$(printf '%s' "$line" | sed 's|^/||')
                if [ -z "$line" ] || printf '%s' "$line" | grep -q '/'; then
                    continue
                fi
                FILE_PATTERNS="$FILE_PATTERNS $line"
            else
                # Skip complex paths like dir/file
                continue
            fi
        else
            FILE_PATTERNS="$FILE_PATTERNS $line"
        fi
    done < .gitignore
fi

# Build find command: prune directories that match patterns
FIND_ARGS=""
for pat in $FILE_PATTERNS; do
    FIND_ARGS="$FIND_ARGS -name '$pat' -type d -prune -o"
done
FIND_CMD="find . $FIND_ARGS -type f"

# Clear and recreate output directory
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# Create temporary file list
TMP_FILE_LIST="$(mktemp)" || { echo "Error: could not create temp file" >&2; exit 1; }

if [ "$UNCOMMITTED_CHANGES" = "true" ]; then
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        echo "Error: not a git repository" >&2
        exit 1
    fi
    > "$TMP_FILE_LIST"
{
    # Modified, added, renamed, etc. (tracked changes)
    git diff --name-only --diff-filter=ACMRTUXB HEAD
    # Untracked files (not in .gitignore)
    git ls-files --others --exclude-standard
} | sort -u | {
    while IFS= read -r relpath; do
        # Skip empty lines
        [ -z "$relpath" ] && continue
        # Skip if file doesn't exist (e.g. deleted)
        [ ! -e "./$relpath" ] && continue
        fullpath="./$relpath"
        skip=0
        path="$fullpath"
        while [ "$path" != "." ]; do
            comp=$(basename "$path")
            for pat in $FILE_PATTERNS "$(basename "$0")"; do
                if [ "$comp" = "$pat" ]; then
                    skip=1
                    break 2
                fi
            done
            next=$(dirname "$path")
            if [ "$next" = "$path" ]; then break; fi
            path="$next"
        done
        if [ "$skip" = "0" ]; then
            printf '%s\n' "$fullpath"
        fi
    done
} > "$TMP_FILE_LIST"
else
    eval "$FIND_CMD" > "$TMP_FILE_LIST"
fi

# Initialize concatenation state
PART=1
CURRENT_FILE=""
CURRENT_SIZE=0
PARTS_CREATED=""

# Helper: get file content (with or without line numbers)
get_content() {
    if [ "$LINE_NUMBERS" = "true" ]; then
        awk '{print NR ": " $0}' "$1"
    else
        cat "$1"
    fi
}

# Helper: estimate final size of file content
estimate_size() {
    if [ "$LINE_NUMBERS" = "true" ]; then
        get_content "$1" | wc -c
    else
        wc -c < "$1"
    fi
}

# Process each file
while IFS= read -r filepath; do
    case "$filepath" in
        */output_part_*.txt) continue ;;
        "$OUTPUT_DIR"/*) continue ;;
    esac
    # Skip filenames containing newline (extremely rare)
    case "$filepath" in
        *$'\n'*) continue ;;
    esac
    # Extract basename for pattern matching
    basename=$(basename "$filepath")
    # Skip files matching any ignore pattern or this script
    skip=0
    for pat in $FILE_PATTERNS; do
        case "$basename" in
            $pat)
                skip=1
                break
                ;;
        esac
    done
    if [ "$skip" = "0" ] && [ "$basename" = "$(basename "$0")" ]; then
        skip=1
    fi
    if [ "$skip" = "1" ]; then
        continue
    fi
    # Get raw file size
    RAW_SIZE=$(wc -c < "$filepath" 2>/dev/null)
    if ! echo "$RAW_SIZE" | grep -q '^[0-9][0-9]*$' || [ "$RAW_SIZE" -eq 0 ]; then
        continue
    fi
    # Skip if larger than --max-input-size
    if [ "$MAX_INPUT_SIZE_SET" -eq 1 ] && [ "$RAW_SIZE" -gt "$MAX_INPUT_SIZE" ]; then
        continue
    fi
    # Calculate size with header and possible line numbers
    CONTENT_SIZE=$(estimate_size "$filepath")
    HEADER="### FILE: $filepath"
    HEADER_SIZE=$(printf '%s' "$HEADER" | wc -c)
    ENTRY_SIZE=$((HEADER_SIZE + 1 + CONTENT_SIZE))
   # Append to current part or start new one
if [ "$MAX_OUTPUT_SIZE_SET" -eq 0 ] || [ $((CURRENT_SIZE + ENTRY_SIZE)) -le "$MAX_OUTPUT_SIZE" ]; then
    if [ -z "$CURRENT_FILE" ]; then
        CURRENT_FILE="output_part_${PART}.txt"
        printf '%s\n' "$HEADER" > "$CURRENT_FILE"
        get_content "$filepath" >> "$CURRENT_FILE"
        FIRST_FILE_IN_PART="false"
    else
        printf '\n%s\n' "$HEADER" >> "$CURRENT_FILE"
        get_content "$filepath" >> "$CURRENT_FILE"
    fi
    CURRENT_SIZE=$((CURRENT_SIZE + ENTRY_SIZE))
else
    PARTS_CREATED="$PARTS_CREATED $PART"
    PART=$((PART + 1))
    CURRENT_FILE="output_part_${PART}.txt"
    printf '%s\n' "$HEADER" > "$CURRENT_FILE"
    get_content "$filepath" >> "$CURRENT_FILE"
    FIRST_FILE_IN_PART="false"
    CURRENT_SIZE=$ENTRY_SIZE
fi
done < "$TMP_FILE_LIST"

# Handle last part
if [ -n "$CURRENT_FILE" ]; then
    PARTS_CREATED="$PARTS_CREATED $PART"
fi

# Count total parts
TOTAL_PARTS=0
for p in $PARTS_CREATED; do
    TOTAL_PARTS=$((TOTAL_PARTS + 1))
done

# Move temporary files to final names
if [ "$TOTAL_PARTS" -eq 1 ]; then
    SRC="output_part_$(echo $PARTS_CREATED | awk '{print $1}').txt"
    DEST="$OUTPUT_DIR/${DIR_NAME}.txt"
    mv "$SRC" "$DEST" 2>/dev/null || echo "Warning: failed to move $SRC" >&2
else
    IDX=1
    for p in $PARTS_CREATED; do
        SRC="output_part_${p}.txt"
        DEST="$OUTPUT_DIR/${DIR_NAME}_part${IDX}.txt"
        mv "$SRC" "$DEST" 2>/dev/null || echo "Warning: failed to move $SRC" >&2
        IDX=$((IDX + 1))
    done
fi

# Cleanup
rm -f output_part_*.txt
rm -f "$TMP_FILE_LIST"