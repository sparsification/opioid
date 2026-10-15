#!/bin/bash
set -euo pipefail

SCENARIO=${1:-}
ANTAGONIST=${2:-}
PATIENTIDX=${3:-2001}

if [[ -z "${SCENARIO}" || -z "${ANTAGONIST}" ]]; then
  echo "Usage: ./run_scenario_final.sh <scenario> <antagonist> [patient_id]"
  echo "  scenario: 0=normal, 1=sleep, 2=high_gas, 3=mechanical"
  echo "  antagonist: Generic | EVZIO"
  exit 1
fi

# Locate base Figure_7 (relative to this scenarios/ folder)
HERE="$(cd -- "$(dirname "$0")" && pwd)"
BASE_DIR="$(cd "${HERE}/../base/Figure_7" && pwd)"
MODEL_DIR="${BASE_DIR}/models/modelWithSimpleVentilatoryCollapse_IM"

REQUIRED=(
  "${BASE_DIR}/simulateToGetOD_IM.R"
  "${MODEL_DIR}/delaypars.R"
  "${MODEL_DIR}/delaystates.R"
)
for f in "${REQUIRED[@]}"; do
  [[ -e "$f" ]] || { echo "Missing required file: $f"; exit 1; }
done

case "${SCENARIO}" in
  0) OUTTAG="scenario0_normal";;
  1) OUTTAG="scenario1_sleep";;
  2) OUTTAG="scenario2_highgas";;
  3) OUTTAG="scenario3_mechanical";;
  *) echo "Invalid scenario: ${SCENARIO}"; exit 1;;
esac

echo "================================================"
echo "Running Scenario ${SCENARIO} (${OUTTAG}) with ${ANTAGONIST}  (patient ${PATIENTIDX})"
echo "Base at: ${BASE_DIR}"
echo "================================================"

# Backups
cp -f "${MODEL_DIR}/delaypars.R"   "${MODEL_DIR}/delaypars.R.bak"
cp -f "${MODEL_DIR}/delaystates.R" "${MODEL_DIR}/delaystates.R.bak"

# Helper sed (case-insensitive key match, replace entire assignment)
# Usage: set_assign <file> <name_regex> <value>
set_assign () {
  local file="$1" name_rx="$2" value="$3"
  # Replace if exists (start-of-line or leading spaces), else append
  if grep -qiE "^[[:space:]]*${name_rx}[[:space:]]*=" "$file"; then
    sed -i -E "s|^([[:space:]]*${name_rx}[[:space:]]*=).*|\1 ${value}|" "$file"
  else
    echo "${name_rx} = ${value}" >> "$file"
  fi
}

# Scenario-specific edits
case "${SCENARIO}" in
  0)
    echo "[Normal] No parameter changes."
    ;;

  1)
    echo "[Sleep] ~30% reductions in ventilatory drive and chemosensitivity."
    set_assign "${MODEL_DIR}/delaypars.R" "(?i)Wmax" "4.63"
    set_assign "${MODEL_DIR}/delaypars.R" "(?i)Bco2" "45"
    set_assign "${MODEL_DIR}/delaypars.R" "(?i)c1o2" "11.9"
    set_assign "${MODEL_DIR}/delaypars.R" "(?i)Aco2" "-21"
    ;;

  2)
    echo "[High Gas] Inspired CO2=7% (~50 mmHg), O2=50% (~357 mmHg)."
    # Inspired gases belong in delaypars.R; use common name patterns P_i_co2, P_i_o2
    set_assign "${MODEL_DIR}/delaypars.R" "(?i)P_[iI]_co2" "50"
    set_assign "${MODEL_DIR}/delaypars.R" "(?i)P_[iI]_o2"  "357"
    ;;

  3)
    echo "[Mechanical] Attempt to fix expired/alveolar CO2 at 50 mmHg (requires ODE clamp)."
    # These soften chemosensitivity; real clamp still needs ODE change.
    set_assign "${MODEL_DIR}/delaypars.R" "(?i)Aco2" "0"
    set_assign "${MODEL_DIR}/delaypars.R" "(?i)c1o2" "0"
    # Set initial alveolar CO2 to 50 mmHg (note: without ODE clamp it will evolve)
    set_assign "${MODEL_DIR}/delaystates.R" "(?i)P_[aA]_co2" "50"
    echo "WARNING: Scenario 3 needs ODE-level clamp to truly hold P_A_co2=50 mmHg."
    ;;

esac

# Run simulation in base (carfentanil high dose to match your example)
echo "==> Running simulateToGetOD_IM.R in ${BASE_DIR}"
cd "${BASE_DIR}"
Rscript simulateToGetOD_IM.R \
  -a "${ANTAGONIST}" \
  -i "${PATIENTIDX}" \
  -p "chronic" \
  -o "carfentanil" \
  -m "yes" \
  -q "yes" \
  -c ".02187"

# Collect outputs into scenarios/out/
OUT_DIR="${HERE}/out/${OUTTAG}_${ANTAGONIST}"
mkdir -p "${OUT_DIR}"

# Typical places the base script writes to:
if [[ -d "${BASE_DIR}/outputs/results/Im_plot_${ANTAGONIST}" ]]; then
  cp -f ${BASE_DIR}/outputs/results/Im_plot_${ANTAGONIST}/carfentanil_0.02187_ypred*.csv "${OUT_DIR}/" 2>/dev/null || true
fi
if [[ -d "${BASE_DIR}/outputs/Review_naloxone_formulation_${ANTAGONIST}_conc_0.02187_ligand_carfentanil_patient_chronic" ]]; then
  cp -f ${BASE_DIR}/outputs/Review_naloxone_formulation_${ANTAGONIST}_conc_0.02187_ligand_carfentanil_patient_chronic/*.csv "${OUT_DIR}/" 2>/dev/null || true
fi
# Also sweep base's default per-patient folder if used
if [[ -d "${BASE_DIR}/output_individual_patients" ]]; then
  cp -f ${BASE_DIR}/output_individual_patients/*.csv "${OUT_DIR}/" 2>/dev/null || true
fi

# Restore backups
mv -f "${MODEL_DIR}/delaypars.R.bak"   "${MODEL_DIR}/delaypars.R"
mv -f "${MODEL_DIR}/delaystates.R.bak" "${MODEL_DIR}/delaystates.R"

echo "================================================"
echo "Scenario ${SCENARIO} (${OUTTAG}) with ${ANTAGONIST} complete."
echo "Outputs -> ${OUT_DIR}"
ls -la "${OUT_DIR}" 2>/dev/null || true
echo "================================================"
