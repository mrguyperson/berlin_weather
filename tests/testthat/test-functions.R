library(testthat)
library(tidyverse)

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

test_that("filter_data derives dates from datetimes", {
    response <- data.frame(
        datetime = as.POSIXct(
            c("2025-01-01 06:00:00", "2025-01-02 18:00:00"),
            tz = "UTC"
        ),
        hourly_temperature_2m = c(2, 4)
    )

    result <- filter_data(response)

    expect_s3_class(result$date, "Date")
    expect_equal(result$date, as.Date(c("2025-01-01", "2025-01-02")))
})

test_that("filter_data removes rows containing missing values", {
    response <- data.frame(
        datetime = as.POSIXct(
            c("2025-01-01 00:00:00", "2025-01-01 01:00:00"),
            tz = "UTC"
        ),
        hourly_temperature_2m = c(12, NA_real_)
    )

    result <- filter_data(response)

    expect_equal(nrow(result), 1)
    expect_equal(result$hourly_temperature_2m, 12)
})

test_that("filter_data excludes leap days", {
    response <- data.frame(
        datetime = as.POSIXct(
            c(
                "2024-02-28 12:00:00",
                "2024-02-29 12:00:00",
                "2024-03-01 12:00:00"
            ),
            tz = "UTC"
        ),
        hourly_temperature_2m = c(8, 9, 10)
    )

    result <- filter_data(response)

    expect_equal(result$date, as.Date(c("2024-02-28", "2024-03-01")))
})
