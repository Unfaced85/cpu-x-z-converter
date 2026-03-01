# cpu-x-z-converter — Copilot Instructions

## Project Goal

This repository provides a Linux shell script (`src/convert.sh`) that reads the plain-text output of the **cpu-x** tool and converts it into a **cpu-z**-compatible text file. The resulting file must be parseable by `parser/HardwareParser_CPUZ_Text.php`, a PHP class that extracts structured hardware data from CPU-Z text reports.

Usage:
```
src/convert.sh path/to/cpu-x.txt > out.txt
```

---

## Repository Structure

```
cpu-x-z-converter/
├── src/
│   └── convert.sh              # Main conversion script (to be written/maintained)
├── tests/
│   ├── run_all.sh              # Test runner: runs convert.sh on each case and diffs output
│   ├── case 1/
│   │   ├── cpu-x.txt           # Input: Ryzen 7 5800X3D, CachyOS, RX 9070 XT
│   │   └── cpu-z.txt           # Reference output: CPU-Z 2.05.1
│   ├── case 2/
│   │   ├── cpu-x.txt           # Input: Ryzen 9 5950X, Debian 13, RX 7700/7800 XT
│   │   └── cpu-z.txt           # Reference output: CPU-Z 2.06.0
│   └── case 3/
│       ├── cpu-x.txt           # Input: Ryzen 5 5600, Manjaro, RX 7900 XT/XTX
│       └── cpu-z.txt           # Reference output: CPU-Z 2.17.0
└── parser/
    └── HardwareParser_CPUZ_Text.php   # PHP parser (reference — do not modify)
```

---

## Input Format: cpu-x text output

The cpu-x tool (`CPU-X`) outputs plain text to stdout. The file contains:

- **ANSI escape codes** (e.g. `[1;34m`, `[0m`, `[1;33m`) — must be stripped during parsing
- **German-language labels** throughout
- **Comma as decimal separator** (German locale): `33,6` MHz, `37,62°C`
- **Special unit markers**: `@GiB@`, `@MiB@`, `@KiB@` — must be converted to plain units

### Sections (delimited by `>>>>>>>>>> SECTION <<<<<<<<<<`):

```
>>>>>>>>>> CPU <<<<<<<<<<
>>>>>>>>>> Caches <<<<<<<<<<
>>>>>>>>>> Motherboard <<<<<<<<<<
>>>>>>>>>> Speicher <<<<<<<<<<       (Memory/RAM)
>>>>>>>>>> System <<<<<<<<<<
>>>>>>>>>> Grafik <<<<<<<<<<         (GPU)
```

### CPU Section fields (German → meaning):

| cpu-x label | Meaning |
|---|---|
| `Kerngeschwindigkeit:` | Core clock speed (MHz) |
| `Multiplikator:` | CPU multiplier (e.g. `x33,6 (22-34)`) |
| `Bustakt:` | Bus clock (MHz) |
| `Auslastung:` | CPU usage % |
| `Hersteller:` | Manufacturer (AMD) |
| `Codename:` | Codename (e.g. `Ryzen 7 (Vermeer)`) |
| `Paket:` | Socket (e.g. `AM4` or `AM4 (PGA-1331)`) |
| `Technologie:` | Process node (e.g. `TSMC N7FF` or `7 nm`) |
| `Spannung:` | Core voltage |
| `Spezifikation:` | Full CPU name string |
| `Familie:` | Family (hex) |
| `Angez. Familie:` | Extended family (hex) |
| `Modell:` | Model (hex) |
| `Angez. Modell:` | Extended model (hex) |
| `Stepping:` | Stepping |
| `Temp.:` | Temperature |
| `Instruktionen:` | Instruction sets (German notation) |
| `L1 Daten:` | L1 Data cache |
| `L1 Inst.:` | L1 Instruction cache |
| `Level 2:` | L2 cache |
| `Level 3:` | L3 cache |
| `Kerne:` | Number of cores |
| `Threads:` | Number of threads |

### Motherboard Section fields:

