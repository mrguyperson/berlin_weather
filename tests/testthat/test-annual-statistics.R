library(testthat)
library(tidyverse)
source(testthat::test_path("..", "..", "R", "functions.R"))

annual_fixture <- function(year, temperature = 10) {
    dates <- seq(as.Date(sprintf("%d-01-01", year)),
                 as.Date(sprintf("%d-12-31", year)), by = "day")
    dates <- dates[!(month(dates) == 2 & mday(dates) == 29)]
    date <- rep(dates, each = 24)
    tibble(
        date = date,
        # Use the same parsed wall-clock grid as Open-Meteo, including DST.
        datetime = as.POSIXct(
            sprintf("%s %02d:00:00", date, rep(0:23, length(dates))),
            format = "%Y-%m-%d %H:%M:%S", tz = "Europe/Berlin"
        ),
        hourly_temperature_2m = rep(temperature, length.out = length(date))
    )
}

annual_today <- as.Date("2025-09-01")

test_that("annual means retain complete years and pool complete hourly data", {
    data <- annual_fixture(2024, c(0, 20))
    expect_equal(get_historical_means(data, annual_today)$temperature, 10)
    coverage <- get_annual_date_coverage(data, annual_today)
    expect_equal(nrow(coverage), 365)
    expect_true(all(coverage$complete))
    expect_false(any(month(coverage$date) == 2 & mday(coverage$date) == 29))
})

test_that("one incomplete represented date is excluded but its year is eligible", {
    data <- annual_fixture(2024, 10)
    data$hourly_temperature_2m[1:24] <- 100
    data <- data[-c(1, 2), ]
    expect_equal(get_historical_means(data, annual_today)$temperature, 10)
    coverage <- get_annual_date_coverage(data, annual_today)
    expect_equal(sum(coverage$complete), 364)
    expect_equal(coverage$date[!coverage$complete], as.Date("2024-01-01"))
})

test_that("expected dates detect wholly missing coverage", {
    full <- annual_fixture(2024)
    one_missing <- full[-(1:24), ]
    expect_equal(get_historical_means(one_missing, annual_today)$temperature, 10)
    two_missing <- full[-(1:48), ]
    expect_equal(nrow(get_historical_means(two_missing, annual_today)), 0)
    one_day <- full[1:24, ]
    expect_true(has_complete_openmeteo_hours(one_day))
    expect_equal(nrow(get_historical_means(one_day, annual_today)), 0)
    missing_month <- filter(full, month(date) != 7)
    expect_equal(nrow(get_historical_means(missing_month, annual_today)), 0)
    expect_equal(sum(get_annual_date_coverage(one_missing, annual_today)$complete), 364)
})

test_that("same-count corruption and missing dates share the annual allowance", {
    data <- annual_fixture(2024)
    data$datetime[5] <- data$datetime[4]
    data$hourly_temperature_2m[1:24] <- 100
    expect_equal(get_historical_means(data, annual_today)$temperature, 10)
    expect_equal(nrow(get_historical_means(data[-(25:48), ], annual_today)), 0)
})

test_that("annual outputs use only eligible historical years", {
    data <- bind_rows(
        annual_fixture(2020, 0), annual_fixture(2021, 2),
        annual_fixture(2022, 4), annual_fixture(2023, -100)[1:24, ],
        annual_fixture(2024, 100)[1:24, ], annual_fixture(2025, 1000)
    )
    expect_equal(get_historical_means(data, annual_today)$year, 2020:2022)
    expect_equal(get_most_extreme_year(data, annual_today, "hottest")$year, 2022)
    expect_equal(get_most_extreme_year(data, annual_today, "coldest")$year, 2020)
    expect_equal(calculate_temperature_slope(data, annual_today), 2)
    shuffled <- data[rev(seq_len(nrow(data))), ]
    expect_equal(get_annual_date_coverage(shuffled, annual_today),
                 get_annual_date_coverage(data, annual_today))
    expect_equal(get_historical_means(shuffled, annual_today),
                 get_historical_means(data, annual_today))
    for (type in c("hottest", "coldest")) {
        expect_equal(get_most_extreme_year(shuffled, annual_today, type),
                     get_most_extreme_year(data, annual_today, type))
    }
    expect_equal(calculate_temperature_slope(shuffled, annual_today), 2)
})

test_that("annual trend fails clearly with fewer than two eligible years", {
    full <- annual_fixture(2024)
    for (data in list(full, full[1:24, ], full[0, ])) {
        expect_error(calculate_temperature_slope(data, annual_today),
                     "At least two eligible historical years", fixed = TRUE)
    }
    empty <- get_historical_means(full[0, ], annual_today)
    expect_named(empty, c("year", "temperature"))
    expect_equal(nrow(empty), 0)
    expect_equal(nrow(get_most_extreme_year(full[0, ], annual_today)), 0)
})
