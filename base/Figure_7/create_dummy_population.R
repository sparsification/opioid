# create_dummy_population.R
# Writes minimal 2-row population CSVs expected by Plot_Combined_Generic_EVZIO2mg.R

dir.create("population_outputs_2mg_40tsh_delays/CA_IM", recursive = TRUE, showWarnings = FALSE)

conditions <- list(
  list(dose = "1.625",  drug = "fentanyl"),
  list(dose = "2.965",  drug = "fentanyl"),
  list(dose = "0.012",  drug = "carfentanil"),
  list(dose = "0.02187", drug = "carfentanil")
)

formulations <- c("Generic", "EVZIO")

for (cond in conditions) {
  for (form in formulations) {
    df <- data.frame(
      rowYesCA = c(100, 0),  # % CA with No naloxone vs With naloxone (placeholder)
      emin     = c(100, 0),
      emax     = c(100, 0)
    )
    fn <- sprintf(
      "population_outputs_2mg_40tsh_delays/CA_IM/All_CADo1PKReview_naloxone_formulation_%s_conc_%s_ligand_%s_patient_chronic.csv",
      form, cond$dose, cond$drug
    )
    write.csv(df, fn, row.names = FALSE)
  }
}

cat("Dummy population files created in population_outputs_2mg_40tsh_delays/CA_IM\n")
