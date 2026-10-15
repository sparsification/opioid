#!/bin/bash
set -euo pipefail

# Always run from this folder
here="$(cd -- "$(dirname "$0")" && pwd)"
cd "$here"

# Use your user R library if set up there
export R_LIBS_USER="${R_LIBS_USER:-$HOME/R/x86_64-pc-linux-gnu-library/4.3}"

# Requirements
need=(
  "plot_combine_2mg_AND_EVZIO/Plot_Combined_Generic_EVZIO2mg.R"
  "population_outputs_2mg_40tsh_delays/CA_IM"
)
for f in "${need[@]}"; do
  [[ -e "$f" ]] || { echo "Missing required file/dir: $f"; exit 1; }
done

# Ensure dummy population CSVs exist (no-op if already there)
if ! ls population_outputs_2mg_40tsh_delays/CA_IM/All_CADo1PKReview_* >/dev/null 2>&1; then
  echo "==> Creating dummy population CA files…"
  Rscript create_dummy_population.R
fi

echo "==> Building Figure 7A panels…"
cd plot_combine_2mg_AND_EVZIO
Rscript Plot_Combined_Generic_EVZIO2mg.R

echo "==> Done. Outputs (if generated):"
ls -la results 2>/dev/null || echo "No results/ folder created by plot script."
