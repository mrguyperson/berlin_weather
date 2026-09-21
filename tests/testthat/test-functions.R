library(testthat)
library(tidyverse)
library(glue)

source(testthat::test_path("..", "..", "R", "functions.R"))

test_that("get_raw_data can log an injected retrieval", {
    retriever <- function(...) data.frame(value = 1)

    expect_message(
        get_raw_data(
            "Berlin",
            as.Date("2026-01-01"),
            as.Date("2026-09-19"),
            retrieval_function = retriever,
            log_retrieval = TRUE
        ),
        paste0(
            "Retrieving Open-Meteo data for Berlin: ",
            "2026-01-01 through 2026-09-19"
        ),
        fixed = TRUE
    )
})

test_that("get_raw_data keeps injected retrievals quiet by default", {
    retriever <- function(...) data.frame(value = 1)

    expect_no_message(
        get_raw_data(
            "Berlin",
            as.Date("2026-01-01"),
            as.Date("2026-09-19"),
            retrieval_function = retriever
        )
    )
})

test_that("get_raw_data succeeds on its third retrieval attempt", {
    attempts <- 0
    response <- data.frame(
        datetime = "2025-01-01 00:00:00",
        hourly_temperature_2m = 12
    )
    retriever <- function(...) {
        attempts <<- attempts + 1

        if (attempts < 3) {
            stop("temporary retrieval failure")
        }

        response
    }

    result <- get_raw_data(
        "Berlin",
        as.Date("2025-01-01"),
        as.Date("2025-01-02"),
        retrieval_function = retriever,
        retry_rate = purrr::rate_delay(pause = 0, max_times = 3)
    )

    expect_identical(result, response)
    expect_equal(attempts, 3)
})

test_that("get_raw_data stops after three failed retrieval attempts", {
    attempts <- 0
    retriever <- function(...) {
        attempts <<- attempts + 1
        stop("persistent retrieval failure")
    }

    expect_error(
        get_raw_data(
            "Berlin",
            as.Date("2025-01-01"),
            as.Date("2025-01-02"),
            retrieval_function = retriever,
            retry_rate = purrr::rate_delay(pause = 0, max_times = 3)
        ),
        "persistent retrieval failure",
        fixed = TRUE
    )
    expect_equal(attempts, 3)
})

test_that("get_raw_data does not retry downstream validation failures", {
    attempts <- 0
    invalid_response <- data.frame(datetime = "2025-01-01 00:00:00")
    retriever <- function(...) {
        attempts <<- attempts + 1
        invalid_response
    }

    result <- get_raw_data(
        "Berlin",
        as.Date("2025-01-01"),
        as.Date("2025-01-02"),
        retrieval_function = retriever,
        retry_rate = purrr::rate_delay(pause = 0, max_times = 3)
    )

    expect_equal(attempts, 1)
    expect_error(
        validate_raw_data(result),
        "Open-Meteo response is missing required columns: hourly_temperature_2m",
        fixed = TRUE
    )
    expect_equal(attempts, 1)
})

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

test_that("current-year boundaries are contiguous", {
    midyear <- as.Date("2025-06-15")
    new_year <- as.Date("2025-01-01")

    expect_equal(get_current_year_start(midyear), as.Date("2025-01-01"))
    expect_equal(get_current_year_start(new_year), as.Date("2025-01-01"))
    expect_equal(
        get_current_year_start(midyear) - days(1),
        as.Date("2024-12-31")
    )
    expect_equal(
        get_current_year_start(midyear) - days(1) + days(1),
        get_current_year_start(midyear)
    )
})

