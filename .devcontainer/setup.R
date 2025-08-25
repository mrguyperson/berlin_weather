pkgs <- c(
    "here",
    "httpgd",
    "tidyverse",
    "targets",
    "readxl", 
    "tarchetypes",
    "showtext", 
    "openmeteo",
    "gt",
    "leaflet"
  )

renv::init()
renv::install(pkgs, ask = FALSE)
renv::snapshot(prompt = FALSE)