| cpu-x label | Meaning |
|---|---|
| `Hersteller:` (Motherboard) | MB manufacturer |
| `Modell:` (Motherboard) | MB model |
| `Revision:` | MB revision |
| `Marke:` (BIOS) | BIOS brand |
| `Version:` (BIOS) | BIOS version |
| `Datum:` (BIOS) | BIOS date |
| `Hersteller:` (Chipsatz) | Chipset manufacturer |
| `Modell:` (Chipsatz) | Chipset model (always `FCH LPC Bridge` for AMD) |

### Memory Section fields (per `***** Stick N *****`):

| cpu-x label | Meaning |
|---|---|
| `Hersteller:` | DIMM manufacturer |
| `Teilenummer:` | Part number |
| `Typ:` | Module type (e.g. `DIMM DDR4`) |
| `Typdetail:` | Module detail (e.g. `Synchronous Unbuffered (Unregistered)`) |
| `Gerätepositionsanzeiger:` | Device locator (e.g. `DIMM 1`) |
| `Bankpositionsanzeiger:` | Bank locator (e.g. `P0 CHANNEL A`) |
| `Reihe:` | Rank |
| `Größe:` | Size (e.g. `16 @GiB@`) |
| `Geschwindigkeit:` | Speed (e.g. `3200 MT/s (konfiguriert) / 3200 MT/s (max)`) |
| `Spannung:` | Voltage |

### GPU Section fields (per `***** Karte N *****`):

| cpu-x label | Meaning |
|---|---|
| `Hersteller:` | GPU manufacturer (AMD) |
| `Treiber:` | Driver (e.g. `amdgpu`) |
| `UMD-Version:` | Mesa version |
| `Modell:` | GPU model (e.g. `Navi 48 [Radeon RX 9070/9070 XT/9070 GRE]`) |
| `Recheneinheit:` | Compute units |
| `Gerätekennung:` | Device ID (e.g. `0x1002:0x7550`) |
| `VBIOS-Version:` | VBIOS version |
| `Schnittstelle:` | PCIe interface |
| `Kerntakt:` | GPU core clock (MHz) |
| `Speichertakt:` | GPU memory clock (MHz) |
| `Verwendeter Speicher:` | VRAM used/total (e.g. `2091 MiB / 16304 MiB`) |

---

## Output Format: cpu-z text report

The output must conform to the CPU-Z text report format, which is an English-language structured plain text file with the following characteristics:

- **Tab-indented fields**: top-level section headers are flush left; sub-fields are indented with a single tab
- **Section headers**: `SectionName\n-------------------------------------------------------------------------\n`
- **Field format**: `\tFieldName\t\t\tvalue` (tabs used for alignment)
- **No ANSI codes**
- **Decimal point** (not comma) for numbers

### Required sections and fields for parser compatibility:

#### 1. Header
```
CPU-Z TXT Report
-------------------------------------------------------------------------

Binaries
-------------------------------------------------------------------------

CPU-Z version			2.05.1.x64
```
The version string must be >= `2.01.0` for `HardwareParser_CPUZ_Text.php` to accept the file.

#### 2. `Processors Information` section
This is the primary section parsed for CPU data. Fields must match exactly (including casing):

```
Processors Information
-------------------------------------------------------------------------

Socket 1			ID = 0
	Number of cores		8 (max 8)
	Number of threads	16 (max 16)
	Number of CCDs		1
	Manufacturer		AuthenticAMD
	Name			AMD Ryzen 7 5800X3D
	Codename		Vermeer
	Specification		AMD Ryzen 7 5800X3D 8-Core Processor
	Package 		Socket AM4 (1331)
	CPUID			F.1.2
	Extended CPUID		19.21
	Core Stepping		VMR-B2
	Technology		7 nm
	TDP Limit		105.0 Watts
	Tjmax			90.0 °C
	Core Speed		4449.0 MHz
	Multiplier x Bus Speed	44.5 x 100.0 MHz
	Base frequency (cores)	100.0 MHz
	Base frequency (mem.)	100.0 MHz
	Instructions sets	MMX (+), SSE, SSE2, SSE3, SSSE3, SSE4.1, SSE4.2, SSE4A, x86-64, AMD-V, AES, AVX, AVX2, FMA3, SHA
	Microcode Revision	0xA20120A
	L1 Data cache		8 x 32 KB (8-way, 64-byte line)
	L1 Instruction cache	8 x 32 KB (8-way, 64-byte line)
	L2 cache		8 x 512 KB (8-way, 64-byte line)
	L3 cache		96 MB (16-way, 64-byte line)
```