test_that("validated split data recombine to the original response", {
    current_year_start <- as.POSIXct("2025-01-01", tz = "UTC")
    full_response <- data.frame(
        datetime = seq(
            as.POSIXct("2024-12-30", tz = "UTC"),
            as.POSIXct("2025-01-02 23:00:00", tz = "UTC"),
            by = "hour"
        ),
        hourly_temperature_2m = seq_len(96)
    )
    historical_response <- full_response %>%
        filter(datetime < current_year_start)
    current_year_response <- full_response %>%
        filter(datetime >= current_year_start)

    recombined <- combine_raw_data(
        validate_raw_data(historical_response),
        validate_raw_data(current_year_response)
    )

    expect_equal(recombined, full_response)
    expect_identical(names(recombined), names(full_response))
    expect_identical(class(recombined$datetime), class(full_response$datetime))
    expect_identical(
        typeof(recombined$hourly_temperature_2m),
        typeof(full_response$hourly_temperature_2m)
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

test_that("make_historical_data summarizes pooled hourly observations", {
    filtered_data <- tibble(
        date = as.Date(c(
            "2022-01-01", "2022-01-01",
            "2023-01-01", "2023-01-01"
        )),
        hourly_temperature_2m = c(0, 10, 20, 30)
    )

    result <- add_calendar_to_historical(
        make_calendar(as.Date("2025-06-01")),
        make_historical_data(filtered_data, as.Date("2025-06-01"))
    ) %>%
        filter(date == as.Date("2025-01-01"))

    expect_equal(result$min, 0)
    expect_equal(unname(result$x5), 1.5)
    expect_equal(unname(result$x25), 7.5)
    expect_equal(result$avg, 15)
    expect_equal(unname(result$x75), 22.5)
    expect_equal(unname(result$x95), 28.5)
    expect_equal(result$max, 30)
})

test_that("make_historical_data excludes current-year observations", {
    filtered_data <- tibble(
        date = as.Date(c("2022-01-01", "2023-01-01", "2025-01-01")),
        hourly_temperature_2m = c(0, 10, 1000)
    )

    result <- add_calendar_to_historical(
        make_calendar(as.Date("2025-06-01")),
        make_historical_data(filtered_data, as.Date("2025-06-01"))
    ) %>%
        filter(date == as.Date("2025-01-01"))

    expect_equal(result$min, 0)
    expect_equal(result$avg, 5)
    expect_equal(result$max, 10)
})

test_that("historical calendar mapping is independent of input row order", {
    ordered <- tibble(
        date = as.Date(c(
            "2022-01-01", "2023-01-01",
            "2022-01-02", "2023-01-02",
            "2022-01-03", "2023-01-03"
        )),
        hourly_temperature_2m = c(0, 2, 10, 12, 20, 22)
    )
    shuffled <- ordered[c(5, 2, 3, 6, 1, 4), ]
    calendar <- make_calendar(as.Date("2025-06-01"))
    summarize_with_calendar <- function(data) {
        add_calendar_to_historical(
            calendar,
            make_historical_data(data, as.Date("2025-06-01"))
        ) %>%
            filter(date %in% as.Date(c(
                "2025-01-01", "2025-01-02", "2025-01-03"
            ))) %>%
            arrange(date)
    }

    ordered_result <- summarize_with_calendar(ordered)
    shuffled_result <- summarize_with_calendar(shuffled)

    expect_equal(ordered_result$avg, c(1, 11, 21))
    expect_equal(shuffled_result$avg, c(1, 11, 21))
    expect_equal(shuffled_result, ordered_result)
})

make_elapsed_hourly_day <- function(date, timezone = "Europe/Berlin") {
    date <- as.Date(date)
    start <- as.POSIXct(paste(date, "00:00:00"), tz = timezone)
    next_start <- as.POSIXct(paste(date + 1, "00:00:00"), tz = timezone)
    instants <- seq(start, next_start - 3600, by = "hour")
    local_times <- format(
        instants,
        format = "%Y-%m-%d %H:%M:%S",
        tz = timezone
    )

    data.frame(
        datetime = as.POSIXct(
            local_times,
            format = "%Y-%m-%d %H:%M:%S",
            tz = timezone
        ),
        date = rep(date, length(local_times)),
        hourly_temperature_2m = seq_along(local_times)
    )
}

make_openmeteo_hourly_day <- function(date, timezone = "Europe/Berlin") {
    date <- as.Date(date)
    local_times <- sprintf("%s %02d:00:00", date, 0:23)

    # Open-Meteo supplies a 24-position wall-clock grid. On spring DST days,
    # parsing the nonexistent 02:00 in Europe/Berlin normalizes it to 03:00.
    data.frame(
        datetime = as.POSIXct(
            local_times,
            format = "%Y-%m-%d %H:%M:%S",
            tz = timezone
        ),
        date = rep(date, length(local_times)),
        hourly_temperature_2m = seq_along(local_times)
    )
}

duplicate_hour_in_place_of_another <- function(day, missing, duplicate) {
    day$datetime[missing] <- day$datetime[duplicate]
    day
}

test_that("remove_incomplete_date removes an incomplete ordinary final day", {
    complete_day <- make_openmeteo_hourly_day("2025-01-01")
    partial_day <- head(make_openmeteo_hourly_day("2025-01-02"), 5)
    reference_time <- as.POSIXct("2025-01-03 00:00:00", tz = "Europe/Berlin")

    result <- remove_incomplete_date(
        bind_rows(complete_day, partial_day),
        reference_time
    )

    expect_equal(result, complete_day)
})

test_that("remove_incomplete_date removes a structurally complete current day", {
    first_day <- make_openmeteo_hourly_day("2025-01-01")
    final_day <- make_openmeteo_hourly_day("2025-01-02")
    response <- bind_rows(first_day, final_day)
    reference_time <- as.POSIXct("2025-01-02 12:00:00", tz = "Europe/Berlin")

    expect_equal(remove_incomplete_date(response, reference_time), first_day)
})

test_that("remove_incomplete_date removes a valid current spring DST day", {
    spring_day <- make_openmeteo_hourly_day("2025-03-30")
    reference_time <- as.POSIXct("2025-03-30 12:00:00", tz = "Europe/Berlin")

    expect_equal(nrow(spring_day), 24)
    expect_equal(remove_incomplete_date(spring_day, reference_time), spring_day[0, ])
})

test_that("remove_incomplete_date retains complete days after local midnight", {
    ordinary_day <- make_openmeteo_hourly_day("2025-01-02")
    spring_day <- make_openmeteo_hourly_day("2025-03-30")
    autumn_day <- make_openmeteo_hourly_day("2025-10-26")

    expect_equal(
        remove_incomplete_date(
            ordinary_day,
            as.POSIXct("2025-01-03 00:00:00", tz = "Europe/Berlin")
        ),
        ordinary_day
    )
    expect_equal(
        remove_incomplete_date(
            spring_day,
            as.POSIXct("2025-03-31 00:00:00", tz = "Europe/Berlin")
        ),
        spring_day
    )
    expect_equal(
        remove_incomplete_date(
            autumn_day,
            as.POSIXct("2025-10-27 00:00:00", tz = "Europe/Berlin")
        ),
        autumn_day
    )
})

test_that("remove_incomplete_date rejects same-count ordinary hour corruption", {
    ordinary_day <- make_openmeteo_hourly_day("2025-01-02")
    corrupted_day <- duplicate_hour_in_place_of_another(ordinary_day, 5, 4)
    reference_time <- as.POSIXct("2025-01-03 00:00:00", tz = "Europe/Berlin")

    expect_equal(
        remove_incomplete_date(corrupted_day, reference_time),
        corrupted_day[0, ]
    )
})

test_that("remove_incomplete_date rejects same-count spring DST corruption", {
    spring_day <- make_openmeteo_hourly_day("2025-03-30")
    corrupted_day <- duplicate_hour_in_place_of_another(spring_day, 5, 4)
    reference_time <- as.POSIXct("2025-03-31 00:00:00", tz = "Europe/Berlin")

    expect_equal(nrow(corrupted_day), 24)
    expect_equal(
        remove_incomplete_date(corrupted_day, reference_time),
        corrupted_day[0, ]
    )
})

test_that("remove_incomplete_date rejects same-count autumn DST corruption", {
    autumn_day <- make_openmeteo_hourly_day("2025-10-26")
    corrupted_day <- duplicate_hour_in_place_of_another(autumn_day, 6, 5)
    reference_time <- as.POSIXct("2025-10-27 00:00:00", tz = "Europe/Berlin")

    expect_equal(nrow(corrupted_day), 24)
    expect_equal(
        remove_incomplete_date(corrupted_day, reference_time),
        corrupted_day[0, ]
    )
})

test_that("remove_incomplete_date accepts Open-Meteo DST wall-clock grids", {
    spring_day <- make_openmeteo_hourly_day("2025-03-30")
    autumn_day <- make_openmeteo_hourly_day("2025-10-26")

    expect_equal(nrow(spring_day), 24)
    expect_equal(sum(duplicated(spring_day$datetime)), 1)
    expect_equal(
        remove_incomplete_date(
            spring_day,
            as.POSIXct("2025-03-31 00:00:00", tz = "Europe/Berlin")
        ),
        spring_day
    )
    expect_equal(nrow(autumn_day), 24)
    expect_equal(sum(duplicated(autumn_day$datetime)), 0)
    expect_equal(
        remove_incomplete_date(
            autumn_day,
            as.POSIXct("2025-10-27 00:00:00", tz = "Europe/Berlin")
        ),
        autumn_day
    )
})

test_that("remove_incomplete_date rejects a 23-hour spring elapsed-time pattern", {
    spring_day <- make_elapsed_hourly_day("2025-03-30")
    openmeteo_day <- make_openmeteo_hourly_day("2025-03-30")

    expect_equal(nrow(spring_day), 23)
    expect_equal(
        sum(format(spring_day$datetime, "%H", tz = "Europe/Berlin") == "03"),
        1
    )
    expect_equal(
        sum(format(openmeteo_day$datetime, "%H", tz = "Europe/Berlin") == "03"),
        2
    )
    expect_equal(
        remove_incomplete_date(
            spring_day,
            as.POSIXct("2025-03-31 00:00:00", tz = "Europe/Berlin")
        ),
        spring_day[0, ]
    )
})

test_that("remove_incomplete_date rejects a 25-hour autumn elapsed-time pattern", {
    autumn_day <- make_elapsed_hourly_day("2025-10-26")

    expect_equal(nrow(autumn_day), 25)
    expect_equal(sum(duplicated(autumn_day$datetime)), 1)
    expect_equal(
        remove_incomplete_date(
            autumn_day,
            as.POSIXct("2025-10-27 00:00:00", tz = "Europe/Berlin")
        ),
        autumn_day[0, ]
    )
})

test_that("remove_incomplete_date only removes the incomplete final date", {
    earlier_day <- make_openmeteo_hourly_day("2025-03-30")
    partial_final_day <- head(make_openmeteo_hourly_day("2025-03-31"), 5)

    result <- remove_incomplete_date(
        bind_rows(earlier_day, partial_final_day),
        as.POSIXct("2025-04-01 00:00:00", tz = "Europe/Berlin")
    )

    expect_equal(result, earlier_day)
})

test_that("remove_incomplete_date is independent of row order", {
    first_day <- make_openmeteo_hourly_day("2025-01-01")
    final_day <- make_openmeteo_hourly_day("2025-01-02")
    ordered <- bind_rows(first_day, final_day)
    unsorted <- bind_rows(ordered[-1, ], ordered[1, ])
    reference_time <- as.POSIXct("2025-01-03 00:00:00", tz = "Europe/Berlin")

    ordered_result <- remove_incomplete_date(ordered, reference_time)
    unsorted_result <- remove_incomplete_date(unsorted, reference_time)

    expect_equal(
        arrange(unsorted_result, date, datetime),
        arrange(ordered_result, date, datetime)
    )
})

test_that("get_this_year is empty before the first current-year day completes", {
    previous_year <- make_openmeteo_hourly_day("2024-12-31")
    current_day <- make_openmeteo_hourly_day("2025-01-01")
    reference_time <- as.POSIXct("2025-01-01 12:00:00", tz = "Europe/Berlin")

    result <- get_this_year(
        bind_rows(previous_year, current_day),
        reference_time
    )

    expect_equal(nrow(result), 0)
})

test_that("get_this_year calculates daily means from hourly observations", {
    current_day <- make_openmeteo_hourly_day("2025-01-01")
    current_day$hourly_temperature_2m <- c(rep(0, 12), rep(10, 12))

    result <- get_this_year(
        current_day,
        as.POSIXct("2025-01-02 00:00:00", tz = "Europe/Berlin")
    )

    expect_equal(result$this_year_mean, 5)
})

make_temperature_day <- function(date, temperatures) {
    day <- make_openmeteo_hourly_day(date)
    day$hourly_temperature_2m <- rep(
        temperatures,
        length.out = nrow(day)
    )
    day
}

test_that("summarize_latest_day selects the latest completed current date", {
    filtered_data <- bind_rows(
        make_temperature_day("2020-09-18", c(0, 2)),
        make_temperature_day("2021-09-18", c(4, 6)),
        make_temperature_day("2022-09-18", c(8, 10)),
        make_temperature_day("2025-09-17", c(2, 4)),
        make_temperature_day("2025-09-18", c(8, 12))
    )
    this_year <- tibble(
        date = as.Date(c("2025-09-17", "2025-09-18")),
        this_year_mean = c(3, 10)
    )

    result <- summarize_latest_day(filtered_data, this_year)

    expect_equal(result$date, as.Date("2025-09-18"))
    expect_equal(result$current_mean, 10)
    expect_equal(result$historical_median, 5)
    expect_equal(result$anomaly, 5)
    expect_equal(result$percentile, 100)
})

test_that("summarize_latest_day uses historical daily means for the same date", {
    filtered_data <- bind_rows(
        make_temperature_day("2020-09-18", 0),
        make_temperature_day("2021-09-18", c(10, 10, 10)),
        make_temperature_day("2022-09-17", c(-100, 100)),
        make_temperature_day("2025-09-18", c(4, 8))
    )
    this_year <- tibble(
        date = as.Date("2025-09-18"),
        this_year_mean = 6
    )

    result <- summarize_latest_day(filtered_data, this_year)

    expect_equal(result$current_mean, 6)
    expect_equal(result$historical_median, 5)
    expect_equal(result$anomaly, 1)
})

test_that("summarize_latest_day calculates negative anomalies and low percentiles", {
    filtered_data <- bind_rows(
        make_temperature_day("2020-09-18", 1),
        make_temperature_day("2021-09-18", 5),
        make_temperature_day("2022-09-18", 9),
        make_temperature_day("2025-09-18", c(-1, 1))
    )
    this_year <- tibble(
        date = as.Date("2025-09-18"),
        this_year_mean = 0
    )

    result <- summarize_latest_day(filtered_data, this_year)

    expect_equal(result$anomaly, -5)
    expect_equal(result$percentile, 0)
})

test_that("summarize_latest_day includes historical ties in the percentile", {
    filtered_data <- bind_rows(
        make_temperature_day("2020-09-18", 1),
        make_temperature_day("2021-09-18", 5),
        make_temperature_day("2022-09-18", 9),
        make_temperature_day("2025-09-18", 5)
    )
    this_year <- tibble(
        date = as.Date("2025-09-18"),
        this_year_mean = 5
    )

    result <- summarize_latest_day(filtered_data, this_year)

    expect_equal(result$percentile, 200 / 3)
})

test_that("summarize_latest_day is independent of input row order", {
    filtered_data <- bind_rows(
        make_temperature_day("2020-09-18", c(0, 2)),
        make_temperature_day("2021-09-18", c(4, 6)),
        make_temperature_day("2025-09-18", c(8, 12))
    )
    this_year <- tibble(
        date = as.Date("2025-09-18"),
        this_year_mean = 10
    )

    ordered <- summarize_latest_day(filtered_data, this_year)
    shuffled <- summarize_latest_day(
        filtered_data[c(25:72, 1:24), ],
        this_year
    )

    expect_equal(shuffled, ordered)
})

test_that("summarize_latest_day returns no metric without required observations", {
    current_data <- make_temperature_day("2025-09-18", c(8, 12))
    completed <- tibble(
        date = as.Date("2025-09-18"),
        this_year_mean = 10
    )

    expect_equal(nrow(summarize_latest_day(current_data, completed[0, ])), 0)
    expect_equal(nrow(summarize_latest_day(current_data, completed)), 0)
})

test_that("summarize_latest_day excludes a partial historical date", {
    partial_day <- make_temperature_day("2022-09-18", 100)[1:12, ]
    filtered_data <- bind_rows(
        make_temperature_day("2020-09-18", 0),
        make_temperature_day("2021-09-18", 10),
        partial_day
    )
    this_year <- tibble(
        date = as.Date("2025-09-18"),
        this_year_mean = 6
    )

    result <- summarize_latest_day(filtered_data, this_year)

    expect_equal(result$historical_median, 5)
    expect_equal(result$anomaly, 1)
    expect_equal(result$percentile, 50)
})

test_that("summarize_latest_day excludes same-count historical corruption", {
    corrupted_day <- make_temperature_day("2022-09-18", -100)
    corrupted_day <- duplicate_hour_in_place_of_another(corrupted_day, 5, 4)
    filtered_data <- bind_rows(
        make_temperature_day("2020-09-18", 0),
        make_temperature_day("2021-09-18", 10),
        corrupted_day
    )
    this_year <- tibble(
        date = as.Date("2025-09-18"),
        this_year_mean = 6
    )

    result <- summarize_latest_day(filtered_data, this_year)

    expect_equal(result$historical_median, 5)
    expect_equal(result$anomaly, 1)
    expect_equal(result$percentile, 50)
})

test_that("summarize_latest_day accepts complete historical DST dates", {
    filtered_data <- bind_rows(
        make_temperature_day("2020-03-29", 4),
        make_temperature_day("2026-03-29", 8)
    )
    this_year <- tibble(
        date = as.Date("2026-03-29"),
        this_year_mean = 8
    )

    result <- summarize_latest_day(filtered_data, this_year)

    expect_equal(result$historical_median, 4)
    expect_equal(result$percentile, 100)
})

test_that("summarize_latest_day is empty without complete historical dates", {
    partial_history <- make_temperature_day("2020-09-18", 4)[-1, ]
    this_year <- tibble(
        date = as.Date("2025-09-18"),
        this_year_mean = 8
    )

    result <- summarize_latest_day(partial_history, this_year)

    expect_equal(nrow(result), 0)
    expect_s3_class(result$date, "Date")
    expect_type(result$historical_median, "double")
})
