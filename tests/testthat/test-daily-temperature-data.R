library(testthat)
library(tidyverse)
library(glue)

source(testthat::test_path("..", "..", "R", "functions.R"))

filtered_compact_weather <- function(fixture) {
    filter_data(combine_raw_data(
        validate_raw_data(fixture$historical_raw),
        validate_raw_data(fixture$current_raw)
    ))
}

test_that("daily model contains only complete ended fixture dates", {
    fixture <- compact_weather_fixture()
    filtered <- filtered_compact_weather(fixture)
    daily <- make_daily_temperature_data(filtered, fixture$reference_time)

    expect_identical(names(daily), c(
        "date", "year", "month", "mday",
        "temperature_min", "temperature_mean", "temperature_max"
    ))
    expect_s3_class(daily$date, "Date")
    expect_type(daily$year, "integer")
    expect_type(daily$month, "integer")
    expect_type(daily$mday, "integer")
    expect_type(daily$temperature_min, "double")
    expect_type(daily$temperature_mean, "double")
    expect_type(daily$temperature_max, "double")
    expect_equal(nrow(daily), 1096)
    expect_false(anyDuplicated(daily$date) > 0)
    expect_identical(daily$date, sort(daily$date))

    expect_false(any(as.Date(c(
        "2021-01-01", "2022-01-02", "2024-02-29", "2025-09-19"
    )) %in% daily$date))
    expect_true(all(as.Date(c(
        "2022-03-27", "2022-10-30", "2025-09-16",
        "2025-09-17", "2025-09-18"
    )) %in% daily$date))

    jan1 <- filter(daily, date == as.Date("2022-01-01"))
    expect_equal(unname(unlist(jan1[c(
        "year", "month", "mday", "temperature_min",
        "temperature_mean", "temperature_max"
    )])), c(2022, 1, 1, 2, 2, 2))
    sep16 <- filter(daily, date == as.Date("2025-09-16"))
    expect_equal(unname(unlist(sep16[c(
        "temperature_min", "temperature_mean", "temperature_max"
    )])), c(-20, -8, 4))
    sep18 <- filter(daily, date == as.Date("2025-09-18"))
    expect_equal(unname(unlist(sep18[c(
        "temperature_min", "temperature_mean", "temperature_max"
    )])), c(0, 10, 20))
})

test_that("daily model admits a complete day at the next Berlin midnight", {
    fixture <- compact_weather_fixture()
    last_day <- filtered_compact_weather(fixture) %>%
        filter(date == as.Date("2025-09-19"))
    before_midnight <- as.POSIXct(
        "2025-09-19 23:59:59", tz = "Europe/Berlin"
    )
    at_midnight <- as.POSIXct(
        "2025-09-20 00:00:00", tz = "Europe/Berlin"
    )

    empty <- make_daily_temperature_data(last_day, before_midnight)
    expect_s3_class(empty, "tbl_df")
    expect_identical(names(empty), c(
        "date", "year", "month", "mday",
        "temperature_min", "temperature_mean", "temperature_max"
    ))
    expect_equal(nrow(empty), 0)
    expect_s3_class(empty$date, "Date")
    expect_type(empty$year, "integer")
    expect_type(empty$month, "integer")
    expect_type(empty$mday, "integer")
    expect_type(empty$temperature_min, "double")
    expect_type(empty$temperature_mean, "double")
    expect_type(empty$temperature_max, "double")

    completed <- make_daily_temperature_data(last_day, at_midnight)
    expect_equal(completed$date, as.Date("2025-09-19"))
    expect_equal(unname(unlist(completed[c(
        "temperature_min", "temperature_mean", "temperature_max"
    )])), c(-100, 0, 100))
})

test_that("daily model never fills a missing hourly observation", {
    fixture <- compact_weather_fixture()
    one_day <- fixture$current_raw[1:24, ]
    one_day$hourly_temperature_2m[1] <- NA_real_

    filtered <- filter_data(validate_raw_data(one_day))
    daily <- make_daily_temperature_data(
        filtered, fixture$reference_time
    )
    expect_equal(nrow(daily), 0)
})

test_that("daily model is row-order invariant and matches current-year output", {
    fixture <- compact_weather_fixture()
    filtered <- filtered_compact_weather(fixture)
    daily <- make_daily_temperature_data(filtered, fixture$reference_time)
    reversed <- make_daily_temperature_data(
        filtered[rev(seq_len(nrow(filtered))), ],
        fixture$reference_time
    )
    expect_identical(reversed, daily)

    current_from_daily <- daily %>%
        filter(year == 2025L) %>%
        transmute(
            date,
            this_year_min = temperature_min,
            this_year_max = temperature_max,
            this_year_mean = temperature_mean
        )
    expect_equal(current_from_daily,
        get_this_year(filtered, fixture$reference_time))
})
