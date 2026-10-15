#!/bin/bash

# Run only the typical patient (patient 2001) for both formulations
FORMULATION=(Generic EVZIO)
PATIENTIDX=2001  # The typical patient

# Run for each formulation
for ANTAGONIST in "${FORMULATION[@]}"; do
    echo "Running Low Fentanyl simulation for patient $PATIENTIDX with $ANTAGONIST"
    
    Rscript simulateToGetOD_IM.R \
        -a "$ANTAGONIST" \
        -i "$PATIENTIDX" \
        -p "chronic" \
        -o "fentanyl" \
        -m "yes" \
        -q "yes" \
        -c "1.625"  # Low fentanyl dose
done
