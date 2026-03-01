<?php
/**
 * validate.php — Feed a converted cpu-z text file through HardwareParser_CPUZ_Text
 * and verify that all required fields are present and non-empty.
 *
 * Usage:
 *   php tests/validate.php <path/to/converted.txt> [--verbose]
 *
 * Exit codes:
 *   0  all checks passed
 *   1  one or more checks failed
 *   2  bad invocation / file not found
 */

// ---------------------------------------------------------------------------
// Stub for HardwareManufacturer::get() — the real class lives outside the repo.
// We just return the raw string so the parser does not blow up on missing deps.
// ---------------------------------------------------------------------------
class HardwareManufacturer {
    public static function get(string $category, string $name): string {
        return trim($name);
    }
}

// ---------------------------------------------------------------------------
// Bootstrap
// ---------------------------------------------------------------------------
$verbose = in_array('--verbose', $argv, true);
$args    = array_filter($argv, fn($a) => $a !== '--verbose');
$args    = array_values($args);

if (count($args) < 2) {
    fwrite(STDERR, "Usage: php tests/validate.php <converted.txt> [--verbose]\n");
    exit(2);
}

$file = $args[1];

if (!file_exists($file)) {
    fwrite(STDERR, "File not found: $file\n");
    exit(2);
}

require_once __DIR__ . '/../parser/HardwareParser_CPUZ_Text.php';

// ---------------------------------------------------------------------------
// Run parser
// ---------------------------------------------------------------------------
$parser = new HardwareParser_CPUZ_Text($file);

if ($parser->error) {
    fwrite(STDERR, "Parser constructor errors: " . implode(', ', $parser->error) . "\n");
    exit(1);
}

$versionOk = $parser->checkVersion();
$parser->parseFile();
$data = $parser->getData();

// ---------------------------------------------------------------------------
// Validation rules
// Each rule: [ 'section', 'key' (dot-notation for nested), 'description' ]
// ---------------------------------------------------------------------------

$PASS = 0;
$FAIL = 1;

$checks  = [];
$results = [];

/**
 * Assert a value is set and non-empty; record the result.
 */
function check(string $desc, mixed $value, bool $verbose): bool {
    $ok = (isset($value) && $value !== '' && $value !== null);
    $status = $ok ? 'PASS' : 'FAIL';
    $display = is_string($value) ? $value : json_encode($value);
    if ($verbose || !$ok) {
        printf("  [%s] %s%s\n", $status, $desc, $ok ? " => $display" : '');
    }
    return $ok;
}

$allPassed = true;

// ---------------------------------------------------------------------------
// 1. Version check
// ---------------------------------------------------------------------------
echo "--- Version\n";
$r = $versionOk;
printf("  [%s] CPU-Z version >= 2.01.0\n", $r ? 'PASS' : 'FAIL');
if (!$r) $allPassed = false;

// ---------------------------------------------------------------------------
// 2. CPU — at least one socket block
// ---------------------------------------------------------------------------
echo "--- CPU (Processors Information)\n";

if (empty($data['CPU'])) {
    echo "  [FAIL] No CPU data found\n";
    $allPassed = false;
} else {
    foreach ($data['CPU'] as $idx => $cpu) {
        echo "  Socket $idx:\n";
        $required = [
            'name'         => 'Name',
            'codename'     => 'Codename',
            'specification'=> 'Specification',
            'socket'       => 'Package (socket)',
            'cores'        => 'Number of cores',
            'threads'      => 'Number of threads',
            'multiplier'   => 'Multiplier',
            'instructions' => 'Instructions sets',
        ];
        foreach ($required as $key => $label) {
            $v = $cpu[$key] ?? null;
            $r = check("    $label", $v, $verbose);
            if (!$r) $allPassed = false;
        }
    }
}

// ---------------------------------------------------------------------------
// 3. Mainboard (DMI)
// ---------------------------------------------------------------------------
echo "--- Mainboard (DMI)\n";
$mb = $data['Mainboard'] ?? [];
foreach (['vendor' => 'vendor', 'model' => 'model'] as $key => $label) {
    $r = check("  $label", $mb[$key] ?? null, $verbose);
    if (!$r) $allPassed = false;
}

// Southbridge / chipset is optional in the PHP parser output
// (it may come back empty if not in the source), report informational only
if ($verbose) {
    $chipset = $mb['chipset'] ?? null;
    printf("  [INFO] chipset => %s\n", $chipset ?: '(empty)');
}

// ---------------------------------------------------------------------------
// 4. RAM — if the section exists, validate each DIMM
// ---------------------------------------------------------------------------
echo "--- Memory SPD\n";
if (empty($data['RAM'])) {
    echo "  [INFO] No RAM SPD data (case 2 has no sticks — acceptable)\n";
} else {
    foreach ($data['RAM'] as $idx => $dimm) {
        echo "  DIMM #$idx:\n";
        $required = [
            'memory_type'  => 'Memory type',
            'socket'       => 'Module format',
            'manufacturer' => 'Module Manufacturer(ID)',
            'size'         => 'Size (MBytes)',
            'max_bandwidth'=> 'Max bandwidth',
            'serial'       => 'Part number',
        ];
        foreach ($required as $key => $label) {
            $v = $dimm[$key] ?? null;
            $r = check("    $label", $v, $verbose);
            if (!$r) $allPassed = false;
        }
    }
}

// ---------------------------------------------------------------------------
// 5. GPU — at least one display adapter
// ---------------------------------------------------------------------------
echo "--- Display Adapters\n";
if (empty($data['GPU'])) {
    echo "  [FAIL] No GPU data found\n";
    $allPassed = false;
} else {
    foreach ($data['GPU'] as $idx => $gpu) {
        echo "  Adapter $idx:\n";
        $required = [
            'name'        => 'Name',
            'memory'      => 'Memory size',
            'memory_type' => 'Memory type',
            'core_clock'  => 'Core clock',
            'memory_clock'=> 'Memory clock',
        ];
        foreach ($required as $key => $label) {
            $v = $gpu[$key] ?? null;
            $r = check("    $label", $v, $verbose);
            if (!$r) $allPassed = false;
        }
    }
}

// ---------------------------------------------------------------------------
// 6. SystemInfo (Software / OS)
// ---------------------------------------------------------------------------
echo "--- Software (SystemInfo)\n";
$si = $data['SystemInfo'] ?? [];
$r = check("  Windows Version (OS)", $si['windows'] ?? null, $verbose);
if (!$r) $allPassed = false;

// ---------------------------------------------------------------------------
// Summary
// ---------------------------------------------------------------------------
echo "\n";
if ($allPassed) {
    echo "RESULT: PASS — all required fields present\n";
    exit(0);
} else {
    echo "RESULT: FAIL — one or more required fields missing\n";
    exit(1);
}
