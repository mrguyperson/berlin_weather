#!/usr/bin/env Rscript

# Current-main baseline: 60.55226824%. Floor rounded down to 0.1 percentage point.
# Raise the floor through reviewed changes; do not lower it merely to pass CI.
minimum_coverage <- 60.5

source_files <- list.files("R", pattern = "[.]R$", full.names = TRUE, recursive = TRUE)
test_files <- list.files("tests/testthat", pattern = "^test-.*[.]R$", full.names = TRUE)

if (length(source_files) == 0L || length(test_files) == 0L) {
    stop("Coverage requires R/ source files and tests/testthat/ test files.")
}

coverage <- covr::file_coverage(
    source_files = source_files,
    test_files = test_files
)
measured_coverage <- covr::percent_coverage(coverage)

cat(sprintf(
    "R/ line coverage: %.2f%%; required minimum: %.1f%%\n",
    measured_coverage,
    minimum_coverage
))

if (!is.finite(measured_coverage) || measured_coverage < minimum_coverage) {
    stop("R/ line coverage is below the committed minimum.", call. = FALSE)
}
