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
    daily <- make_daily_temperature_data(filtered, fixture$reference_time)
    calendar <- add_calendar_to_historical(
        make_calendar(fixture$today), historical
    )
    current <- get_this_year(filtered, fixture$reference_time)
    list(
        historical = calendar,
        current = current,
        records = get_new_records(calendar, current),
        daily_context = make_historical_daily_extreme_context(
            daily, fixture$reference_time
        )
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
        inputs$historical, inputs$current, inputs$records,
        inputs$daily_context
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
        inputs$historical, inputs$current, inputs$records,
        inputs$daily_context
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
            data$historical, data$current, data$records,
            data$daily_context
        )
    )$x$data
    normal <- build(inputs)
    reordered <- build(reversed)

    normalize <- function(traces) lapply(traces, function(trace) list(
        name = trace$name,
        x = plot_dates(trace$x),
        y = as.numeric(trace$y),
        fillcolor = trace$fillcolor,
        text = unname(as.character(trace$text)),
        hovertemplate = trace$hovertemplate
    ))
    expect_equal(normalize(reordered), normalize(normal))
})

test_that("absent current-year and record rows create no fabricated marks", {
    inputs <- fixture_plot_inputs()
    traces <- plotly::plotly_build(make_interactive_temperature_plot(
        inputs$historical,
        inputs$current[0, ],
        inputs$records[0, ],
        inputs$daily_context
    ))$x$data
    names <- vapply(traces, function(trace) trace$name, character(1))
    expect_false(any(c(
        "Current-year daily range", "New heat record", "New cold record"
    ) %in% names))
})

test_that("hover preparation joins separate daily extremes by calendar date", {
    inputs <- fixture_plot_inputs()
    hover <- prepare_temperature_hover_data(
        inputs$current, inputs$daily_context
    )

    expect_equal(hover$date, inputs$current$date)
    expect_equal(hover$this_year_min, c(-20, 0, 0))
    expect_equal(hover$this_year_max, c(4, 20, 20))
    expect_equal(hover$low_n_years, rep(3L, 3))
    expect_equal(hover$high_n_years, rep(3L, 3))
    for (column in c("low_p05", "high_p05")) {
        expect_equal(as.numeric(hover[[column]]), rep(0.2, 3), info = column)
    }
    for (column in c("low_median", "high_median")) {
        expect_equal(as.numeric(hover[[column]]), rep(2, 3), info = column)
    }
    for (column in c("low_p95", "high_p95")) {
        expect_equal(as.numeric(hover[[column]]), rep(3.8, 3), info = column)
    }
    expect_true(all(hover$context_available))

    reversed <- prepare_temperature_hover_data(
        inputs$current[rev(seq_len(nrow(inputs$current))), ],
        inputs$daily_context[rev(seq_len(nrow(inputs$daily_context))), ]
    )
    expect_equal(reversed, hover)
})

test_that("hover preparation retains days with missing or unusable context", {
    inputs <- fixture_plot_inputs()
    missing <- filter(inputs$daily_context,
        !(month == 9L & mday == 17L),
        !(month == 9L & mday == 18L & measure == "daily_max")
    )
    missing$p05[missing$month == 9L & missing$mday == 16L] <- NaN
    hover <- prepare_temperature_hover_data(inputs$current, missing)

    expect_equal(hover$date, inputs$current$date)
    expect_equal(hover$this_year_min, inputs$current$this_year_min)
    expect_equal(hover$this_year_max, inputs$current$this_year_max)
    expect_false(any(hover$context_available))
    expect_true(is.na(hover$low_median[[2]]))
    expect_true(is.na(hover$high_median[[3]]))

    empty <- prepare_temperature_hover_data(
        inputs$current[0, ], inputs$daily_context[0, ]
    )
    expect_equal(nrow(empty), 0L)
    expect_s3_class(empty$date, "Date")
    expect_type(empty$low_n_years, "integer")
    expect_type(empty$high_p95, "double")
    expect_type(empty$context_available, "logical")
    expect_equal(format_hover_temperature(c(NA_real_, NaN, Inf, -Inf, 1.24, -0.04)),
        c(rep("unavailable", 4), "1.2 °C", "0.0 °C"))
})

