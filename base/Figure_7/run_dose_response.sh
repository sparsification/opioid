#!/usr/bin/env Rscript
suppressPackageStartupMessages(library(deSolve))

MODEL_DIR <- "models/modelWithSimpleVentilatoryCollapse_IM"
SO_PATH   <- file.path(MODEL_DIR, "delaymymod.so")
PARS_R    <- file.path(MODEL_DIR, "delaypars.R")
STATES_R  <- file.path(MODEL_DIR, "delaystates.R")
OUT_DIR   <- "dose_response_outputs"

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

## defeat C time guard (your C uses time(NULL) - starttime > timeout)
pars["starttime"] <- as.numeric(Sys.time())
pars["timeout"]   <- 1e9

## doses & time grid (extend to 30 min to let arrest reach 0)
DOSES <- c(0, 0.2, 0.4, 0.8, 1.6, 3.2)   # mg
times <- seq(0, 1800, by = 1)            # 30 min

## tolerances (relaxed to silence DLSODA warning)
RTOL <- 1e-4; ATOL <- 1e-6

## yout names (your C exports 24; yout[0] is MV)
NOUT <- 24
OUTN <- c("MV", "residualWakefulnessDrive", "chemoreflex_drive",
          "Qb_Lmin", "Qt_Lmin", "PaO2", "PaCO2", "PbO2", "PbCO2",
          "OpioidPlasma", "AntagPlasma", "OpioidEffect", "AntagEffect_nM",
          "OpioidBound", "AntagBound", "Q_Lmin",
          "koutC","k12C","k13C","k21C","k31C","VPC","SaO2_pct","V1C")

if (!dir.exists(OUT_DIR)) dir.create(OUT_DIR, recursive = TRUE)

run_one <- function(dose_mg) {
  st <- states; pr <- pars
  stopifnot("FIV" %in% names(st))
  st["FIV"] <- dose_mg
  st[nlz] <- 0
  pr["starttime"] <- as.numeric(Sys.time())  # refresh guard per run

  dede(y = st, times = times,
       func = "derivs", parms = pr,
       dllname = "delaymymod", initfunc = "initmod",
       rtol = RTOL, atol = ATOL,
       nout = NOUT, outnames = OUTN)
}

cat("==> Dose-response sweep (no naloxone)…\n")
nadirs <- numeric(length(DOSES))
tmins  <- numeric(length(DOSES))

for (i in seq_along(DOSES)) {
  d <- DOSES[i]
  cat(sprintf("  • Dose = %.2f mg … ", d))
  out <- run_one(d)
  mv <- out[, "MV"]
  nadirs[i] <- suppressWarnings(min(mv, na.rm = TRUE))
  tmins[i]  <- out[which.min(mv), "time"]
  utils::write.csv(out, file.path(OUT_DIR, sprintf("dose_%0.2fmg.csv", d)), row.names = FALSE)
  cat(sprintf("nadir = %.2f L/min @ %.0fs\n", nadirs[i], tmins[i]))
}

summary_df <- data.frame(Dose_mg = DOSES,
                         MV_Nadir_L_min = nadirs,
                         Time_to_Nadir_s = tmins)
utils::write.csv(summary_df, file.path(OUT_DIR, "dose_response_summary.csv"), row.names = FALSE)

## ASCII title (no Unicode dash) to avoid mbcsToSbcs warnings
pdf(file.path(OUT_DIR, "dose_response_curve.pdf"), width = 7, height = 5)
plot(DOSES, nadirs, type="b", pch=19, lwd=2,
     xlab="Fentanyl dose (mg)", ylab="Minute ventilation nadir (L/min)",
     main="Fentanyl dose-response (no naloxone)", ylim=c(0,7))
abline(h=0, lty=2); grid()
text(DOSES, nadirs + 0.2, labels = sprintf("%.2f", nadirs), cex = 0.8)
dev.off()

cat("\n==> Done. Results in:", normalizePath(OUT_DIR), "\n")
print(summary_df)
