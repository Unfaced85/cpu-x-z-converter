#!/usr/bin/env bash
# convert.sh — Convert cpu-x plain-text output to cpu-z-compatible format
# Usage: src/convert.sh path/to/cpu-x.txt > out.txt

set -euo pipefail

INFILE="${1:-/dev/stdin}"

if [[ ! -f "$INFILE" && "$INFILE" != "/dev/stdin" ]]; then
    echo "Error: File not found: $INFILE" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Step 1: Strip ANSI escape codes and read cleaned content
# ---------------------------------------------------------------------------
CLEANED=$(sed 's/\x1b\[[0-9;]*[A-Za-z]//g' "$INFILE")

# ---------------------------------------------------------------------------
# Step 2: Parse all fields using awk
# ---------------------------------------------------------------------------
parse_fields() {
    echo "$CLEANED" | awk '
    function trim(s) {
        gsub(/^[ \t]+|[ \t]+$/, "", s)
        return s
    }

    # Extract value after first colon
    function val(line,    pos, v) {
        pos = index(line, ":")
        if (pos == 0) return ""
        v = substr(line, pos + 1)
        gsub(/^[ \t]+|[ \t]+$/, "", v)
        return v
    }

    # Replace German decimal comma with point (only in numeric contexts)
    # awk gsub does not support backreferences; scan character by character
    function decomma(s,    i, c, prev, nxt, out) {
        out = ""
        for (i = 1; i <= length(s); i++) {
            c = substr(s, i, 1)
            if (c == "," && i > 1 && i < length(s)) {
                prev = substr(s, i-1, 1)
                nxt  = substr(s, i+1, 1)
                if (prev ~ /[0-9]/ && nxt ~ /[0-9]/) {
                    out = out "."
                    continue
                }
            }
            out = out c
        }
        return out
    }

    # Emit a shell-safe KEY='value' assignment (escapes embedded single quotes)
    function kv(key, v,    safe) {
        safe = v
        gsub(/'\''/, "'\''\\'\'''\''", safe)
        printf "%s='\''%s'\''\n", key, safe
    }

    BEGIN {
        section = ""
        subsection = ""
        mem_idx = -1
        gpu_idx = -1
        mem_max = -1
        gpu_max = -1
    }

    # ---- Section detection ----
    />>>>>>>>>> CPU <<<<<<<<<</         { section = "CPU";    subsection = ""; next }
    />>>>>>>>>> Caches <<<<<<<<<</      { section = "CACHES"; subsection = ""; next }
    />>>>>>>>>> Motherboard <<<<<<<<<</ { section = "MB";     subsection = ""; next }
    />>>>>>>>>> Speicher <<<<<<<<<<>/   { section = "MEM";    subsection = ""; next }
    />>>>>>>>>> Speicher <<<<<<<<<<$/   { section = "MEM";    subsection = ""; next }
    />>>>>>>>>> System <<<<<<<<<<>/     { section = "SYS";    subsection = ""; next }
    />>>>>>>>>> System <<<<<<<<<<$/     { section = "SYS";    subsection = ""; next }
    />>>>>>>>>> Grafik <<<<<<<<<<>/     { section = "GPU";    subsection = ""; next }
    />>>>>>>>>> Grafik <<<<<<<<<<$/     { section = "GPU";    subsection = ""; next }

    # ---- Subsection detection ----
    /\*\*\*\*\* Takte \*\*\*\*\*/       { subsection = "TAKTE"; next }
    /\*\*\*\*\* Prozessor \*\*\*\*\*/   { subsection = "PROC"; next }
    /\*\*\*\*\* Caches \*\*\*\*\*/      { subsection = "CACHES"; next }
    /\*\*\*\*\* Anzahl \*\*\*\*\*/      { subsection = "ANZAHL"; next }
    /\*\*\*\*\* Motherboard \*\*\*\*\*/ { subsection = "BOARD"; next }
    /\*\*\*\*\* BIOS \*\*\*\*\*/        { subsection = "BIOS"; next }
    /\*\*\*\*\* Chipsatz \*\*\*\*\*/    { subsection = "CHIPSET"; next }
    /\*\*\*\*\* Betriebssystem \*\*\*\*\*/ { subsection = "OS"; next }

    # Memory stick index
    /\*\*\*\*\* Stick [0-9]+ \*\*\*\*\*/ {
        match($0, /Stick ([0-9]+)/, m)
        mem_idx = m[1] + 0
        next
    }

    # GPU card index
    /\*\*\*\*\* Karte [0-9]+ \*\*\*\*\*/ {
        match($0, /Karte ([0-9]+)/, m)
        gpu_idx = m[1] + 0
        next
    }

    # ---- Field parsing ----
    index($0, ":") > 0 {
        line = $0
        gsub(/^[ \t]+/, "", line)
        k = substr(line, 1, index(line, ":") - 1)
        gsub(/[ \t]+$/, "", k)
        v = val(line)

        # CPU section
        if (section == "CPU") {
            if (subsection == "TAKTE") {
                if (k == "Kerngeschwindigkeit") cpu_core_speed = decomma(v)
                if (k == "Multiplikator")       cpu_multiplier  = decomma(v)
                if (k == "Bustakt")             cpu_bus         = decomma(v)
            }
            if (subsection == "PROC") {
                if (k == "Hersteller")      cpu_vendor   = v
                if (k == "Codename")        cpu_codename = v
                if (k == "Paket")           cpu_socket   = v
                if (k == "Technologie")     cpu_tech     = v
                if (k == "Spannung")        cpu_voltage  = decomma(v)
                if (k == "Spezifikation")   cpu_spec     = v
                if (k == "Familie")         cpu_family   = v
                if (k == "Angez. Familie")  cpu_efamily  = v
                if (k == "Modell")          cpu_model    = v
                if (k == "Angez. Modell")   cpu_emodel   = v
                if (k == "Stepping")        cpu_stepping = v
                if (k == "Instruktionen")   cpu_insn     = v
            }
            if (subsection == "CACHES") {
                if (k == "L1 Daten") cpu_l1d = v
                if (k == "L1 Inst.") cpu_l1i = v
                if (k == "Level 2")  cpu_l2  = v
                if (k == "Level 3")  cpu_l3  = v
            }
            if (subsection == "ANZAHL") {
                if (k == "Kerne")   cpu_cores   = v + 0
                if (k == "Threads") cpu_threads = v + 0
            }
        }

        # Motherboard section
        if (section == "MB") {
            if (subsection == "BOARD") {
                if (k == "Hersteller") mb_vendor = v
                if (k == "Modell")     mb_model  = v
            }
            if (subsection == "BIOS") {
                if (k == "Marke")   bios_vendor  = v
                if (k == "Version") bios_version = v
                if (k == "Datum")   bios_date    = v
            }
            if (subsection == "CHIPSET") {
                if (k == "Hersteller") chipset_vendor = v
                if (k == "Modell")     chipset_model  = v
            }
        }

        # Memory section
        if (section == "MEM" && mem_idx >= 0) {
            if (k == "Hersteller")   mem_manuf[mem_idx]  = v
            if (k == "Teilenummer")  mem_part[mem_idx]   = v
            if (k == "Typ")          mem_type[mem_idx]   = v
            if (k == "Typdetail")    mem_detail[mem_idx] = v
            if (k == "Reihe")        mem_rank[mem_idx]   = v
            if (k == "Gr\xc3\xb6\xc3\x9fe" || k == "Größe") {
                mem_size_raw[mem_idx] = v
            }
            if (k == "Geschwindigkeit") mem_speed[mem_idx] = decomma(v)
            if (k == "Spannung")        mem_voltage[mem_idx] = decomma(v)
            # Track highest index seen
            if (mem_idx > mem_max) mem_max = mem_idx
        }

        # System/OS section
        if (section == "SYS") {
            if (subsection == "OS") {
                if (k == "Name")   sys_os_name   = v
                if (k == "Kernel") sys_os_kernel = v
            }
        }

        # GPU section
        if (section == "GPU" && gpu_idx >= 0) {
            if (k == "Hersteller")              gpu_vendor[gpu_idx]   = v
            if (k == "Modell")                  gpu_model[gpu_idx]    = v
            if (k == "Gerätekennung" || \
                k == "Ger\xc3\xa4tekennung")    gpu_devid[gpu_idx]    = v
            if (k == "VBIOS-Version")           gpu_vbios[gpu_idx]    = v
            if (k == "Kerntakt")                gpu_core_clk[gpu_idx] = decomma(v)
            if (k == "Speichertakt")            gpu_mem_clk[gpu_idx]  = decomma(v)
            if (k == "Verwendeter Speicher")    gpu_mem_used[gpu_idx] = v
            if (k == "Recheneinheit")           gpu_cu[gpu_idx]       = v
            # Track highest index seen
            if (gpu_idx > gpu_max) gpu_max = gpu_idx
        }
    }

    END {
        # Defaults
        if (cpu_cores   == "") cpu_cores   = 1
        if (cpu_threads == "") cpu_threads = cpu_cores * 2
        if (cpu_bus     == "") cpu_bus     = "100.0"
        if (mem_max     == "") mem_max     = -1
        if (gpu_max     == "") gpu_max     = -1

        # Output all parsed values as key=value for shell to consume
        kv("CPU_CORE_SPEED", cpu_core_speed)
        kv("CPU_MULTIPLIER", cpu_multiplier)
        kv("CPU_BUS",        cpu_bus)
        kv("CPU_VENDOR",     cpu_vendor)
        kv("CPU_CODENAME",   cpu_codename)
        kv("CPU_SOCKET",     cpu_socket)
        kv("CPU_TECH",       cpu_tech)
        kv("CPU_VOLTAGE",    cpu_voltage)
        kv("CPU_SPEC",       cpu_spec)
        kv("CPU_FAMILY",     cpu_family)
        kv("CPU_EFAMILY",    cpu_efamily)
        kv("CPU_MODEL",      cpu_model)
        kv("CPU_EMODEL",     cpu_emodel)
        kv("CPU_STEPPING",   cpu_stepping)
        kv("CPU_INSN",       cpu_insn)
        kv("CPU_L1D",        cpu_l1d)
        kv("CPU_L1I",        cpu_l1i)
        kv("CPU_L2",         cpu_l2)
        kv("CPU_L3",         cpu_l3)
        kv("CPU_CORES",      cpu_cores)
        kv("CPU_THREADS",    cpu_threads)
        kv("MB_VENDOR",      mb_vendor)
        kv("MB_MODEL",       mb_model)
        kv("BIOS_VENDOR",    bios_vendor)
        kv("BIOS_VERSION",   bios_version)
        kv("BIOS_DATE",      bios_date)
        kv("CHIPSET_VENDOR", chipset_vendor)
        kv("CHIPSET_MODEL",  chipset_model)
        kv("SYS_OS_NAME",   sys_os_name)
        kv("SYS_OS_KERNEL", sys_os_kernel)
        kv("MEM_MAX",        mem_max)
        kv("GPU_MAX",        gpu_max)

        for (i = 0; i <= mem_max; i++) {
            kv("MEM_MANUF_"  i, mem_manuf[i])
            kv("MEM_PART_"   i, mem_part[i])
            kv("MEM_TYPE_"   i, mem_type[i])
            kv("MEM_DETAIL_" i, mem_detail[i])
            kv("MEM_RANK_"   i, mem_rank[i])
            kv("MEM_SIZE_"   i, mem_size_raw[i])
            kv("MEM_SPEED_"  i, mem_speed[i])
            kv("MEM_VOLT_"   i, mem_voltage[i])
        }

        for (i = 0; i <= gpu_max; i++) {
            kv("GPU_VENDOR_"  i, gpu_vendor[i])
            kv("GPU_MODEL_"   i, gpu_model[i])
            kv("GPU_DEVID_"   i, gpu_devid[i])
            kv("GPU_VBIOS_"   i, gpu_vbios[i])
            kv("GPU_CORECLK_" i, gpu_core_clk[i])
            kv("GPU_MEMCLK_"  i, gpu_mem_clk[i])
            kv("GPU_MEMUSED_" i, gpu_mem_used[i])
            kv("GPU_CU_"      i, gpu_cu[i])
        }
    }
    '
}

