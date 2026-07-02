# cpu-x-z-converter — Agent Instruction Set

## Project Identity

A Bash script (`src/convert.sh`) that reads plain-text output of the **cpu-x** tool (Linux hardware info) and converts it into a **CPU-Z**-compatible text report parseable by `HardwareParser_CPUZ_Text.php`.

**Goal**: Maximise structured hardware data extraction from cpu-x → CPU-Z format for CPU, mainboard, RAM, GPU, and OS.

**Quick start**:
```bash
cpu-x --dump | src/convert.sh /dev/stdin > converted.txt
bash tests/run_all.sh              # run full test suite
```

---

## Repository Structure

```
cpu-x-z-converter/
├── AGENT.md                        # This file
├── src/
│   └── convert.sh                  # Main converter script (Bash + awk)
├── tests/
│   ├── run_all.sh                  # Test runner (runs converter + PHP validation)
│   ├── validate.php                # PHP validation script
│   ├── case 1/                     # Ryzen 7 5800X3D (German labels)
│   │   ├── cpu-x.txt               #   — input
│   │   └── cpu-z.txt               #   — reference expected output
│   ├── case 2/                     # Ryzen 9 5950X (German labels)
│   ├── case 3/                     # Ryzen 5 5600 (German labels)
│   └── alex/                       # Ryzen 7 7800X3D (English labels)
│       └── cpu-x.txt
├── pcgh-parser/
│   └── HardwareParser_CPUZ_Text.php  # Downstream PHP parser (reference — do not modify)
└── pcgh-parser/                     # PHP parser (reference — do not modify)
```

---

## Architecture & Data Flow

```
cpu-x --dump                   # ANSI-coloured, German or English, comma decimals
      │
      ▼
  src/convert.sh
      │
      ├── Step 1: Strip ANSI codes (sed)
      ├── Step 2: Parse fields (awk) → key=value pairs emitted as shell vars
      └── Step 3: Transform + emit CPU-Z format (Bash printf)
      │
      ▼
  CPU-Z text report             # Tab-indented, English, dot decimals
      │
      ▼
  HardwareParser_CPUZ_Text.php  # Validates + extracts structured data
```

The awk parser (`parse_fields()`) extracts all fields into shell variables via `eval "$(parse_fields)"`. The transform functions then convert values (German→English, comma→dot, units). The output section emits the CPU-Z format report.

---

## Language Support (Critical)

The converter supports **both German and English** cpu-x output labels.

### How it works

The awk code only uses **German** labels internally. When the input is English, `normalize_key()` maps English labels to German equivalents before the field extraction logic runs:

```
Input label:  "Core Speed"
     │
     ▼
normalize_key("Core Speed") → "Kerngeschwindigkeit"
     │
     ▼
if (k == "Kerngeschwindigkeit") cpu_core_speed = decomma(v)   ✓ match
```

### When adding a new field

1. Add German-label parsing in the appropriate awk `if (k == "...")` block
2. Add an English→German mapping in `normalize_key()` if the English label differs
3. Add a `kv("VARIABLE_NAME", variable)` in the END block
4. Add output logic in the shell section
5. Add the variable to `eval` lines if it's an indexed array (for loop)

### Precedence

If a field has the same label in both languages (e.g. `Stepping`, `Threads`, `Version`, `Name`, `Kernel`), no normalize_key entry is needed — it matches directly.

---

## Key awk Parsing Rules

### Section detection (order matters)

Section headers use `>>>>>>>>>> SECTION <<<<<<<<<<` patterns. Subsection headers use `***** Subsection *****`. Both German and English names are matched via `||`:

```awk
/pattern1/ || /pattern2/ { action }
```

### Section/subsection structure

| awk section | awk subsection | German header | English header |
|---|---|---|---|
| `CPU` | `TAKTE` | `Takte` | `Clocks` |
| `CPU` | `PROC` | `Prozessor` | `Processor` |
| `CPU` | `CACHES` | `Caches` | `Caches` |
| `CPU` | `ANZAHL` | `Anzahl` | `Count` |
| `MB` | `BOARD` | `Motherboard` | `Motherboard` |
| `MB` | `BIOS` | `BIOS` | `BIOS` |
| `MB` | `CHIPSET` | `Chipsatz` | `Chipset` |
| `SYS` | `OS` | `Betriebssystem` | `Operating System` |
| `MEM` | *(stick index)* | `Stick N` | `Slot N` |
| `GPU` | *(card index)* | `Karte N` | `Card N` |

