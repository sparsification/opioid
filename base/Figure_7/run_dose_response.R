#!/usr/bin/env Rscript

# === Config =================================================================
MODEL_DIR <- "models/modelWithSimpleVentilatoryCollapse_IM"
SO_PATH   <- file.path(MODEL_DIR, "delaymymod.so")
PARS_R    <- file.path(MODEL_DIR, "delaypars.R")
STATES_R  <- file.path(MODEL_DIR, "delaystates.R")
OUT_DIR   <- "dose_response_outputs"

# Doses (mg) and simulation time grid
DOSES <- c(0, 0.2, 0.4, 0.8, 1.6, 3.2)
TIMES <- seq(0, 900, by = 1)   # 15 min @ 1 s

# Solver tolerances / steps
RTOL <- 1e-8
ATOL <- 1e-8
MAXSTEPS <- 1e7

# === Checks =================================================================
need <- c(SO_PATH, PARS_R, STATES_R)
miss <- need[!file.exists(need)]
if (length(miss)) {
  stop("Missing required files:\n- ", paste(miss, collapse = "\n- "), call. = FALSE)
}

suppressPackageStartupMessages({
  library(deSolve)
})

# === Load model ==============================================================
source(PARS_R)
source(STATES_R)

# Keep the C timeout from tripping; start clock at 0
pars["timeout"]   <- 3600
pars["starttime"] <- 0

# Room-air baseline + make total delivered == FIV over [0, max(TIMES)]
pars["P_I_co2"] <- 0
states["P_I_o2"] <- 149
states["P_A_co2"] <- 40.28
pars["Infu_t"] <- max(TIMES)  # <— so total delivered equals FIV

# Ensure NO naloxone
nlz <- c("D","NT1","NT2","PlasmaN","N","CBR")
nlz <- nlz[nlz %in% names(states)]
if (length(nlz)) states[nlz] <- 0

# Load the shared object if not already
if (!is.loaded("derivs")) dyn.load(SO_PATH)

# === Helpers ================================================================
get_mv <- function(out) {
  # 1) Try name-match (if your C registers names for yout)
  cn <- colnames(out)
  pat <- paste(c("^MV$", "^MV_?L_?min$", "Minute.?Vent", "Venti.*L.?/min"), collapse="|")
  idx <- grep(pat, cn, ignore.case = TRUE)
  if (length(idx) >= 1) return(out[, idx[1]])

  # 2) Fallback by position: time + (#states) + first yout (yout[0])
  mv_idx <- 1 + length(states) + 1  # time is col 1
  if (mv_idx <= ncol(out)) return(out[, mv_idx])

  stop("Could not locate MV column. Columns:\n", paste(" -", cn, collapse = "\n"), call. = FALSE)
}

run_one <- function(dose_mg) {
  st <- states
  pr <- pars

  # Constant-rate infusion using FIV (total delivered over the window = FIV)
  if (!"FIV" %in% names(st)) stop("State 'FIV' not found in delaystates.R", call. = FALSE)
  st["FIV"] <- dose_mg

  # Keep naloxone off (already zeroed globally, but safe to enforce)
  if (length(nlz)) st[nlz] <- 0

  out <- ode(y = st, times = TIMES,
             func = "derivs", parms = pr,
             dllname = "delaymymod", initfunc = "initmod",
             rtol = RTOL, atol = ATOL, maxsteps = MAXSTEPS,
             nout = 24)  # yout[0..23] in your C

  mv <- get_mv(out)                 # MV in L/min
  nadir <- suppressWarnings(min(mv, na.rm = TRUE))
  t_nadir <- out[which.min(mv), "time"]

  list(out = out, mv = mv, nadir = nadir, t_nadir = t_nadir)
}

# === Run sweep ==============================================================
if (!dir.exists(OUT_DIR)) dir.create(OUT_DIR, recursive = TRUE)

nadirs <- numeric(length(DOSES))
tmins  <- numeric(length(DOSES))

cat("==> Running fentanyl dose-response sweep (no naloxone)…\n")
for (i in seq_along(DOSES)) {
  d <- DOSES[i]
  cat(sprintf("  • Dose = %.2f mg … ", d))
  res <- run_one(d)
  nadirs[i] <- res$nadir
  tmins[i]  <- res$t_nadir

  out_csv <- file.path(OUT_DIR, sprintf("dose_%0.2fmg.csv", d))
  suppressWarnings(utils::write.csv(res$out, out_csv, row.names = FALSE))
  cat(sprintf("nadir = %.2f L/min at %.0f s → %s\n", nadirs[i], tmins[i], basename(out_csv)))
}

summary_df <- data.frame(Dose_mg = DOSES,
                         MV_Nadir_L_min = nadirs,
                         Time_to_Nadir_s = tmins)
utils::write.csv(summary_df,
                 file.path(OUT_DIR, "dose_response_summary.csv"),
                 row.names = FALSE)

# === Plot ===================================================================
pdf(file.path(OUT_DIR, "dose_response_curve.pdf"), width = 7, height = 5)
plot(DOSES, nadirs, type="b", pch=19, lwd=2, col="blue",
     xlab="Fentanyl Dose (mg)", ylab="Minute Ventilation Nadir (L/min)",
     main="Fentanyl Dose-Response (No Naloxone)", ylim=c(0, 7))
abline(h=0, lty=2)
grid()
text(DOSES, nadirs + 0.2, labels = sprintf("%.2f", nadirs), cex = 0.8)
dev.off()

cat("\n==> Done. Results in:", normalizePath(OUT_DIR), "\n")
print(summary_df)