# ---------------------------------------------------------------------------
# Load parsed fields into shell variables
# ---------------------------------------------------------------------------
eval "$(parse_fields)"

# ---------------------------------------------------------------------------
# Helper: emit a cpu-z style field line
# Usage: field "Name" "value"
# ---------------------------------------------------------------------------
field() {
    printf "\t%-30s%s\n" "$1" "$2"
}

sep() {
    printf -- "-------------------------------------------------------------------------\n"
}

# ---------------------------------------------------------------------------
# Transform helpers
# ---------------------------------------------------------------------------

# AMD -> AuthenticAMD, Intel -> GenuineIntel, else pass through
transform_manufacturer() {
    case "$1" in
        AMD)   echo "AuthenticAMD" ;;
        Intel) echo "GenuineIntel" ;;
        *)     echo "$1" ;;
    esac
}

# "Ryzen 7 (Vermeer)" -> "Vermeer"
# "Ryzen 9 (Vermeer)" -> "Vermeer"
transform_codename() {
    # Extract content inside last pair of parentheses
    echo "$1" | sed 's/.*(\(.*\))/\1/'
}

# "AM4" or "AM4 (PGA-1331)" -> "Socket AM4 (1331)"
transform_socket() {
    local raw="$1"
    # Strip PGA- prefix from pin count if present
    local socket
    socket=$(echo "$raw" | sed 's/^/Socket /' | sed 's/(PGA-\([0-9]*\))/(\1)/')
    # If no parenthesised pin count, look up known sockets
    if ! echo "$socket" | grep -q '('; then
        case "$raw" in
            AM4) socket="Socket AM4 (1331)" ;;
            AM5) socket="Socket AM5 (1718)" ;;
            LGA1700) socket="Socket LGA1700 (1700)" ;;
            *)   socket="Socket $raw" ;;
        esac
    fi
    echo "$socket"
}

