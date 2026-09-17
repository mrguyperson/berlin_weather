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

test_that("validate_raw_data rejects malformed non-missing datetimes", {
    response <- data.frame(
        datetime = "not-a-date",
        hourly_temperature_2m = 12
    )

    expect_error(
        validate_raw_data(response),
        "Open-Meteo response contains invalid `datetime` values.",
        fixed = TRUE
    )
})

test_that("validate_raw_data requires numeric temperatures", {
    response <- data.frame(
        datetime = "2025-01-01 00:00:00",
        hourly_temperature_2m = "cold"
    )

    expect_error(
        validate_raw_data(response),
        "Open-Meteo response column `hourly_temperature_2m` must be numeric.",
        fixed = TRUE
    )
})

test_that("validate_raw_data rejects input with no usable observations", {
    response <- data.frame(
        datetime = NA_character_,
        hourly_temperature_2m = NA_real_
    )

    expect_error(
        validate_raw_data(response),
        "Open-Meteo response contains no usable weather observations.",
        fixed = TRUE
    )
})

test_that("validate_raw_data allows partial missing observations", {
    response <- data.frame(
        datetime = c("2025-01-01 00:00:00", NA_character_),
        hourly_temperature_2m = c(12, NA_real_)
    )

    expect_identical(validate_raw_data(response), response)
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

test_that("remove_incomplete_date removes an ordered partial final day", {
    complete_day <- data.frame(
        date = rep(as.Date("2025-01-01"), 24),
        hour = 0:23
    )
    partial_day <- data.frame(
        date = rep(as.Date("2025-01-02"), 5),
        hour = 0:4
    )

    result <- remove_incomplete_date(bind_rows(complete_day, partial_day))

    expect_equal(result, complete_day)
})

test_that("remove_incomplete_date retains a complete final day", {
    first_day <- data.frame(
        date = rep(as.Date("2025-01-01"), 24),
        hour = 0:23
    )
    final_day <- data.frame(
        date = rep(as.Date("2025-01-02"), 24),
        hour = 0:23
    )
    response <- bind_rows(first_day, final_day)

    expect_equal(remove_incomplete_date(response), response)
})

test_that("remove_incomplete_date is independent of row order", {
    complete_day <- data.frame(
        date = rep(as.Date("2025-01-01"), 24),
        hour = 0:23
    )
    partial_day <- data.frame(
        date = rep(as.Date("2025-01-02"), 5),
        hour = 0:4
    )
    ordered <- bind_rows(complete_day, partial_day)
    unsorted <- bind_rows(ordered[-1, ], ordered[1, ])

    ordered_result <- remove_incomplete_date(ordered)
    unsorted_result <- remove_incomplete_date(unsorted)

    expect_equal(
        arrange(unsorted_result, date, hour),
        arrange(ordered_result, date, hour)
    )
})
