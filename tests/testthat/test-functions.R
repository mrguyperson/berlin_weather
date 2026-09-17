library(testthat)

source(testthat::test_path("..", "..", "R", "functions.R"))

test_that("validate_raw_data returns valid input unchanged", {
    response <- data.frame(
        datetime = "2025-01-01 00:00:00",
        hourly_temperature_2m = 12
    )

    expect_identical(validate_raw_data(response), response)
})

test_that("validate_raw_data rejects non-data-frame input", {
    expect_error(
        validate_raw_data(list()),
        "Open-Meteo response must be data-frame-like.",
        fixed = TRUE
    )
})

test_that("validate_raw_data rejects an empty response", {
    response <- data.frame(
        datetime = character(),
        hourly_temperature_2m = numeric()
    )

    expect_error(
        validate_raw_data(response),
        "Open-Meteo response is empty.",
        fixed = TRUE
    )
})

test_that("validate_raw_data rejects a missing required column", {
    response <- data.frame(hourly_temperature_2m = 12)

    expect_error(
        validate_raw_data(response),
        "Open-Meteo response is missing required columns: datetime",
        fixed = TRUE
    )
})

test_that("validate_raw_data requires hourly temperature data", {
    response <- data.frame(datetime = "2025-01-01 00:00:00")

    expect_error(
        validate_raw_data(response),
        "Open-Meteo response is missing required columns: hourly_temperature_2m",
        fixed = TRUE
    )
})
