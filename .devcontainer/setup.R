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
    "leaflet",
    "bigrquery"
  )

renv::init()
renv::install(pkgs, ask = FALSE)
renv::snapshot(prompt = FALSE)