test_that("daily-range hover uses fixture values and labels daily context", {
    inputs <- fixture_plot_inputs()
    traces <- plotly::plotly_build(make_interactive_temperature_plot(
        inputs$historical, inputs$current, inputs$records,
        inputs$daily_context
    ))$x$data
    ranges <- named_plot_trace(traces, "Current-year daily range")
    dates <- plot_dates(ranges$x)
    first_day <- unique(as.character(ranges$text[which(
        dates == as.Date("2025-09-16")
    )]))

    expect_identical(first_day, paste0(
        "16 Sep 2025<br>Daily low: -20.0 °C",
        "<br>Historical daily lows: median 2.0 °C (5–95%: 0.2–3.8 °C)",
        "<br>Daily high: 4.0 °C",
        "<br>Historical daily highs: median 2.0 °C (5–95%: 0.2–3.8 °C)",
        "<br>Historical context: 3 prior years"
    ))
    templates <- as.character(ranges$hovertemplate)
    expect_true(any(!is.na(templates)))
    expect_setequal(templates[!is.na(templates)],
        "%{text}<extra></extra>")
    expect_false(any(grepl("\\b(?:NA|NaN)\\b", as.character(ranges$text),
        perl = TRUE)))
    for (name in c(
        "Historical minimum", "Lowest to 5th percentile",
        "5th to 25th percentile", "25th to 75th percentile",
        "75th to 95th percentile", "95th percentile to highest"
    )) {
        expect_true(all(as.character(named_plot_trace(traces, name)$hoverinfo)
            == "skip"))
    }
})

test_that("mean and record hover have formatted dates and temperatures", {
    inputs <- fixture_plot_inputs()
    traces <- plotly::plotly_build(make_interactive_temperature_plot(
        inputs$historical, inputs$current, inputs$records,
        inputs$daily_context
    ))$x$data

    mean <- named_plot_trace(traces, "Historical pooled-hourly mean")
    jan2 <- which(plot_dates(mean$x) == as.Date("2025-01-02"))
    expect_identical(as.character(mean$text[[jan2]]),
        "2 Jan<br>Historical pooled-hourly mean: 2.0 °C")
    expect_true(all(as.character(mean$hovertemplate) ==
        "%{text}<extra></extra>"))

    heat <- named_plot_trace(traces, "New heat record")
    cold <- named_plot_trace(traces, "New cold record")
    expect_identical(as.character(heat$text[[1]]),
        "17 Sep 2025<br>New heat record: 20.0 °C")
    expect_identical(as.character(cold$text[[1]]),
        "16 Sep 2025<br>New cold record: -20.0 °C")
    expect_true(all(as.character(heat$hovertemplate) ==
        "%{text}<extra></extra>"))
    expect_true(all(as.character(cold$hovertemplate) ==
        "%{text}<extra></extra>"))
    for (trace in list(mean, heat, cold)) {
        expect_false(any(grepl("\\b(?:NA|NaN)\\b", as.character(trace$text),
            perl = TRUE)))
    }
})

test_that("missing daily context produces an explicit fallback hover", {
    inputs <- fixture_plot_inputs()
    context <- filter(inputs$daily_context,
        !(month == 9L & mday == 17L)
    )
    traces <- plotly::plotly_build(make_interactive_temperature_plot(
        inputs$historical, inputs$current, inputs$records, context
    ))$x$data
    ranges <- named_plot_trace(traces, "Current-year daily range")
    dates <- plot_dates(ranges$x)
    missing_hover <- unique(as.character(ranges$text[which(
        dates == as.Date("2025-09-17")
    )]))
    expect_identical(missing_hover, paste0(
        "17 Sep 2025<br>Daily low: 0.0 °C",
        "<br>Daily high: 20.0 °C",
        "<br>Historical context unavailable"
    ))
    expect_false(grepl("\\b(?:NA|NaN)\\b", missing_hover, perl = TRUE))
    expect_equal(as.numeric(ranges$y)[which(
        dates == as.Date("2025-09-17")
    )], c(0, 20))

    empty_context_traces <- plotly::plotly_build(
        make_interactive_temperature_plot(
            inputs$historical, inputs$current, inputs$records,
            inputs$daily_context[0, ]
        )
    )$x$data
    all_fallback <- named_plot_trace(
        empty_context_traces, "Current-year daily range"
    )$text
    all_fallback <- as.character(all_fallback)
    all_fallback <- all_fallback[!is.na(all_fallback) & nzchar(all_fallback)]
    expect_length(unique(all_fallback), nrow(inputs$current))
    expect_true(all(grepl("Historical context unavailable",
        unique(all_fallback))))
})

