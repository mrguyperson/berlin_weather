library(testthat)
library(tidyverse)

source(testthat::test_path("..", "..", "R", "functions.R"))

fixture_daily_temperatures <- function(fixture) {
    filtered <- filter_data(combine_raw_data(
        validate_raw_data(fixture$historical_raw),
        validate_raw_data(fixture$current_raw)
    ))
    make_daily_temperature_data(filtered, fixture$reference_time)
}

test_that("daily extreme context has separate typed, ordered distributions", {
    fixture <- compact_weather_fixture()
    daily <- fixture_daily_temperatures(fixture)
    context <- make_historical_daily_extreme_context(
        daily, fixture$reference_time
    )

    expect_identical(names(context), c(
        "month", "mday", "measure", "n_years", "minimum", "p05",
        "p25", "median", "p75", "p95", "maximum"
    ))
    expect_s3_class(context, "tbl_df")
    expect_type(context$month, "integer")
    expect_type(context$mday, "integer")
    expect_type(context$measure, "character")
    expect_type(context$n_years, "integer")
    for (column in c("minimum", "p05", "p25", "median", "p75", "p95", "maximum")) {
        expect_type(context[[column]], "double")
    }
    expect_setequal(unique(context$measure), c("daily_min", "daily_max"))
    expect_equal(nrow(context), 730)
    expect_equal(nrow(distinct(context, month, mday, measure)), nrow(context))
    expect_identical(context, arrange(context, month, mday, measure))

    ordinary <- filter(context, month == 1L, mday == 3L)
    expect_equal(ordinary$n_years, c(3L, 3L))
    for (column in c("minimum", "p05", "p25", "median", "p75", "p95", "maximum")) {
        expect_equal(ordinary[[column]], rep(c(
            minimum = 0, p05 = 0.2, p25 = 1, median = 2,
            p75 = 3, p95 = 3.8, maximum = 4
        )[[column]], 2))
    }
})

test_that("unusable prior-year fixture dates reduce sample counts", {
    fixture <- compact_weather_fixture()
    context <- make_historical_daily_extreme_context(
        fixture_daily_temperatures(fixture), fixture$reference_time
    )

    jan1 <- filter(context, month == 1L, mday == 1L)
    jan2 <- filter(context, month == 1L, mday == 2L)
    expect_equal(jan1$n_years, c(2L, 2L))
    expect_equal(jan1$minimum, c(2, 2))
    expect_equal(jan1$p05, c(2.1, 2.1))
    expect_equal(jan1$maximum, c(4, 4))
    expect_equal(jan2$n_years, c(2L, 2L))
    expect_equal(jan2$minimum, c(0, 0))
    expect_equal(jan2$p95, c(3.8, 3.8))
    expect_equal(jan2$maximum, c(4, 4))

    for (calendar_date in list(c(3L, 27L), c(10L, 30L))) {
        transition <- filter(context,
            month == calendar_date[[1]], mday == calendar_date[[2]]
        )
        expect_equal(transition$measure, c("daily_max", "daily_min"))
        expect_equal(transition$n_years, c(3L, 3L))
        expect_equal(transition$median, c(2, 2))
    }
})

test_that("daily minima and maxima remain distinct without filling absent dates", {
    days <- tibble(
        date = as.Date(c("2021-06-01", "2022-06-01", "2023-06-01")),
        year = c(2021L, 2022L, 2023L),
        month = c(6L, 6L, 6L),
        mday = c(1L, 1L, 1L),
        temperature_min = c(0, 2, 4),
        temperature_mean = c(5, 11, 17),
        temperature_max = c(10, 20, 30)
    )
    reference_time <- as.POSIXct("2025-06-02", tz = "Europe/Berlin")

    context <- make_historical_daily_extreme_context(days, reference_time)
    expect_equal(nrow(context), 2)
    expect_equal(context$mday, c(1L, 1L))
    expect_equal(context$measure, c("daily_max", "daily_min"))
    expect_equal(context$n_years, c(3L, 3L))
    expect_equal(context$minimum, c(10, 0))
    expect_equal(context$median, c(20, 2))
    expect_equal(context$maximum, c(30, 4))
})

test_that("current and future years do not change historical context", {
    fixture <- compact_weather_fixture()
    daily <- fixture_daily_temperatures(fixture)
    baseline <- make_historical_daily_extreme_context(
        daily, fixture$reference_time
    )
    altered <- daily
    altered$temperature_min[altered$year == 2025L] <- -10000
    altered$temperature_max[altered$year == 2025L] <- 10000
    future <- altered[altered$year == 2025L, ][1, ]
    future$year <- 2026L
    future$date <- as.Date("2026-09-16")
    altered <- bind_rows(altered, future)

    expect_identical(
        make_historical_daily_extreme_context(altered, fixture$reference_time),
        baseline
    )
    expect_identical(
        make_historical_daily_extreme_context(
            daily[rev(seq_len(nrow(daily))), ], fixture$reference_time
        ),
        baseline
    )
})

test_that("Berlin calendar year governs the baseline and empty output stays typed", {
    fixture <- compact_weather_fixture()
    daily <- fixture_daily_temperatures(fixture)
    berlin_new_year <- as.POSIXct("2024-12-31 23:30:00", tz = "UTC")
    context <- make_historical_daily_extreme_context(daily, berlin_new_year)
    expect_equal(unique(context$n_years), c(2L, 3L))

    empty <- make_historical_daily_extreme_context(
        filter(daily, year >= 2025L), fixture$reference_time
    )
    expect_equal(nrow(empty), 0)
    expect_identical(names(empty), names(context))
    for (column in c("month", "mday", "n_years")) {
        expect_type(empty[[column]], "integer")
    }
    expect_type(empty$measure, "character")
    for (column in c("minimum", "p05", "p25", "median", "p75", "p95", "maximum")) {
        expect_type(empty[[column]], "double")
    }
})
