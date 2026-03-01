#!/usr/bin/env bash
# tests/run_all.sh — Run convert.sh against every test-case cpu-x input,
# then validate the output with the PHP parser.
#
# Usage:
#   bash tests/run_all.sh [--verbose] [--keep-output]
#
# Options:
#   --verbose      Pass --verbose to validate.php (shows every PASS line)
#   --keep-output  Keep the generated .txt files in tests/<case>/converted.txt
#
# Exit codes:
#   0  all cases passed
#   1  one or more cases failed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONVERT="$REPO_ROOT/src/convert.sh"
VALIDATE="$SCRIPT_DIR/validate.php"

VERBOSE=0
KEEP=0
for arg in "$@"; do
    case "$arg" in
        --verbose)      VERBOSE=1 ;;
        --keep-output)  KEEP=1 ;;
    esac
done

# Verify prerequisites
if [[ ! -f "$CONVERT" ]]; then
    echo "ERROR: convert.sh not found at $CONVERT" >&2
    exit 1
fi

if [[ ! -f "$VALIDATE" ]]; then
    echo "ERROR: validate.php not found at $VALIDATE" >&2
    exit 1
fi

PHP_BIN=""
if command -v php &>/dev/null; then
    PHP_BIN="php"
elif command -v php8 &>/dev/null; then
    PHP_BIN="php8"
elif command -v php8.0 &>/dev/null; then
    PHP_BIN="php8.0"
elif command -v php8.1 &>/dev/null; then
    PHP_BIN="php8.1"
elif command -v php8.2 &>/dev/null; then
    PHP_BIN="php8.2"
elif command -v php8.3 &>/dev/null; then
    PHP_BIN="php8.3"
fi

if [[ -z "$PHP_BIN" ]]; then
    echo "WARNING: php not found in PATH — validation step will be skipped." >&2
    echo "         Install PHP (>= 7.4) to enable parser validation." >&2
    PHP_AVAILABLE=0
else
    PHP_AVAILABLE=1
fi

chmod +x "$CONVERT"

# ---------------------------------------------------------------------------
# Discover test cases: any subdirectory of tests/ that contains cpu-x.txt
# ---------------------------------------------------------------------------
mapfile -t CASES < <(find "$SCRIPT_DIR" -mindepth 2 -maxdepth 2 -name "cpu-x.txt" | sort)

if [[ ${#CASES[@]} -eq 0 ]]; then
    echo "ERROR: No test cases found (expected tests/<case>/cpu-x.txt)" >&2
    exit 1
fi

TOTAL=0
PASSED=0
FAILED=0
FAILED_CASES=()

# ---------------------------------------------------------------------------
# Run each case
# ---------------------------------------------------------------------------
for CPUX_FILE in "${CASES[@]}"; do
    CASE_DIR="$(dirname "$CPUX_FILE")"
    CASE_NAME="$(basename "$CASE_DIR")"
    CONVERTED="$CASE_DIR/converted.txt"

    TOTAL=$(( TOTAL + 1 ))
    echo "========================================"
    echo "Test case: $CASE_NAME"
    echo "  Input:  $CPUX_FILE"
    echo "  Output: $CONVERTED"
    echo "----------------------------------------"

    # Step 1: Run convert.sh
    if ! bash "$CONVERT" "$CPUX_FILE" > "$CONVERTED" 2>/tmp/convert_stderr_$$; then
        echo "  [FAIL] convert.sh exited with error:"
        cat /tmp/convert_stderr_$$
        rm -f /tmp/convert_stderr_$$
        FAILED=$(( FAILED + 1 ))
        FAILED_CASES+=("$CASE_NAME (convert.sh failed)")
        [[ $KEEP -eq 0 ]] && rm -f "$CONVERTED"
        continue
    fi
    rm -f /tmp/convert_stderr_$$

    CONV_LINES=$(wc -l < "$CONVERTED")
    echo "  convert.sh: OK ($CONV_LINES lines)"

    # Step 2: Validate with PHP parser (if PHP is available)
    if [[ $PHP_AVAILABLE -eq 0 ]]; then
        echo "  [SKIP] PHP not available — skipping parser validation"
        PASSED=$(( PASSED + 1 ))
    else
        PHP_ARGS=()
        [[ $VERBOSE -eq 1 ]] && PHP_ARGS+=("--verbose")

        if "$PHP_BIN" "$VALIDATE" "$CONVERTED" "${PHP_ARGS[@]}"; then
            PASSED=$(( PASSED + 1 ))
        else
            FAILED=$(( FAILED + 1 ))
            FAILED_CASES+=("$CASE_NAME (validation failed)")
        fi
    fi

    # Clean up unless --keep-output
    if [[ $KEEP -eq 0 ]]; then
        rm -f "$CONVERTED"
    else
        echo "  (output kept at $CONVERTED)"
    fi

    echo ""
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "========================================"
echo "Results: $PASSED/$TOTAL passed"
if [[ ${#FAILED_CASES[@]} -gt 0 ]]; then
    echo "Failed cases:"
    for c in "${FAILED_CASES[@]}"; do
        echo "  - $c"
    done
    exit 1
fi

echo "All test cases passed."
exit 0