### Field extraction patterns

```awk
index($0, ":") > 0 {             # Only process lines with a colon
    line = $0
    gsub(/^[ \t]+/, "", line)    # Strip leading whitespace
    k = substr(line, 1, index(line, ":") - 1)  # Key before colon
    gsub(/[ \t]+$/, "", k)       # Trim trailing space from key
    v = val(line)                # Value after colon (trimmed)
    k = normalize_key(k)         # English→German mapping
    # ... if (k == "GermanLabel") assignments ...
}
```

---

## Field Transformation Reference

### `decomma(s)` — German decimal comma → dot
Applied to all numeric values: `33,6` → `33.6`. Only converts commas between two digits.

### `transform_manufacturer`
- `AMD` → `AuthenticAMD`
- `Intel` → `GenuineIntel`

### `transform_codename`
- `Ryzen 7 (Vermeer)` → `Vermeer` (extracts last parenthesised content)

### `transform_socket`
- `AM4` → `Socket AM4 (1331)` (lookup table for known sockets)
- `AM5 (LGA-1718)` → `Socket AM5 (1718)` (strips PGA-/LGA- prefix)

### `transform_tech`
- `TSMC N5` → `5 nm`
- `TSMC N7FF` → `7 nm`

### `build_cpuid` / `build_ext_cpuid`
- `Familie: 0xF`, `Modell: 0x1`, `Stepping: 2` → `F.1.2`
- Strips `0x` prefix, uppercases hex, joins with `.`

### `transform_cache`
- `8 x   32 kB,  8-way` → `8 x 32 KB (8-way, 64-byte line)`
- `96 MB, 16-fach` → `96 MB (16-way, 64-byte line)`
- Matches both `N-fach` (German) and `N-way` (English)
- Always appends `, 64-byte line`

### `transform_insn` — Instruction set expansion
- `SMT, MMX(+), SSE(1, 2, 3, 3S, 4.1, 4.2, 4A), AVX(1, 2, 512), FMA(3), AES, ...`
- → `MMX (+), SSE, SSE2, SSE3, SSSE3, SSE4.1, SSE4.2, SSE4A, x86-64, AMD-V, AES, AVX, AVX2, AVX-512, FMA3, SHA`
- Key expansion rules: `512` → `AVX-512`, `3S` → `SSSE3`, etc.

### `transform_multiplier` / `transform_bus` / `transform_core_speed`
- `x33,6 (22-34)` → `33.6` (strip x prefix, strip range, comma→dot)
- `99,97 MHz` → `100.0` (round to 1dp)
- `3361 MHz` → `3361.0`

### `transform_mem_size`
- `16 @GiB@` → `16384 MBytes` (GiB × 1024)
- Strips all `@GiB@`, `@MiB@`, `@KiB@` markers

### `transform_mem_speed`
- `3200 MT/s (konfiguriert) / 3200 MT/s (max)` → `DDR4-3200 (1600 MHz)`
- Memory type is detected dynamically (`DDR4`, `DDR5`, etc.)

### `transform_mem_type` / `transform_mem_format`
- `DIMM DDR4` → memory_type: `DDR4`, module_format: `UDIMM`
- `DIMM DDR5` → memory_type: `DDR5`, module_format: `UDIMM`

### `transform_gpu_name`
- `Navi 31 [Radeon RX 7900 XT/7900 XTX/7900 GRE/7900M]` → `AMD Radeon RX 7900 XT`
- Picks best match from slash-separated variants (prefers XT over XTX)
- Prefixes with vendor name

### `transform_gpu_mem` / `transform_gpu_mem_type`
- `8917 MiB / 24560 MiB` → `24560 MB` (extracts total)
- All modern AMD GPUs → `GDDR6`

---

## Output Format Rules

The CPU-Z text format uses:
- **Section headers**: `SectionName\n-------------------------------------------------------------------------\n`
- **Fields**: `\tFieldName\t\t\tvalue` (tab-indented, tabs for alignment via `field()` function)
- **Decimal point** (not comma)
- **English labels**
- **No ANSI codes**

### The `field()` helper

```bash
field() { printf "\t%-30s%s\n" "$1" "$2"; }
```

Produces: `\tName                         value`

Always use `field "Field Name" "$VALUE"` for field output. Use `printf` directly for section headers and structure.

### Conditional output pattern

```bash
[[ -n "$VARIABLE" ]] && field "Field Name" "$VARIABLE"
```

Only emit fields when the variable is non-empty.

---

## Output Sections Produced