# "TSMC N7FF" or "7 nm" or "TSMC N5" -> "7 nm" / "5 nm"
transform_tech() {
    local raw="$1"
    # Try to extract explicit "N<digits>" node from TSMC names
    local node
    node=$(echo "$raw" | grep -oiE 'N([0-9]+(\.[0-9]+)?)' | grep -oE '[0-9]+(\.[0-9]+)?' | head -1)
    if [[ -n "$node" ]]; then
        echo "${node} nm"
        return
    fi
    # Try to extract plain "<digits> nm" or "<digits>nm"
    node=$(echo "$raw" | grep -oE '[0-9]+(\.[0-9]+)? ?(nm|um)' | head -1)
    if [[ -n "$node" ]]; then
        echo "$node" | sed 's/\([0-9]\)\(nm\|um\)/\1 \2/'
        return
    fi
    echo "$raw"
}

# "0xF" -> "F" (strip 0x, uppercase)
strip_hex_prefix() {
    echo "$1" | sed 's/^0[xX]//' | tr '[:lower:]' '[:upper:]'
}

# Build CPUID string: "F.1.2" from Familie, Modell, Stepping
build_cpuid() {
    local fam model step
    fam=$(strip_hex_prefix "$CPU_FAMILY")
    model=$(strip_hex_prefix "$CPU_MODEL")
    step="$CPU_STEPPING"
    echo "${fam}.${model}.${step}"
}

