#!/usr/bin/env Rscript

# === Config =================================================================
MODEL_DIR <- "models/modelWithSimpleVentilatoryCollapse_IM"
SO_PATH   <- file.path(MODEL_DIR, "delaymymod_partial.so")  # partial DLL
PARS_R    <- file.path(MODEL_DIR, "delaypars.R")
STATES_R  <- file.path(MODEL_DIR, "delaystates.R")

# Efficacy (0..1). 1 = full agonist (nadir→0). <1 = partial (plateau).
EPS <- 0.50
OUT_DIR <- sprintf("dose_response_outputs_eps_%s",
                   gsub("\\.", "p", sprintf("%.2f", EPS)))

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
if (length(miss)) stop("Missing required files:\n- ", paste(miss, collapse = "\n- "), call. = FALSE)

suppressPackageStartupMessages({ library(deSolve) })

# === Load model ==============================================================
source(PARS_R)
source(STATES_R)

# Wall-clock guard; start the clock NOW
pars["timeout"]   <- 3600
pars["starttime"] <- as.numeric(Sys.time())

# Room-air baseline
pars["P_I_co2"]  <- 0
states["P_I_o2"] <- 149
states["P_A_co2"] <- 40.28

# Infusion schedule (total delivered = FIV over [0, max(TIMES)])
pars["Infu_t"] <- max(TIMES)   # set to 1 for bolus-like delivery

# Ensure NO naloxone
nlz <- c("D","NT1","NT2","PlasmaN","N","CBR")
nlz <- nlz[nlz %in% names(states)]
if (length(nlz)) states[nlz] <- 0

# Provide Eps as the LAST parameter (DLL expects 107 parms incl. Eps)
if (!"Eps" %in% names(pars)) pars <- c(pars, Eps = EPS) else pars["Eps"] <- EPS

# Load the shared object
if (!is.loaded("derivs")) dyn.load(SO_PATH)

# === Helpers ================================================================
get_mv <- function(out) {
  cn <- colnames(out)
  pat <- paste(c("^MV$", "^MV_?L_?min$", "Minute.?Vent", "Venti.*L.?/min"), collapse="|")
  idx <- grep(pat, cn, ignore.case = TRUE)
  if (length(idx) >= 1) return(out[, idx[1]])
  mv_idx <- 1 + length(states) + 1  # time + states + first yout
  if (mv_idx <= ncol(out)) return(out[, mv_idx])
  stop("Could not locate MV column. Columns:\n", paste(" -", cn, collapse = "\n"), call. = FALSE)
}

run_one <- function(dose_mg) {
  st <- states
  pr <- pars

  # Deliver total dose via FIV state
  if (!"FIV" %in% names(st)) stop("State 'FIV' not found in delaystates.R", call. = FALSE)
  st["FIV"] <- dose_mg

  # Keep naloxone off
  if (length(nlz)) st[nlz] <- 0

  out <- ode(
    y = st, times = TIMES,
    func = "derivs", parms = pr,
    dllname = "delaymymod_partial", initfunc = "initmod",
    rtol = RTOL, atol = ATOL, maxsteps = MAXSTEPS,
    lags = 1,              # <<<<<<<<<<<<<<<<<<<<<<<<<< enable delay history
    nout = 24
  )

  mv <- get_mv(out)
  nadir <- suppressWarnings(min(mv, na.rm = TRUE))
  t_nadir <- out[which.min(mv), "time"]
  list(out = out, mv = mv, nadir = nadir, t_nadir = t_nadir)
}

# === Run sweep ==============================================================
if (!dir.exists(OUT_DIR)) dir.create(OUT_DIR, recursive = TRUE)
nadirs <- numeric(length(DOSES)); tmins <- numeric(length(DOSES))

cat(sprintf("==> Fentanyl dose-response (no naloxone), Eps=%.2f …\n", EPS))
for (i in seq_along(DOSES)) {
  d <- DOSES[i]
  cat(sprintf("  • Dose = %.2f mg … ", d))
  res <- run_one(d)
  nadirs[i] <- res$nadir; tmins[i] <- res$t_nadir
  out_csv <- file.path(OUT_DIR, sprintf("dose_%0.2fmg.csv", d))
  suppressWarnings(utils::write.csv(res$out, out_csv, row.names = FALSE))
  cat(sprintf("nadir = %.2f L/min at %.0f s → %s\n", nadirs[i], tmins[i], basename(out_csv)))
}

summary_df <- data.frame(Dose_mg = DOSES,
                         MV_Nadir_L_min = nadirs,
                         Time_to_Nadir_s = tmins)
utils::write.csv(summary_df, file.path(OUT_DIR, "dose_response_summary.csv"), row.names = FALSE)

# === Plot ===================================================================
pdf(file.path(OUT_DIR, sprintf("dose_response_curve_eps_%0.2f.pdf", EPS)), width = 7, height = 5)
plot(DOSES, nadirs, type="b", pch=19, lwd=2, col="blue",
     xlab="Fentanyl Dose (mg)", ylab="Minute Ventilation Nadir (L/min)",
     main=sprintf("Fentanyl Dose-Response (No Naloxone)  [Eps=%.2f]", EPS),
     ylim=c(0, 7))
abline(h=0, lty=2); grid()
text(DOSES, nadirs + 0.2, labels = sprintf("%.2f", nadirs), cex = 0.8)
dev.off()

cat("\n==> Done. Results in:", normalizePath(OUT_DIR), "\n")
print(summary_df)
