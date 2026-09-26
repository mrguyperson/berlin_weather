library(testthat)
library(tidyverse)
source(testthat::test_path("..", "..", "R", "functions.R"))

extreme_day <- function(date, temperatures = c(-5, 10)) {
    tibble(
        date = rep(as.Date(date), 24),
        # Match Open-Meteo's parsed 24-position grid, including spring normalization.
        datetime = as.POSIXct(
            sprintf("%s %02d:00:00", date, 0:23),
            format = "%Y-%m-%d %H:%M:%S", tz = "Europe/Berlin"
        ),
        hourly_temperature_2m = rep(temperatures, length.out = 24)
    )
}

rank_at <- function(data, reference_time, type) {
    get_top_10_list(data, reference_time, type = type)
}

extreme_reference <- as.POSIXct("2025-01-12 12:00:00", tz = "Europe/Berlin")

test_that("daily extremes use hourly minima and maxima of completed current-year days", {
    data <- bind_rows(extreme_day("2025-01-01", c(-5, 20)),
                      extreme_day("2025-01-02", c(-10, 15)))
    hot <- rank_at(data, extreme_reference, "hottest")
    cold <- rank_at(data, extreme_reference, "coldest")
    expect_equal(hot$date, as.Date(c("2025-01-01", "2025-01-02")))
    expect_equal(hot$temperature, c(20, 15))
    expect_equal(cold$date, as.Date(c("2025-01-02", "2025-01-01")))
    expect_equal(cold$temperature, c(-10, -5))
})

test_that("incomplete historical dates and same-count corruption cannot rank", {
    complete <- extreme_day("2025-01-01")
    partial <- extreme_day("1940-01-01", c(-50, 50))[-c(1, 2), ]
    corrupt <- extreme_day("2024-01-01", c(-60, 60))
    corrupt$datetime[5] <- corrupt$datetime[4]
    for (type in c("hottest", "coldest")) {
        result <- rank_at(bind_rows(partial, corrupt, complete), extreme_reference, type)
        expect_equal(result, rank_at(complete, extreme_reference, type))
    }
})

test_that("partial and full-grid in-progress dates and future dates cannot rank", {
    past <- extreme_day("2025-01-11")
    current <- extreme_day("2025-01-12", c(-50, 50))
    future <- extreme_day("2025-01-13", c(-60, 60))
    for (type in c("hottest", "coldest")) {
        for (candidate in list(current[1:2, ], current)) {
            result <- rank_at(bind_rows(past, candidate, future), extreme_reference, type)
            expect_equal(result, rank_at(past, extreme_reference, type))
        }
    }
})

test_that("ordinary and Open-Meteo DST days become eligible at Berlin midnight", {
    for (date in c("2025-01-12", "2025-03-30", "2025-10-26")) {
        data <- extreme_day(date)
        midnight <- as.POSIXct(paste(as.Date(date) + 1, "00:00:00"), tz = "Europe/Berlin")
        for (type in c("hottest", "coldest")) {
            expect_equal(nrow(rank_at(data, midnight - 1, type)), 0)
            expect_equal(nrow(rank_at(data, midnight, type)), 1)
            # The instant's display timezone must not change Berlin eligibility.
            expect_equal(rank_at(data, with_tz(midnight, "UTC"), type),
                         rank_at(data, midnight, type))
        }
    }
})

test_that("ties including the tenth-place cutoff choose earlier dates independently of order", {
    data <- bind_rows(lapply(1:11, function(i) {
        extreme_day(sprintf("2025-01-%02d", i), c(-10, 10))
    }))
    shuffled <- data[rev(seq_len(nrow(data))), ]
    for (type in c("hottest", "coldest")) {
        ordered <- rank_at(data, extreme_reference, type)
        reversed <- rank_at(shuffled, extreme_reference, type)
        expect_equal(nrow(reversed), 10)
        expect_equal(reversed$date, as.Date("2025-01-01") + 0:9)
        expect_equal(reversed, ordered)
    }
})

test_that("no eligible dates returns a typed empty ranking", {
    day <- extreme_day("2025-01-12")
    for (data in list(day[0, ], day[1:2, ], day)) {
        for (type in c("hottest", "coldest")) {
            result <- rank_at(data, extreme_reference, type)
            expect_named(result, c("date", "temperature"))
            expect_equal(nrow(result), 0)
            expect_s3_class(result$date, "Date")
            expect_type(result$temperature, "double")
        }
    }
})
