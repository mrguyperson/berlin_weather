library(testthat)
library(tidyverse)
library(glue)

source(testthat::test_path("..", "..", "R", "functions.R"))

run_compact_analysis <- function(fixture) {
    historical_raw <- validate_raw_data(fixture$historical_raw)
    current_raw <- validate_raw_data(fixture$current_raw)
    filtered <- filter_data(combine_raw_data(historical_raw, current_raw))
    historical <- make_historical_data(filtered, fixture$today)
    daily <- make_daily_temperature_data(filtered, fixture$reference_time)
    daily_context <- make_historical_daily_extreme_context(
        daily, fixture$reference_time
    )
    calendar <- add_calendar_to_historical(
        make_calendar(fixture$today), historical
    )
    current <- get_this_year(filtered, fixture$reference_time)

    list(
        filtered = filtered,
        historical = historical,
        daily_context = daily_context,
        calendar = calendar,
        current = current,
        latest = summarize_latest_day(filtered, current),
        coverage = get_annual_date_coverage(filtered, fixture$today),
        annual = get_historical_means(filtered, fixture$today),
        hottest_year = get_most_extreme_year(filtered, fixture$today),
        coldest_year = get_most_extreme_year(
            filtered, fixture$today, type = "coldest"
        ),
        slope = calculate_temperature_slope(filtered, fixture$today),
        hottest_days = get_top_10_list(filtered, fixture$reference_time),
        coldest_days = get_top_10_list(
            filtered, fixture$reference_time, type = "coldest"
        ),
        records = get_new_records(calendar, current)
    )
}

test_that("compact offline fixture exercises the production analysis sequence", {
    fixture <- compact_weather_fixture()
    result <- run_compact_analysis(fixture)

    expect_error(
        validate_raw_data(select(fixture$current_raw, -hourly_temperature_2m)),
        "missing required columns"
    )
    expect_false(any(lubridate::month(result$filtered$date) == 2 &
        lubridate::mday(result$filtered$date) == 29))
    expect_true(has_complete_openmeteo_hours(
        filter(result$filtered, date == as.Date("2022-03-27"))
    ))
    expect_true(has_complete_openmeteo_hours(
        filter(result$filtered, date == as.Date("2022-10-30"))
    ))
    spring <- filter(result$filtered, date == as.Date("2022-03-27"))
    autumn <- filter(result$filtered, date == as.Date("2022-10-30"))
    spring_hours <- format(spring$datetime, "%H", tz = "Europe/Berlin")
    autumn_hours <- format(autumn$datetime, "%H", tz = "Europe/Berlin")
    # Open-Meteo supplies 24 wall-clock positions: spring's nonexistent 02
    # normalizes to a second 03; autumn has only one 02 after parsing.
    expect_equal(nrow(spring), 24)
    expect_equal(sum(spring_hours == "02"), 0)
    expect_equal(sum(spring_hours == "03"), 2)
    expect_equal(nrow(autumn), 24)
    expect_equal(sum(autumn_hours == "02"), 1)
    expect_true(has_complete_openmeteo_hours(
        filter(result$filtered, date == as.Date("2025-09-19"))
    ))
    expect_false(has_complete_openmeteo_hours(
        filter(result$filtered, date == as.Date("2021-01-01"))
    ))
    expect_false(has_complete_openmeteo_hours(
        filter(result$filtered, date == as.Date("2022-01-02"))
    ))
    expect_equal(nrow(filter(result$filtered,
        date == as.Date("2021-01-01"))), 22)
    expect_equal(nrow(filter(result$filtered,
        date == as.Date("2022-01-02"))), 24)

    jan1 <- filter(result$calendar, date == as.Date("2025-01-01"))
    jan2 <- filter(result$calendar, date == as.Date("2025-01-02"))
    sep18 <- filter(result$calendar, date == as.Date("2025-09-18"))
    expect_equal(c(jan1$min, jan1$avg, jan1$max), c(2, 3, 4))
    expect_equal(c(jan2$min, jan2$avg, jan2$max), c(0, 2, 4))
    expect_equal(c(sep18$min, sep18$avg, sep18$max), c(0, 2, 4))
    expect_equal(nrow(result$calendar), 365)
    ordinary_context <- filter(result$daily_context,
        month == 1L, mday == 3L
    )
    expect_equal(ordinary_context$measure, c("daily_max", "daily_min"))
    expect_equal(ordinary_context$n_years, c(3L, 3L))
    expect_equal(ordinary_context$median, c(2, 2))
    expect_equal(nrow(result$daily_context), 730)

    expect_equal(result$current$date, as.Date(c(
        "2025-09-16", "2025-09-17", "2025-09-18"
    )))
    expect_equal(result$current$this_year_min, c(-20, 0, 0))
    expect_equal(result$current$this_year_max, c(4, 20, 20))
    expect_equal(result$current$this_year_mean, c(-8, 10, 10))
    expect_equal(result$latest$date, as.Date("2025-09-18"))
    expect_equal(unname(unlist(result$latest[1, -1])), c(10, 2, 8, 100))

    complete_counts <- result$coverage %>%
        summarize(days = sum(complete), .by = year) %>%
        arrange(year)
    expect_equal(complete_counts$year, c(2021, 2022, 2023))
    expect_equal(complete_counts$days, c(364, 364, 365))
    expect_equal(result$annual$temperature, c(0, 2, 4))
    expect_equal(result$hottest_year$year, 2023)
    expect_equal(result$coldest_year$year, 2021)
    expect_equal(result$slope, 2)

    expect_equal(result$hottest_days$date[1:2], as.Date(c(
        "2025-09-17", "2025-09-18"
    )))
    expect_equal(result$hottest_days$temperature[1:2], c(20, 20))
    expect_equal(result$coldest_days$date[1], as.Date("2025-09-16"))
    expect_equal(result$coldest_days$temperature[1], -20)
    expect_false(any(result$hottest_days$date == as.Date("2022-01-02")))
    expect_false(any(result$coldest_days$date == as.Date("2021-01-01")))
    expect_false(any(result$hottest_days$date == as.Date("2025-09-19")))
    expect_equal(result$records$date, as.Date(c(
        "2025-09-16", "2025-09-17", "2025-09-18"
    )))
    expect_equal(result$records$new_record, c("cold", "heat", "heat"))
})

test_that("compact analysis is invariant to source row order", {
    fixture <- compact_weather_fixture()
    ordered <- run_compact_analysis(fixture)
    fixture$historical_raw <- fixture$historical_raw[
        rev(seq_len(nrow(fixture$historical_raw))),
    ]
    fixture$current_raw <- fixture$current_raw[
        rev(seq_len(nrow(fixture$current_raw))),
    ]
    reversed <- run_compact_analysis(fixture)

    for (component in c(
        "calendar", "daily_context", "current", "latest", "coverage", "annual",
        "hottest_year", "coldest_year", "slope", "hottest_days",
        "coldest_days", "records"
    )) {
        expect_equal(reversed[[component]], ordered[[component]],
            info = component)
    }
})