# Build Extended CPUID: "19.21" from Angez.Familie, Angez.Modell
build_ext_cpuid() {
    local efam emodel
    efam=$(strip_hex_prefix "$CPU_EFAMILY")
    emodel=$(strip_hex_prefix "$CPU_EMODEL")
    echo "${efam}.${emodel}"
}

# Convert cache format:
# "8 x   32 kB,  8-fach assoziativ, 64-Bytes Zeilengröße" -> "8 x 32 KB (8-way, 64-byte line)"
# "96 MB, 16-fach assoziativ, 64-Bytes Zeilengröße"       -> "96 MB (16-way, 64-byte line)"
transform_cache() {
    local raw="$1"
    echo "$raw" | awk '{
        # Normalise whitespace
        gsub(/[ \t]+/, " ")
        gsub(/^ | $/, "")

        # Extract way count from "N-fach"
        way = ""
        if (match($0, /([0-9]+)-fach/, m)) way = m[1]

        # Strip everything from the first comma onward (covers "-fach assoziativ, 64-Bytes ...")
        sub(/,.*/, "")
        gsub(/^ | $/, "")

        # Fix unit: kB -> KB (MB stays MB)
        gsub(/kB/, "KB")

        # Normalise spaces around "x"
        gsub(/[ \t]+x[ \t]+/, " x ")
        gsub(/[ \t]+KB/, " KB")
        gsub(/[ \t]+MB/, " MB")

        if (way != "")
            printf "%s (%s-way, 64-byte line)\n", $0, way
        else
            print $0
    }'
}

# Convert German instruction set notation to cpu-z English format
# "SMT, MMX(+), SSE(1, 2, 3, 3S, 4.1, 4.2, 4A), AVX(1, 2), FMA(3), AES, CLMUL, RdRand, SHA, AMD-V, x86-64"
# -> "MMX (+), SSE, SSE2, SSE3, SSSE3, SSE4.1, SSE4.2, SSE4A, x86-64, AMD-V, AES, AVX, AVX2, FMA3, SHA"
transform_insn() {
    local raw="$1"
    local out=""

    append() { [[ -z "$out" ]] && out="$1" || out="$out, $1"; }

    # MMX(+)
    echo "$raw" | grep -q 'MMX(+)' && append "MMX (+)"

    # SSE(1, 2, 3, 3S, 4.1, 4.2, 4A) -> individual names
    local sse_inner
    sse_inner=$(echo "$raw" | grep -oE 'SSE\([^)]+\)' | sed 's/SSE(//;s/)//')
    if [[ -n "$sse_inner" ]]; then
        local IFS_SAVE="$IFS"; IFS=','
        for part in $sse_inner; do
            part=$(echo "$part" | tr -d ' ')
            case "$part" in
                1)   append "SSE" ;;
                2)   append "SSE2" ;;
                3)   append "SSE3" ;;
                3S)  append "SSSE3" ;;
                4.1) append "SSE4.1" ;;
                4.2) append "SSE4.2" ;;
                4A)  append "SSE4A" ;;
            esac
        done
        IFS="$IFS_SAVE"
    fi

    # x86-64
    echo "$raw" | grep -q 'x86-64' && append "x86-64"

    # AMD-V
    echo "$raw" | grep -q 'AMD-V' && append "AMD-V"

    # AES
    echo "$raw" | grep -q 'AES' && append "AES"

    # AVX(1, 2)
    local avx_inner
    avx_inner=$(echo "$raw" | grep -oE 'AVX\([^)]+\)' | sed 's/AVX(//;s/)//')
    if [[ -n "$avx_inner" ]]; then
        local IFS_SAVE="$IFS"; IFS=','
        for part in $avx_inner; do
            part=$(echo "$part" | tr -d ' ')
            case "$part" in
                1) append "AVX" ;;
                2) append "AVX2" ;;
            esac
        done
        IFS="$IFS_SAVE"
    fi

    # FMA(3)
    local fma_inner
    fma_inner=$(echo "$raw" | grep -oE 'FMA\([^)]+\)' | sed 's/FMA(//;s/)//')
    if [[ -n "$fma_inner" ]]; then
        local IFS_SAVE="$IFS"; IFS=','
        for part in $fma_inner; do
            part=$(echo "$part" | tr -d ' ')
            append "FMA${part}"
        done
        IFS="$IFS_SAVE"
    fi

    # SHA
    echo "$raw" | grep -q 'SHA' && append "SHA"

    [[ -n "$out" ]] && echo "$out" || echo "$raw"
}

# "x33,6 (22-34)" -> multiplier="33.6", returns just the numeric part
transform_multiplier() {
    local raw="$1"
    # Strip leading x, strip parenthesised range, replace comma with period
    echo "$raw" | sed 's/^x//' | sed 's/ *([^)]*)$//' | sed 's/,/./' | tr -d ' '
}

