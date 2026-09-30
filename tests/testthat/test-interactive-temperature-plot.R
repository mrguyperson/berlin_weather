library(testthat)
library(tidyverse)
library(glue)

source(testthat::test_path("..", "..", "R", "functions.R"))

fixture_plot_inputs <- function() {
    fixture <- compact_weather_fixture()
    filtered <- filter_data(combine_raw_data(
        validate_raw_data(fixture$historical_raw),
        validate_raw_data(fixture$current_raw)
    ))
    historical <- make_historical_data(filtered, fixture$today)
    calendar <- add_calendar_to_historical(
        make_calendar(fixture$today), historical
    )
    current <- get_this_year(filtered, fixture$reference_time)
    list(
        historical = calendar,
        current = current,
        records = get_new_records(calendar, current)
    )
}

plot_dates <- function(x) {
    if (inherits(x, "Date") || is.numeric(x)) {
        return(as.Date(unname(as.numeric(x)), origin = "1970-01-01"))
    }
    as.Date(unname(as.character(x)))
}

named_plot_trace <- function(traces, name) {
    matches <- Filter(function(trace) identical(trace$name, name), traces)
    expect_length(matches, 1L)
    matches[[1]]
}

test_that("interactive bands and mean retain the pooled-hourly fixture values", {
    inputs <- fixture_plot_inputs()
    widget <- make_interactive_temperature_plot(
        inputs$historical, inputs$current, inputs$records
    )
    expect_s3_class(widget, "plotly")
    expect_s3_class(widget, "htmlwidget")
    built <- plotly::plotly_build(widget)
    traces <- built$x$data

    expected_boundaries <- c(
        "Historical minimum" = "min",
        "Lowest to 5th percentile" = "x5",
        "5th to 25th percentile" = "x25",
        "25th to 75th percentile" = "x75",
        "75th to 95th percentile" = "x95",
        "95th percentile to highest" = "max",
        "Historical pooled-hourly mean" = "avg"
    )
    for (label in names(expected_boundaries)) {
        trace <- named_plot_trace(traces, label)
        expect_equal(plot_dates(trace$x), inputs$historical$date, info = label)
        expect_equal(as.numeric(trace$y),
            as.numeric(inputs$historical[[expected_boundaries[[label]]]]),
            info = label)
    }

    colors <- c("#2c7bb6", "#abd9e9", "#ffffbf", "#fdae61", "#d7191c")
    for (i in seq_along(colors)) {
        trace <- named_plot_trace(traces, names(expected_boundaries)[[i + 1L]])
        expect_identical(trace$fill, "tonexty")
        expect_identical(trace$fillcolor, colors[[i]])
    }
    expect_identical(
        named_plot_trace(traces, "Historical pooled-hourly mean")$line$color,
        "goldenrod"
    )
    jan2 <- filter(inputs$historical, date == as.Date("2025-01-02"))
    expect_equal(unname(as.numeric(c(jan2$min, jan2$x5, jan2$x25, jan2$avg,
                   jan2$x75, jan2$x95, jan2$max))),
                 c(0, 0, 0, 2, 4, 4, 4))
    expect_identical(built$x$layout$xaxis$type, "date")
    expect_identical(built$x$layout$yaxis$ticksuffix, "°C")
})

test_that("interactive daily ranges and record coordinates match the fixture", {
    inputs <- fixture_plot_inputs()
    traces <- plotly::plotly_build(make_interactive_temperature_plot(
        inputs$historical, inputs$current, inputs$records
    ))$x$data

    ranges <- named_plot_trace(traces, "Current-year daily range")
    expected_dates <- rep(inputs$current$date, each = 3L)
    expected_dates[seq(3L, length(expected_dates), by = 3L)] <- as.Date(NA)
    expected_y <- as.vector(rbind(
        inputs$current$this_year_min, inputs$current$this_year_max, NA_real_
    ))
    expect_equal(plot_dates(ranges$x), head(expected_dates, -1L))
    expect_equal(as.numeric(ranges$y), head(expected_y, -1L))
    expect_identical(ranges$line$color, "black")
    expect_equal(inputs$current$this_year_min, c(-20, 0, 0))
    expect_equal(inputs$current$this_year_max, c(4, 20, 20))

    heat <- named_plot_trace(traces, "New heat record")
    cold <- named_plot_trace(traces, "New cold record")
    expected_heat <- filter(inputs$records, new_record == "heat")
    expected_cold <- filter(inputs$records, new_record == "cold")
    expect_equal(plot_dates(heat$x), expected_heat$date)
    expect_equal(as.numeric(heat$y), expected_heat$this_year_max)
    expect_equal(plot_dates(cold$x), expected_cold$date)
    expect_equal(as.numeric(cold$y), expected_cold$this_year_min)
    expect_equal(plot_dates(heat$x), as.Date(c("2025-09-17", "2025-09-18")))
    expect_equal(plot_dates(cold$x), as.Date("2025-09-16"))
    expect_identical(heat$marker$color, "firebrick")
    expect_identical(cold$marker$color, "dodgerblue")
})

test_that("interactive values are stable under input row reordering", {
    inputs <- fixture_plot_inputs()
    reversed <- lapply(inputs, function(data) data[rev(seq_len(nrow(data))), ])
    build <- function(data) plotly::plotly_build(
        make_interactive_temperature_plot(
            data$historical, data$current, data$records
        )
    )$x$data
    normal <- build(inputs)
    reordered <- build(reversed)

    normalize <- function(traces) lapply(traces, function(trace) list(
        name = trace$name,
        x = plot_dates(trace$x),
        y = as.numeric(trace$y),
        fillcolor = trace$fillcolor
    ))
    expect_equal(normalize(reordered), normalize(normal))
})

test_that("absent current-year and record rows create no fabricated marks", {
    inputs <- fixture_plot_inputs()
    traces <- plotly::plotly_build(make_interactive_temperature_plot(
        inputs$historical,
        inputs$current[0, ],
        inputs$records[0, ]
    ))$x$data
    names <- vapply(traces, function(trace) trace$name, character(1))
    expect_false(any(c(
        "Current-year daily range", "New heat record", "New cold record"
    ) %in% names))
})