| Section | Source | Key fields |
|---|---|---|
| `Binaries` | Static | CPU-Z version (`2.05.1.x64`) |
| `Processors` | Computed | Thread mask, socket count |
| `APICs` | Computed | Core/CCD/CCX/Thread topology |
| `Timers` | Static | ACPI/perf/sys timer freqs |
| `Processors Information` | cpu-x CPU | Name, Codename, Spec, Socket, Cores, Threads, Clocks, Cache, Instructions, Temperature |
| `DMI` | cpu-x Motherboard | vendor, model, revision, southbridge |
| `Memory SPD` | cpu-x Memory | Per-DIMM: type, format, size, speed, part number |
| `Display Adapters` | cpu-x GPU | Name, memory size/type, clocks, driver, UMD version, PCIe interface |
| `Software` | cpu-x System | OS name + kernel |

---

## Test Procedure

```bash
# Run all test cases (conversion + PHP parser validation)
bash tests/run_all.sh

# With verbose PASS/FAIL per field
bash tests/run_all.sh --verbose

# Keep converted output files for inspection
bash tests/run_all.sh --keep-output --verbose

# Run a single test case manually
bash src/convert.sh "tests/case 1/cpu-x.txt" > /tmp/out.txt
php tests/validate.php /tmp/out.txt
```

### Test cases

| Case | CPU | Labels | Memory | GPU |
|---|---|---|---|---|
| case 1 | Ryzen 7 5800X3D (8c/16t) | German | 2× DIMM DDR4 | RX 9070 XT |
| case 2 | Ryzen 9 5950X (16c/32t) | German | none | RX 7700 XT |
| case 3 | Ryzen 5 5600 (6c/12t) | German | 4× DIMM DDR4 | RX 7900 XT |
| alex | Ryzen 7 7800X3D (8c/16t) | English | none | RX 7900 XT |

### Validation exit codes
- `0` — all required fields present
- `1` — one or more required fields missing
- `2` — bad invocation / file not found

---

## Common Pitfalls

### 1. Locale-sensitive operations
Always use `LC_ALL=C` for numeric operations. Bash `printf "%.1f"` and `awk` are locale-sensitive — German locale expects `,` as decimal separator and will fail on `.`.

### 2. The normalize_key function scope
`normalize_key()` is shared across all sections. A mapping like `"Manufacturer" → "Hersteller"` applies everywhere. If a label has different meanings in different sections, use the `&& section == "..."` guard.

### 3. Section/subsection state is sticky
The awk code tracks `section` and `subsection` across lines. A `next` call skips to the next line, so header matches take priority over field parsing. Always call `next` in header/subsection matches.

### 4. Colon presence is required for field parsing
`index($0, ":") > 0` gates the field parsing block. Lines without `:` (section headers, subsection headers, blank lines) are never processed as fields.

### 5. GPU index tracking
GPU sections (like `Card 0`) set `gpu_idx`. Field parsing only happens when `gpu_idx >= 0`. Reset to `-1` when entering a new section.

### 6. Adding a new index-based field (arrays)
If adding an array field (like per-GPU data):
- In parsing: `gpu_varname[gpu_idx] = v`
- In END: `kv("GPU_VARNAME_" i, gpu_varname[i])`
- In output loop: `eval "GPU_VARNAME_VAL=\${GPU_VARNAME_${i}:-}"`
- Add BEGIN array initialization if needed (awk auto-initializes to empty)

### 7. The PHP parser file location
It lives at `pcgh-parser/HardwareParser_CPUZ_Text.php`. The test validator (`tests/validate.php`) references it directly via `__DIR__ . '/../pcgh-parser/...'`.

### 8. checkVersion() ordering in validate.php
`parseFile()` must be called **before** `checkVersion()` — the method reads `_rawContent` which is only set during `parseFile()`.

---

## When Adding a New cpu-x Field

1. **Identify the section+subsection** in the awk parsing block
2. **Add German-label match**: `if (k == "GermanLabel") variable = v`
3. **Add English mapping** in `normalize_key()` if English label differs
4. **Emit in END block**: `kv("VAR_NAME", variable)`
5. **Add transformation function** if value needs reformatting
6. **Add output line** in the appropriate section's shell code
7. **Run tests** to verify all cases still pass
8. **Check English dump** (`tests/alex/cpu-x.txt`) also works

---

## Git Conventions

- Commit messages are concise and match repo style
- No emojis in commits
- Do not amend pushed commits
- Before creating a PR, inspect status, diff, remote tracking, and base branch diff