# Bus clock: "99,97 MHz" -> "100.0" (just the number, rounded to 1dp)
transform_bus() {
    local raw="$1"
    # Replace comma, strip MHz
    local num
    num=$(echo "$raw" | sed 's/,/./' | grep -oE '[0-9]+(\.[0-9]+)?' | head -1)
    if [[ -z "$num" ]]; then
        echo "100.0"
    else
        # Round to 1 decimal place
        printf "%.1f" "$num"
    fi
}

# Core speed: "3361 MHz" -> "3361.0"
transform_core_speed() {
    local raw="$1"
    local num
    num=$(echo "$raw" | grep -oE '[0-9]+(\.[0-9]+)?' | head -1)
    if [[ -n "$num" ]]; then
        printf "%.1f" "$num"
    fi
}

# Memory size: "16 @GiB@" -> 16384 MBytes
transform_mem_size() {
    local raw="$1"
    echo "$raw" | awk '{
        if (match($0, /([0-9]+)[ \t]*@?GiB@?/, m)) {
            printf "%d MBytes\n", m[1] * 1024
        } else if (match($0, /([0-9]+)[ \t]*@?MiB@?/, m)) {
            printf "%d MBytes\n", m[1]
        } else if (match($0, /([0-9]+)[ \t]*@?KiB@?/, m)) {
            printf "%d MBytes\n", int(m[1] / 1024)
        } else {
            print $0
        }
    }'
}

# Memory speed: "3200 MT/s (konfiguriert) / 3200 MT/s (max)" -> "DDR4-3200 (1600 MHz)"
transform_mem_speed() {
    local raw="$1"
    local mts
    mts=$(echo "$raw" | grep -oE '[0-9]+' | head -1)
    if [[ -n "$mts" ]]; then
        local mhz=$(( mts / 2 ))
        echo "DDR4-${mts} (${mhz} MHz)"
    fi
}

# Memory type/format: "DIMM DDR4" + detail -> type="DDR4", format="UDIMM"
transform_mem_type() {
    local typ="$1"
    echo "$typ" | grep -oE 'DDR[0-9]+'
}

transform_mem_format() {
    local typ="$1"
    local detail="$2"
    if echo "$detail" | grep -qi "unbuffered\|unregistered"; then
        echo "UDIMM"
    elif echo "$detail" | grep -qi "registered\|buffered"; then
        echo "RDIMM"
    elif echo "$typ" | grep -qi "SO-DIMM\|SODIMM"; then
        echo "SODIMM"
    else
        echo "UDIMM"
    fi
}