**Field name notes for the PHP parser** (`_dataFields['CPU']`):
- `Name` → parsed as `name` (CPU model name, e.g. `AMD Ryzen 7 5800X3D`)
- `Codename` → parsed as `codename`
- `Specification` → parsed as `specification`
- `Package` (or `Package (platform ID)`) → parsed as `socket`; the `socket` filter strips `Socket ` prefix and `(...)` suffix, so output `Socket AM4 (1331)` to get `AM4` after filtering
- `Number of cores` → parsed as `cores`
- `Number of threads` → parsed as `threads`
- `Multiplier x Bus Speed` → parsed as `multiplier` and `bus_speed`; format must be `X.X x Y.Y MHz`
- `Core speed` → parsed as `core_speed` (note: field name in parser is `Core speed` with lowercase 's')
- `Instructions sets` → parsed as `instructions`

#### 3. `Memory SPD` section
This is what the parser uses for RAM data. Each DIMM is a `DIMM #` block:

```
Memory SPD
-------------------------------------------------------------------------

DIMM #				1
	Memory type		DDR4
	Module format		UDIMM
	Module Manufacturer(ID)	Crucial Technology (7F7F7F7F7F9B0000000000000000)
	Size			16384 MBytes
	Max bandwidth		DDR4-3200 (1600 MHz)
	Part number		BLS16G4D32AESC.M16FE
```

**Field name notes for the PHP parser** (`_dataFields['Memory']`):
- `Module Manufacturer(ID)` → parsed as `manufacturer`
- `Manufacturer (ID)` → also parsed as `manufacturer` (alternate)
- `Memory type` → parsed as `memory_type`
- `Module format` → parsed as `socket` (the module form factor: UDIMM, SODIMM, etc.)
- `Part number` → parsed as `serial`
- `Size` → parsed as `size` (in MBytes, integer)
- `Max bandwidth` → parsed as `max_bandwidth`; value after `-` is extracted (e.g. `3200` from `DDR4-3200`)

#### 4. `Display Adapters` section (GPU)
The parser (`_getGPUInfo`) looks for `Display adapter N` blocks:

```
Display Adapters
-------------------------------------------------------------------------

Display adapter 0	
	Name			AMD Radeon RX 9070 XT
	Board Manufacturer	PowerColor
	Memory size		16304 MB
	Memory type		GDDR6
	Core clock		300 MHz
	Memory clock		96 MHz
```

**Field name notes for the PHP parser** (`_dataFields['GPU']`):
- `Name` → parsed as `name`
- `Board Manufacturer` → parsed as `manufacturer`
- `Memory size` → parsed as `memory` (in MB)
- `Memory type` → parsed as `memory_type`
- `Core clock` → parsed as `core_clock` (integer, floor)
- `Memory clock` → parsed as `memory_clock` (integer, floor)

The parser skips onboard GPUs matching `Radeon(TM) Graphics` or `Intel(R) UHD/HD Graphics`.

#### 5. `DMI` section (Mainboard fallback)
The PHP parser uses `DMI Baseboard` for mainboard vendor/model. Provide this section for compatibility:

```
DMI
-------------------------------------------------------------------------

DMI Baseboard
	vendor			Gigabyte Technology Co., Ltd.
	model			X570S UD
	Southbridge		AMD FCH
```

#### 6. `Software` section (Windows/OS info)
The parser extracts `Windows Version` and `DirectX Version`. Since cpu-x runs on Linux, output a Linux placeholder or omit; the parser handles missing values gracefully.

---

## Key Field Transformations (cpu-x → cpu-z)

### CPU Manufacturer
- `AMD` (cpu-x) → `AuthenticAMD` (cpu-z `Manufacturer` field)

### Codename
- cpu-x: `Ryzen 7 (Vermeer)` → cpu-z: `Vermeer` (strip CPU family prefix and parentheses)

