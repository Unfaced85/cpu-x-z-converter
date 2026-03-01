# cpu-x-z-converter

Converts the plain-text output of [cpu-x](https://github.com/TheTumultuousUnicornOfDarkness/CPU-X) into a [CPU-Z](https://www.cpuid.com/softwares/cpu-z.html)-compatible text report.

The generated file is structured to be parseable by `HardwareParser_CPUZ_Text.php`, producing structured hardware data for CPU, mainboard, RAM, GPU, and OS.

---

## Requirements

- Bash 4+
- Standard POSIX utilities: `awk`, `sed`, `grep`
- cpu-x installed and able to produce plain-text output

---

## Usage

```bash
# Generate a cpu-x plain-text dump (pipe or redirect)
cpu-x --dump > cpu-x.txt

# Convert to cpu-z format
src/convert.sh cpu-x.txt > converted.txt
```

The script reads from a file path or stdin:

```bash
# From stdin
cpu-x --dump | src/convert.sh /dev/stdin > converted.txt
```

---

## What it converts

cpu-x outputs German-language labels, ANSI escape codes, and locale-specific number formats. The converter handles all of this automatically:

| Input (cpu-x) | Output (cpu-z) |
|---|---|
| ANSI color codes | Stripped |
| German labels (`Hersteller`, `Kerne`, etc.) | Mapped to English CPU-Z field names |
| Decimal commas (`33,6`) | Converted to decimal points (`33.6`) |
| Size markers (`@GiB@`, `@MiB@`) | Converted to plain units (`MBytes`) |
| German instruction set notation | Expanded to standard CPU-Z format |

### Sections produced

| Output section | Source | Parser field |
|---|---|---|
| `Processors Information` | cpu-x CPU section | CPU name, codename, socket, cores, threads, clocks, cache, instructions |
| `DMI` | cpu-x Motherboard section | Board vendor, model, chipset |
| `Memory SPD` | cpu-x Memory section | Per-DIMM type, format, size, speed, part number |
| `Display Adapters` | cpu-x GPU section | GPU name, memory size/type, core/memory clocks |
| `Software` | cpu-x System section | OS name and kernel version |

---

## Test cases

Three reference cases are included under `tests/`:

| Case | CPU | GPU | OS |
|---|---|---|---|
| 1 | Ryzen 7 5800X3D (8c/16t) | RX 9070 XT | CachyOS (Linux 6.17) |
| 2 | Ryzen 9 5950X (16c/32t) | RX 7700/7800 XT | Debian 13 (Linux 6.12) |
| 3 | Ryzen 5 5600 (6c/12t, 4×DIMM) | RX 7900 XT/XTX | Manjaro (Linux 6.16) |

Run all tests:

```bash
bash tests/run_all.sh
```

If PHP is available, the test runner also validates the converted output through the parser and checks that all required fields are present. Without PHP, the shell conversion step is still verified.

---

## Repository structure

```
cpu-x-z-converter/
├── src/
│   └── convert.sh                     # Conversion script
├── tests/
│   ├── run_all.sh                     # Test runner
│   ├── validate.php                   # PHP parser validation (requires PHP >= 7.4)
│   ├── case 1/
│   │   ├── cpu-x.txt                  # Input: Ryzen 7 5800X3D, CachyOS
│   │   └── cpu-z.txt                  # Reference output
│   ├── case 2/
│   │   ├── cpu-x.txt                  # Input: Ryzen 9 5950X, Debian 13
│   │   └── cpu-z.txt                  # Reference output
│   └── case 3/
│       ├── cpu-x.txt                  # Input: Ryzen 5 5600, Manjaro
│       └── cpu-z.txt                  # Reference output
└── parser/
    └── HardwareParser_CPUZ_Text.php   # PHP parser (gitignored, reference only)
```