# GPU model: "Navi 48 [Radeon RX 9070/9070 XT/9070 GRE]" -> "AMD Radeon RX 9070 XT"
# Strategy: take bracketed section, use last slash-variant that contains "XT" or
# longest variant, prefix with vendor
transform_gpu_name() {
    local raw="$1"
    local vendor="$2"

    # Extract content inside brackets using sed (no grep -P needed)
    local bracketed
    bracketed=$(echo "$raw" | sed 's/.*\[\(.*\)\].*/\1/')
    # If sed didn't change the string, there were no brackets
    if [[ "$bracketed" == "$raw" ]]; then
        bracketed=""
    fi

    if [[ -z "$bracketed" ]]; then
        echo "${vendor} ${raw}"
        return
    fi

    # Split on '/' and pick best variant
    local best=""
    local IFS_ORIG="$IFS"
    IFS='/'
    read -ra parts <<< "$bracketed"
    IFS="$IFS_ORIG"

    # Trim whitespace from each part
    local trimmed=()
    for p in "${parts[@]}"; do
        p=$(echo "$p" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        trimmed+=("$p")
    done

    # Prefer plain XT (not XTX)
    for p in "${trimmed[@]}"; do
        if echo "$p" | grep -qE 'XT$' || echo "$p" | grep -qE 'XT '; then
            if ! echo "$p" | grep -q 'XTX'; then
                best="$p"
                break
            fi
        fi
    done

    # Then try XTX
    if [[ -z "$best" ]]; then
        for p in "${trimmed[@]}"; do
            if echo "$p" | grep -q 'XTX'; then
                best="$p"
                break
            fi
        done
    fi

    # Fallback: first variant
    if [[ -z "$best" ]]; then
        best="${trimmed[0]}"
    fi

    # Ensure "Radeon RX" prefix is present, carrying over prefix from first part if needed
    # e.g. parts: ["Radeon RX 9070", "9070 XT", "9070 GRE"] -> best="9070 XT" -> "Radeon RX 9070 XT"
    if ! echo "$best" | grep -q 'Radeon'; then
        # Try to extract a common prefix from the first full variant
        local first_full="${trimmed[0]}"
        if echo "$first_full" | grep -q 'Radeon'; then
            # Extract up to and including "RX" or brand prefix, strip trailing model number
            local prefix
            prefix=$(echo "$first_full" | sed 's/\([Rr]adeon [Rr][Xx]\? \).*/\1/' | sed 's/ $//')
            best="${prefix} ${best}"
        else
            best="Radeon $best"
        fi
    fi

    echo "${vendor} ${best}"
}

# GPU memory size: "2091 MiB / 16304 MiB" -> "16304 MB"
transform_gpu_mem() {
    local raw="$1"
    # Extract second number (total)
    local total
    total=$(echo "$raw" | awk '{
        # Find last number before MiB/MB
        n = split($0, a, "/")
        last = a[n]
        match(last, /([0-9]+)[ \t]*(MiB|MB)/, m)
        print m[1]
    }')
    if [[ -n "$total" ]]; then
        echo "${total} MB"
    fi
}

# GPU memory type from device ID heuristic (GDDR6 for modern AMD)
# Could be extended with a lookup table
transform_gpu_mem_type() {
    local devid="$1"
    local model="$2"
    # All Navi 2x/3x/4x are GDDR6
    if echo "$model" | grep -qE 'Navi [234][0-9]'; then
        echo "GDDR6"
    else
        echo "GDDR6"
    fi
}

# Number of CCDs: cores / 8, minimum 1
compute_ccds() {
    local cores="$1"
    local ccds=$(( (cores + 7) / 8 ))
    [[ $ccds -lt 1 ]] && ccds=1
    echo "$ccds"
}

# ---------------------------------------------------------------------------
# Compute derived values
# ---------------------------------------------------------------------------

CPU_MFR=$(transform_manufacturer "$CPU_VENDOR")
CPU_CODENAME_OUT=$(transform_codename "$CPU_CODENAME")
CPU_SOCKET_OUT=$(transform_socket "$CPU_SOCKET")
CPU_TECH_OUT=$(transform_tech "$CPU_TECH")
CPU_CPUID=$(build_cpuid)
CPU_EXT_CPUID=$(build_ext_cpuid)
CPU_CORES_OUT="${CPU_CORES:-1}"
CPU_THREADS_OUT="${CPU_THREADS:-2}"
CPU_CCDS=$(compute_ccds "$CPU_CORES_OUT")
CPU_SPEED_OUT=$(transform_core_speed "$CPU_CORE_SPEED")

# Multiplier and bus
if [[ -n "$CPU_MULTIPLIER" ]]; then
    MULT_NUM=$(transform_multiplier "$CPU_MULTIPLIER")
else
    # Derive from core speed / bus
    MULT_NUM=""
fi

if [[ -n "$CPU_BUS" && "$CPU_BUS" != " " ]]; then
    BUS_NUM=$(transform_bus "$CPU_BUS")
else
    BUS_NUM="100.0"
fi

if [[ -n "$MULT_NUM" && -n "$CPU_SPEED_OUT" ]]; then
    MULT_BUS_LINE="${MULT_NUM} x ${BUS_NUM} MHz"
elif [[ -n "$CPU_SPEED_OUT" && -n "$BUS_NUM" ]]; then
    # Compute multiplier from speed / bus (awk fallback)
    MULT_COMPUTED=$(python3 -c "print('%.1f' % (${CPU_SPEED_OUT} / ${BUS_NUM}))" 2>/dev/null \
        || awk -v s="${CPU_SPEED_OUT}" -v b="${BUS_NUM}" 'BEGIN { printf "%.1f\n", s/b }')
    if [[ -n "$MULT_COMPUTED" ]]; then
        MULT_BUS_LINE="${MULT_COMPUTED} x ${BUS_NUM} MHz"
    fi
fi

CPU_INSN_OUT=$(transform_insn "$CPU_INSN")
CPU_L1D_OUT=$(transform_cache "$CPU_L1D")
CPU_L1I_OUT=$(transform_cache "$CPU_L1I")
CPU_L2_OUT=$(transform_cache "$CPU_L2")
CPU_L3_OUT=$(transform_cache "$CPU_L3")

# ---------------------------------------------------------------------------
# Output the cpu-z format report
# ---------------------------------------------------------------------------

printf "CPU-Z TXT Report\n"
sep
printf "\n"

printf "Binaries\n"
sep
printf "\n"
field "CPU-Z version" "2.05.1.x64"
printf "\n"

printf "Processors\n"
sep
printf "\n"
field "CPU Groups" "1"
# Thread mask: 2^n - 1 in hex (awk fallback when python3 unavailable)
MASK=$(python3 -c "print('0x%X' % ((1 << ${CPU_THREADS_OUT}) - 1))" 2>/dev/null \
    || awk -v t="${CPU_THREADS_OUT}" 'BEGIN { v=1; for(i=0;i<t;i++) v*=2; printf "0x%X\n", v-1 }')
field "CPU Group 0" "${CPU_THREADS_OUT} threads, mask=${MASK}"
printf "\n"
field "Number of sockets" "1"
field "Number of threads" "${CPU_THREADS_OUT}"
printf "\n"

printf "APICs\n"
sep
printf "\n"
printf "Socket 0\t\n"
# Build CCD/CCX/Core/Thread topology
python3 -c "
cores   = int('${CPU_CORES_OUT}')
threads = int('${CPU_THREADS_OUT}')
ccds    = int('${CPU_CCDS}')
tpc     = threads // cores if cores > 0 else 2
cores_per_ccd = (cores + ccds - 1) // ccds

core_id   = 0
thread_id = 0

for ccd in range(ccds):
    print('\t-- Node %d\t' % ccd)
    print('\t\t-- CCD %d\t\t' % ccd)
    print('\t\t\t-- CCX 0\t\t')
    for c in range(cores_per_ccd):
        if core_id >= cores:
            break
        print('\t\t\t\t-- Core %d (ID %d)\t' % (core_id, core_id))
        for t in range(tpc):
            print('\t\t\t\t\t-- Thread %d\t%d' % (thread_id, thread_id))
            thread_id += 1
        core_id += 1
" 2>/dev/null || true
printf "\n"

printf "Timers\n"
sep
printf "\n"
field "ACPI timer" "3.580 MHz"
field "Perf timer" "10.000 MHz"
field "Sys timer"  "1.000 KHz"
printf "\n\n"

printf "Processors Information\n"
sep
printf "\n"
printf "Socket 1\t\t\tID = 0\n"
field "Number of cores"    "${CPU_CORES_OUT} (max ${CPU_CORES_OUT})"
field "Number of threads"  "${CPU_THREADS_OUT} (max ${CPU_THREADS_OUT})"
field "Number of CCDs"     "${CPU_CCDS}"
field "Manufacturer"       "$CPU_MFR"
[[ -n "$CPU_SPEC" ]]          && field "Name"          "$CPU_SPEC"
[[ -n "$CPU_CODENAME_OUT" ]]  && field "Codename"      "$CPU_CODENAME_OUT"
[[ -n "$CPU_SPEC" ]]          && field "Specification" "$CPU_SPEC"
[[ -n "$CPU_SOCKET_OUT" ]]    && field "Package"       "$CPU_SOCKET_OUT"
[[ -n "$CPU_CPUID" ]]         && field "CPUID"         "$CPU_CPUID"
[[ -n "$CPU_EXT_CPUID" ]]     && field "Extended CPUID" "$CPU_EXT_CPUID"
[[ -n "$CPU_TECH_OUT" ]]      && field "Technology"    "$CPU_TECH_OUT"
[[ -n "$CPU_SPEED_OUT" ]]     && field "Core Speed"    "${CPU_SPEED_OUT} MHz"
[[ -n "${MULT_BUS_LINE:-}" ]] && field "Multiplier x Bus Speed" "$MULT_BUS_LINE"
field "Base frequency (cores)" "${BUS_NUM} MHz"
field "Base frequency (mem.)"  "${BUS_NUM} MHz"
[[ -n "$CPU_INSN_OUT" ]]  && field "Instructions sets" "$CPU_INSN_OUT"
[[ -n "$CPU_L1D_OUT" ]]   && field "L1 Data cache"         "$CPU_L1D_OUT"
[[ -n "$CPU_L1I_OUT" ]]   && field "L1 Instruction cache"  "$CPU_L1I_OUT"
[[ -n "$CPU_L2_OUT" ]]    && field "L2 cache"              "$CPU_L2_OUT"
[[ -n "$CPU_L3_OUT" ]]    && field "L3 cache"              "$CPU_L3_OUT"
printf "\n\n\n"

# ---------------------------------------------------------------------------
# DMI section (Mainboard)
# ---------------------------------------------------------------------------
printf "DMI\n"
sep
printf "\n"
printf "DMI Baseboard\n"
[[ -n "$MB_VENDOR" ]]      && field "vendor" "$MB_VENDOR"
[[ -n "$MB_MODEL" ]]       && field "model"  "$MB_MODEL"
# Southbridge: derive from chipset vendor
if [[ -n "$CHIPSET_VENDOR" ]]; then
    if echo "$CHIPSET_VENDOR" | grep -qi "AMD"; then
        field "Southbridge" "AMD FCH"
    else
        field "Southbridge" "$CHIPSET_VENDOR"
    fi
fi
printf "\n"
printf "DMI System Enclosure\t\t\n"
field "chassis type" "Desktop"
printf "\n\n\n"

# ---------------------------------------------------------------------------
# Memory SPD section
# ---------------------------------------------------------------------------
if [[ "${MEM_MAX:-"-1"}" -ge 0 ]]; then
    printf "Memory SPD\n"
    sep
    printf "\n"

    for (( i=0; i<=MEM_MAX; i++ )); do
        eval "MEM_MANUF_VAL=\${MEM_MANUF_${i}:-}"
        eval "MEM_PART_VAL=\${MEM_PART_${i}:-}"
        eval "MEM_TYPE_VAL=\${MEM_TYPE_${i}:-}"
        eval "MEM_DETAIL_VAL=\${MEM_DETAIL_${i}:-}"
        eval "MEM_SIZE_VAL=\${MEM_SIZE_${i}:-}"
        eval "MEM_SPEED_VAL=\${MEM_SPEED_${i}:-}"
        eval "MEM_VOLT_VAL=\${MEM_VOLT_${i}:-}"

        DIMM_NUM=$(( i + 1 ))
        printf "DIMM #\t\t\t\t%d\t\n" "$DIMM_NUM"

        MEM_TYPE_OUT=$(transform_mem_type "$MEM_TYPE_VAL")
        MEM_FMT_OUT=$(transform_mem_format "$MEM_TYPE_VAL" "$MEM_DETAIL_VAL")
        MEM_SIZE_OUT=$(transform_mem_size "$MEM_SIZE_VAL")
        MEM_BW_OUT=$(transform_mem_speed "$MEM_SPEED_VAL")

        [[ -n "$MEM_TYPE_OUT" ]]   && field "Memory type"           "$MEM_TYPE_OUT"
        [[ -n "$MEM_FMT_OUT" ]]    && field "Module format"         "$MEM_FMT_OUT"
        [[ -n "$MEM_MANUF_VAL" ]]  && field "Module Manufacturer(ID)" "$MEM_MANUF_VAL"
        [[ -n "$MEM_SIZE_OUT" ]]   && field "Size"                  "$MEM_SIZE_OUT"
        [[ -n "$MEM_BW_OUT" ]]     && field "Max bandwidth"         "$MEM_BW_OUT"
        [[ -n "$MEM_PART_VAL" ]]   && field "Part number"           "$MEM_PART_VAL"
        [[ -n "$MEM_VOLT_VAL" ]]   && field "Nominal Voltage"       "$MEM_VOLT_VAL"
        printf "\n"
    done
    # Sentinel: ensures the last DIMM block has a trailing \n\n after trim() in the parser
    printf "SPD\t\t\t\t\t\n"
    printf "\n\n\n"
fi

# ---------------------------------------------------------------------------
# Display Adapters section (GPU)
# ---------------------------------------------------------------------------
if [[ "${GPU_MAX:-"-1"}" -ge 0 ]]; then
    printf "Display Adapters\n"
    sep
    printf "\n"

    for (( i=0; i<=GPU_MAX; i++ )); do
        eval "GPU_VENDOR_VAL=\${GPU_VENDOR_${i}:-}"
        eval "GPU_MODEL_VAL=\${GPU_MODEL_${i}:-}"
        eval "GPU_DEVID_VAL=\${GPU_DEVID_${i}:-}"
        eval "GPU_VBIOS_VAL=\${GPU_VBIOS_${i}:-}"
        eval "GPU_CORECLK_VAL=\${GPU_CORECLK_${i}:-}"
        eval "GPU_MEMCLK_VAL=\${GPU_MEMCLK_${i}:-}"
        eval "GPU_MEMUSED_VAL=\${GPU_MEMUSED_${i}:-}"

        GPU_NAME_OUT=$(transform_gpu_name "$GPU_MODEL_VAL" "$GPU_VENDOR_VAL" "$GPU_VBIOS_VAL")
        GPU_MEMSIZE_OUT=$(transform_gpu_mem "$GPU_MEMUSED_VAL")
        GPU_MEMTYPE_OUT=$(transform_gpu_mem_type "$GPU_DEVID_VAL" "$GPU_MODEL_VAL")

        # Extract MHz from clock strings
        GPU_CORECLK_NUM=$(echo "$GPU_CORECLK_VAL" | grep -oE '[0-9]+' | head -1)
        GPU_MEMCLK_NUM=$(echo "$GPU_MEMCLK_VAL" | grep -oE '[0-9]+' | head -1)

        printf "Display adapter %d\t\n" "$i"
        [[ -n "$GPU_NAME_OUT" ]]      && field "Name"             "$GPU_NAME_OUT"
        field "Board Manufacturer" "Unknown"
        [[ -n "$GPU_MEMSIZE_OUT" ]]   && field "Memory size"      "$GPU_MEMSIZE_OUT"
        [[ -n "$GPU_MEMTYPE_OUT" ]]   && field "Memory type"      "$GPU_MEMTYPE_OUT"
        [[ -n "$GPU_CORECLK_NUM" ]]   && field "Core clock"       "${GPU_CORECLK_NUM} MHz"
        [[ -n "$GPU_MEMCLK_NUM" ]]    && field "Memory clock"     "${GPU_MEMCLK_NUM} MHz"
        printf "\n"
    done
    printf "\n\n"
fi

# ---------------------------------------------------------------------------
# Software section (OS info)
# The PHP parser looks for "Windows Version" in this section.
# cpu-x runs on Linux; we emit the Linux OS name in that field so the
# parser can still populate SystemInfo['windows'] with something meaningful.
# ---------------------------------------------------------------------------
printf "Software\n"
sep
printf "\n"
# Build OS string from cpu-x data
if [[ -n "${SYS_OS_NAME:-}" && -n "${SYS_OS_KERNEL:-}" ]]; then
    field "Windows Version" "${SYS_OS_NAME} (${SYS_OS_KERNEL})"
elif [[ -n "${SYS_OS_NAME:-}" ]]; then
    field "Windows Version" "${SYS_OS_NAME}"
else
    field "Windows Version" "Linux"
fi
printf "\n\n\n"
