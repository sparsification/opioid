# Task 1
## Reproducing Figure 7A

From `opioid/base/Figure_7`, run `./run_typical_all.sh` to generate typical-patient (2001) outputs for all four drug/dose conditions. Then run `./make_fig7A.sh` to assemble Figure 7A (panels A–C from real outputs; panel D uses dummy population bars).


# Task 2 

## Base case (already in `base/`)

### Three scenarios to add

1. **Scenario 1 — Sleep**
   Reduce ventilatory drive & chemosensitivity by \~30–50% (e.g., `Wmax`, `Aco2`, `Bco2`, `c1o2`) in `models/modelWithSimpleVentilatoryCollapse_IM/delaypars.R`.

2. **Scenario 2 — High Gas (FiCO₂=7%, FiO₂=50%)**
   Set **inspired** gases in `delaypars.R` (match repo names/case, e.g., `P_i_co2`, `P_i_o2`):
   7% CO₂ → \~50 mmHg, 50% O₂ → \~357 mmHg via $P = F_i \times (P_B - P_{H_2O})\approx F_i\times 713$.

3. **Scenario 3 — Mechanical (expired/alveolar CO₂ fixed = 50 mmHg)**
   Requires **clamping the alveolar CO₂ state** in the ODEs (C/R layer): set its derivative to 0 and its value to 50 mmHg each step; changing only initial/state files won’t hold it fixed.

## How to run scenarios

Use your wrapper (examples below); it **backs up and restores** the model files and writes outputs per-scenario:

```bash
# Usage: ./run_scenario_final.sh <scenario> <antagonist> [patient_id]
#          0=normal, 1=sleep, 2=high_gas, 3=mechanical; antagonist: Generic|EVZIO

./run_scenario_final.sh 0 Generic       # Baseline → output_individual_patients/
./run_scenario_final.sh 1 Generic       # Sleep    → output_individual_patients_scenario1/
./run_scenario_final.sh 2 EVZIO         # HighGas  → output_individual_patients_scenario2/
./run_scenario_final.sh 3 Generic       # Mechanical (needs ODE clamp) → scenario3/
```

**Notes**

* Keep variable **names/case** exactly as in the repo (`delaypars.R` for inspired gases & drive).
* Scenario 3 won’t be valid until the ODE clamp is implemented (sed edits alone only change initial values).
