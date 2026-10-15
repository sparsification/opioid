#!/usr/bin/env Rscript
suppressPackageStartupMessages(library(deSolve))

## Paths
MODEL_DIR <- "models/modelWithSimpleVentilatoryCollapse_IM"
SO_PATH   <- file.path(MODEL_DIR, "delaymymod.so")
PARS_R    <- file.path(MODEL_DIR, "delaypars.R")
STATES_R  <- file.path(MODEL_DIR, "delaystates.R")

## Load inputs
stopifnot(file.exists(SO_PATH), file.exists(PARS_R), file.exists(STATES_R))
source(PARS_R); source(STATES_R)
if (!is.loaded("derivs")) dyn.load(SO_PATH)

## Baseline: room air, awake, no naloxone
pars["P_I_co2"]   <- 0
pars["W"]         <- 6.62
pars["Wmax"]      <- 6.62
states["P_I_o2"]  <- 149
states["P_A_co2"] <- 40.28
nlz <- intersect(c("D","NT1","NT2","PlasmaN","N","CBR"), names(states)); states[nlz] <- 0

## Defeat C-side time guard used in your file (time(NULL) - starttime > timeout)
pars["starttime"] <- as.numeric(Sys.time())  # epoch seconds
pars["timeout"]   <- 1e9                     # huge window
cat("timeout =", unname(pars["timeout"]), " starttime =", unname(pars["starttime"]), "\n")

## No fentanyl; short horizon
states["FIV"] <- 0
times <- seq(0, 120, by = 1)

## Tolerances (relaxed per DLSODA message)
RTOL <- 1e-5; ATOL <- 1e-7

## Your C sets yout[0..23]; name yout[0] = MV (L/min)
NOUT  <- 24
OUTN  <- c("MV", "residualWakefulnessDrive", "chemoreflex_drive",
           "Qb_Lmin", "Qt_Lmin", "PaO2", "PaCO2", "PbO2", "PbCO2",
           "OpioidPlasma", "AntagPlasma", "OpioidEffect", "AntagEffect_nM",
           "OpioidBound", "AntagBound", "Q_Lmin",
           "koutC","k12C","k13C","k21C","k31C","VPC","SaO2_pct","V1C")

## Use dede() because the model calls lagvalue/pastvalue
out <- dede(y = states, times = times,
            func = "derivs", parms = pars,
            dllname = "delaymymod", initfunc = "initmod",
            rtol = RTOL, atol = ATOL,
            nout = NOUT, outnames = OUTN)

stopifnot("MV" %in% colnames(out))
mv <- out[, "MV"]
cat("Sanity MV head (L/min):", paste(round(head(mv, 5), 2), collapse = ", "), "\n")
cat("Sanity MV tail (L/min):", paste(round(tail(mv, 5), 2), collapse = ", "), "\n")
