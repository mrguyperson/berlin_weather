  options(
    # renv.config.pak.enabled = TRUE,
    # repos = c(RSPM = "https://packagemanager.posit.co/cran/2025-04-22")
  )
  pkgs <- c(
    "here",
    "nx10/httpgd",
    "tidyverse",
    "targets",
    "readxl", 
    "tarchetypes",
    "showtext", 
    "openmeteo",
    "gt",
    "leaflet"
  )


# Initialize renv and install packages using pak + DESCRIPTION
if (!file.exists("renv.lock")) {
  renv::init()
  renv::install(pkgs)
  renv::snapshot()
} else {
  renv::restore()
}