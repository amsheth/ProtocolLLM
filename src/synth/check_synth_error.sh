#/bin/bash

set -e

if [ ! -f reports/synthesis.log ] || grep -iwq -f synth-error-codes reports/synthesis.log; then
    echo -e "\033[0;31mSynthesis failed \033[0m"
    exit 1
fi

if [ ! -f reports/timing.rpt ] || ! grep -iq 'slack (MET)' reports/sta.log; then
   echo -e "\033[0;31mTiming Not Met \033[0m"
   exit 1
else
   echo -e "\033[0;32mTiming Met \033[0m"
fi

if grep -iq 'warning' reports/synthesis.log; then
    echo -e "\033[0;33mSynthesis finished with warnings \033[0m"
    exit 69
else
    echo -e "\033[0;32mSynthesis Successful \033[0m"
    exit 0
fi