### Package/Socket
- cpu-x: `AM4` or `AM4 (PGA-1331)` → cpu-z: `Socket AM4 (1331)` (add "Socket " prefix; normalize pin count)

### Technology
- cpu-x: `TSMC N7FF` or `7 nm` → cpu-z: `7 nm` (normalize to just the node size)

### CPUID fields
- `Familie: 0xF`, `Angez. Familie: 0x19`, `Modell: 0x1`, `Angez. Modell: 0x21`, `Stepping: 2`
- cpu-z `CPUID`: `F.1.2` (Family.Model.Stepping in hex, no 0x prefix)
- cpu-z `Extended CPUID`: `19.21` (ext.family . ext.model in decimal/hex)

### Cache format
- cpu-x: `8 x   32 kB,  8-fach` → cpu-z: `8 x 32 KB (8-way, 64-byte line)`
- cpu-x: `96 MB, 16-fach` → cpu-z: `96 MB (16-way, 64-byte line)`
- Note: `kB` → `KB`, `fach` → `way`; line size is always 64 bytes for Zen 3

### Instruction sets (German → English)
The cpu-x `Instruktionen:` field uses a compact German format that must be expanded:

| cpu-x notation | cpu-z notation |
|---|---|
| `SMT` | (omit — SMT is a topology feature, not an instruction set) |
| `MMX(+)` | `MMX (+)` |
| `SSE(1, 2, 3, 3S, 4.1, 4.2, 4A)` | `SSE, SSE2, SSE3, SSSE3, SSE4.1, SSE4.2, SSE4A` |
| `AVX(1, 2)` | `AVX, AVX2` |
| `FMA(3)` | `FMA3` |
| `AES` | `AES` |
| `CLMUL` | (omit or keep — not in standard cpu-z output for Zen 3) |
| `RdRand` | (omit) |
| `SHA` | `SHA` |
| `AMD-V` | `AMD-V` |
| `x86-64` | `x86-64` |

Target format for Zen 3: `MMX (+), SSE, SSE2, SSE3, SSSE3, SSE4.1, SSE4.2, SSE4A, x86-64, AMD-V, AES, AVX, AVX2, FMA3, SHA`

### Multiplier/Bus Speed
- cpu-x: `x33,6 (22-34)` → cpu-z: `33.6 x 100.0 MHz` (remove `x` prefix, replace comma with period, append ` x 100.0 MHz`)
- When `Bustakt:` is available: use it as bus speed denominator; default to 100.0 MHz if empty

### Memory size
- cpu-x: `16 @GiB@` → MBytes: `16384 MBytes` (multiply GiB by 1024)
- Strip `@GiB@`, `@MiB@`, `@KiB@` markers and convert to MBytes for SPD section

### Memory type / Module format
- cpu-x `Typ: DIMM DDR4` → cpu-z `Memory type: DDR4` + `Module format: UDIMM`
- cpu-x `Typdetail: Synchronous Unbuffered (Unregistered)` confirms UDIMM

### RAM speed / Max bandwidth
- cpu-x: `3200 MT/s (konfiguriert) / 3200 MT/s (max)` → cpu-z: `Max bandwidth DDR4-3200 (1600 MHz)`
- Extract the MT/s value, format as `DDR4-{speed}`, compute half-speed for MHz: `3200/2 = 1600 MHz`

### GPU Name extraction
- cpu-x `Modell: Navi 48 [Radeon RX 9070/9070 XT/9070 GRE]` → cpu-z `Name AMD Radeon RX 9070 XT`
- Extract the bracketed content, pick the specific model name (e.g. "RX 9070 XT" from the slash-separated list if the VBIOS or device ID can disambiguate, otherwise use the full variant)
- Prefix with `AMD ` for AMD GPUs

### GPU Memory size
- cpu-x `Verwendeter Speicher: 2091 MiB / 16304 MiB` → cpu-z `Memory size 16304 MB`
- Extract the total (second value), strip `MiB` and output as `MB`

### GPU Device ID → Board Manufacturer
- cpu-x `Gerätekennung: 0x1002:0x7550` gives vendor:device IDs (hex)
- The sub-vendor ID is not available from cpu-x; use a placeholder like `Unknown` or derive from VBIOS if possible
- The PHP parser accepts any string for `Board Manufacturer`

