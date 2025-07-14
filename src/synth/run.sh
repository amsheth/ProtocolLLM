#!/bin/bash

set -e

exec > reports/metrics.txt

TIMING_FILE="reports/timing.rpt"
POWER_FILE="reports/sta.log"
SYNTH_FILE="reports/synthesis.log"
LINT_FILE="reports/lint.log"

#----------------------------
# Linting Check
#----------------------------
echo "Lint Check:"

# Lint Errors
if grep -iE "error|undeclared|syntax" "$LINT_FILE" > /dev/null; then
    echo "❌ Lint errors found:"
    grep -iE "error|undeclared|syntax" "$LINT_FILE"
    exit 1
else
    echo "✅ No lint errors."
fi

# Lint Warnings
if grep -i "warning" "$LINT_FILE" > /dev/null; then
    echo "⚠️  Lint warnings found:"
    grep -i "warning" "$LINT_FILE"
else
    echo "✅ No lint warnings."
fi

echo ""


#----------------------------
# Synthesis Error Check
#----------------------------
echo "Synthesis Check:"
SYNTH_LOG="reports/synthesis.log"

if grep -iE "ERROR: Found|failed|syntax|unresolved" "$SYNTH_LOG" > /dev/null; then
    echo "❌ Synthesis errors found:"
    grep -iE "error|failed|syntax|unresolved" "$SYNTH_LOG"
    exit 1
else
    echo "✅ No synthesis errors."
fi
echo ""


#----------------------------
# Timing Check
#----------------------------
echo -n "Timing Met: "
if grep -iE "negative slack|timing not met|violation" "$TIMING_FILE" > /dev/null; then
    echo "NO"
    grep -iE "slack.*[-][0-9]" "$TIMING_FILE" | head -n 1
else
    echo "YES"
fi

#----------------------------
# Power Extraction
#----------------------------
echo -n "Total Power: "
POWER_VALUE=$(grep -A 1 -i "^Total" "$POWER_FILE" | \
              grep -oE "[0-9]+\.[0-9]+e[-+][0-9]+" | tail -n 1)

if [ -n "$POWER_VALUE" ]; then
    echo "$POWER_VALUE W"
else
    echo "Not found"
fi

#----------------------------
# Area Extraction
#----------------------------
echo -n "Chip Area: "
AREA_VALUE=$(grep "Chip area for module" "$SYNTH_FILE" | awk -F': ' '{printf "%.0f\n", $2}')

if [ -n "$AREA_VALUE" ]; then
    echo "$AREA_VALUE µm²"
else
    echo "Not found"
fi