test_that("temperature month ranges respect non-leap and leap calendars", {
    ordinary <- make_temperature_month_ranges(as.Date(c(
        "2025-01-01", "2025-09-16", "2025-12-31"
    )))
    expect_named(ordinary, c("Full year", month.abb))
    expect_identical(ordinary[["Full year"]],
        c("2024-12-31 12:00:00", "2025-12-31 12:00:00"))
    expect_identical(ordinary[["Jan"]],
        c("2024-12-31 12:00:00", "2025-01-31 12:00:00"))
    expect_identical(ordinary[["Feb"]],
        c("2025-01-31 12:00:00", "2025-02-28 12:00:00"))
    expect_identical(ordinary[["Dec"]],
        c("2025-11-30 12:00:00", "2025-12-31 12:00:00"))

    leap <- make_temperature_month_ranges(as.Date(c(
        "2028-01-01", "2028-02-28", "2028-12-31"
    )))
    expect_identical(leap[["Feb"]],
        c("2028-01-31 12:00:00", "2028-02-29 12:00:00"))
    expect_identical(leap[["Dec"]],
        c("2028-11-30 12:00:00", "2028-12-31 12:00:00"))
    expect_error(make_temperature_month_ranges(as.Date(character())),
        "one calendar year")
    expect_error(make_temperature_month_ranges(as.Date(c(
        "2025-01-01", "2026-01-01"
    ))), "one calendar year")
})

test_that("month menu changes only the date viewport and retains native navigation", {
    inputs <- fixture_plot_inputs()
    widget <- make_interactive_temperature_plot(
        inputs$historical, inputs$current, inputs$records,
        inputs$daily_context
    )
    built <- plotly::plotly_build(widget)
    layout <- built$x$layout
    ranges <- make_temperature_month_ranges(inputs$historical$date)

    expect_identical(layout$xaxis$range, ranges[["Full year"]])
    expect_identical(layout$xaxis$dtick, "M1")
    expect_identical(layout$xaxis$tickformat, "%b")
    expect_identical(layout$dragmode, "zoom")
    expect_null(layout$xaxis$rangeslider)
    expect_length(layout$updatemenus, 1L)
    menu <- layout$updatemenus[[1]]
    expect_identical(menu$type, "dropdown")
    expect_identical(menu$active, 0L)
    expect_identical(vapply(menu$buttons, `[[`, character(1), "label"),
        c("Full year", month.abb))
    for (label in names(ranges)) {
        button <- menu$buttons[[match(label, names(ranges))]]
        expect_identical(button$method, "relayout")
        expect_named(button$args[[1]], "xaxis.range")
        expect_identical(button$args[[1]][["xaxis.range"]], ranges[[label]])
    }
    expect_true(isTRUE(built$x$config$responsive))
    expect_false(isTRUE(built$x$config$scrollZoom))
    expect_identical(built$x$config$modeBarButtonsToRemove,
        c("select2d", "lasso2d"))
    expect_equal(length(built$x$data), 10L)

    reversed <- lapply(inputs, function(data) data[rev(seq_len(nrow(data))), ])
    reordered <- plotly::plotly_build(make_interactive_temperature_plot(
        reversed$historical, reversed$current, reversed$records,
        reversed$daily_context
    ))
    expect_identical(reordered$x$layout$xaxis, layout$xaxis)
    expect_identical(reordered$x$layout$updatemenus, layout$updatemenus)
    expect_identical(reordered$x$config, built$x$config)
})