---

## PHP Parser: What It Needs

The `HardwareParser_CPUZ_Text.php` parser (`parser/HardwareParser_CPUZ_Text.php`) is the downstream consumer. It parses these sections:

| Parser method | Section it looks for | Key fields |
|---|---|---|
| `_getCPUInfo()` | `Processors Information` | `Name`, `Codename`, `Specification`, `Package`, `Number of cores`, `Number of threads`, `Multiplier x Bus Speed`, `Core speed`, `Instructions sets` |
| `_getRAMInfo()` | `Memory SPD` | `DIMM #` blocks with `Memory type`, `Module format`, `Module Manufacturer(ID)`, `Size`, `Max bandwidth`, `Part number` |
| `_getGPUInfo()` | `Display Adapters` | `Display adapter N` blocks with `Name`, `Board Manufacturer`, `Memory size`, `Memory type`, `Core clock`, `Memory clock` |
| `_getMainBoardInfo()` | `DMI` | `DMI Baseboard` block with `vendor`, `model`; plus `Southbridge`/`Northbridge` for chipset |
| `_getSystemInfo()` | `Software` | `Windows Version`, `DirectX Version` |
| `_getDiskInfo()` | `Storage` | `Drive N` blocks |
| `_getDisplayInfo()` | `Display Adapters` | `Monitor N` blocks |

The parser also calls `checkVersion()` which requires `CPU-Z version` >= `2.01.0` in the `Binaries` section.

---

## Important Caveats

1. **Missing data in cpu-x**: Many cpu-z fields have no equivalent in cpu-x (CPUID hex dumps, MSR registers, P-state register values, per-core telemetry, microcode revision, TDP, Tjmax, etc.). These can be omitted or filled with reasonable defaults/placeholders — the PHP parser only requires the fields listed above.

2. **Thread dump section**: The massive `Thread dumps` section in cpu-z (per-thread CPUID and MSR hex data) is not required by the PHP parser and does not need to be generated.

3. **ANSI escape codes**: cpu-x output contains ANSI color escape codes. These must be completely stripped before parsing. Pattern: `\x1b\[[0-9;]*m` or `\033\[[0-9;]*m`.

4. **German locale numbers**: Decimal commas in cpu-x (e.g. `33,6`) must be converted to decimal points (e.g. `33.6`) in the output.

5. **`@unit@` markers**: cpu-x uses `@GiB@`, `@MiB@`, `@KiB@` as unit placeholders. These must be replaced with plain unit strings or converted appropriately.

6. **Blank fields in cpu-x**: Some fields may be empty (e.g. `Multiplikator:` with no value). The converter must handle these gracefully with fallback values or omit the corresponding cpu-z field.

7. **No RAM SPD detail in cpu-x**: cpu-x does not expose SPD manufacturer IDs, JEDEC timing tables, or XMP profiles. The generated `Memory SPD` section will contain only the fields derivable from cpu-x (type, format, size, speed, part number). This is sufficient for the PHP parser's minimum requirements.

8. **No Windows-specific sections**: cpu-z text exports from Windows include `Software` (Windows/DirectX versions), `Storage`, `Display Adapters` (with Windows driver info). The converter should generate at minimum the `Display Adapters` section (from cpu-x GPU data) and can omit `Software` and `Storage`.

---

## Test Cases Summary

| Case | CPU | Cores/Threads | Socket | GPU | OS |
|---|---|---|---|---|---|
| 1 | Ryzen 7 5800X3D | 8c/16t | AM4 | RX 9070 XT (Navi 48) | CachyOS (Linux 6.17) |
| 2 | Ryzen 9 5950X | 16c/32t | AM4 | RX 7700/7800 XT (Navi 32) | Debian 13 (Linux 6.12) |
| 3 | Ryzen 5 5600 | 6c/12t | AM4 | RX 7900 XT/XTX (Navi 31) | Manjaro (Linux 6.16) |

All test cases are AMD Zen 3 processors on AM4 platform with AMD discrete GPUs running Linux with Mesa/amdgpu drivers.
