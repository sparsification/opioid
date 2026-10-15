#!/bin/bash
set -euo pipefail

# Always run from this folder
here="$(cd -- "$(dirname "$0")" && pwd)"
cd "$here"

# Use your user R library if set up there
export R_LIBS_USER="${R_LIBS_USER:-$HOME/R/x86_64-pc-linux-gnu-library/4.3}"

# Sanity checks
need=(
  "simulateToGetOD_IM.R"
  "models/modelWithSimpleVentilatoryCollapse_IM/delaymymod.so"
  "plot_combine_2mg_AND_EVZIO/Plot_Combined_Generic_EVZIO2mg.R"
)
for f in "${need[@]}"; do
  [[ -e "$f" ]] || { echo "Missing required file: $f"; exit 1; }
done

echo "==> Running typical patient (2001) simulations for both formulations…"
./Simulate_Overdose_Rmodel_HC_typical.sh
./Simulate_Overdose_Rmodel_LC_typical.sh
./Simulate_Overdose_Rmodel_HF_typical.sh
./Simulate_Overdose_Rmodel_LF_typical.sh

echo "==> Done. Check output_individual_patients/ for generated CSVs/plots."
