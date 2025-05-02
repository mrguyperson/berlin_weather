
# Initialize renv and install packages using pak + DESCRIPTION
if (!file.exists("renv.lock")) {
  renv::init()
  # install.packages("pak", repos = sprintf("https://r-lib.github.io/p/pak/stable/%s/%s/%s", .Platform$pkgType, R.Version()$os, R.Version()$arch))
  # renv::install("pak")
  options(
    # renv.config.pak.enabled = TRUE,
    repos = c(RSPM = "https://packagemanager.posit.co/cran/2025-04-22")
  )
  pkgs <- c(
    "here",
    "httpgd",
    "tidyverse",
    "targets",
    "readxl", 
    "tarchetypes",
    "showtext", 
    "openmeteo",
    "ggborderline",
    "gt",
    "leaflet"
  )
  renv::install(pkgs)
  renv::snapshot()
} else {
  renv::restore()
}