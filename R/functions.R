get_city_coords <- function(city) {
    tibble(city = city) %>%
        tidygeocoder::geocode(
            city,
            method = "osm",
            lat = "latitude",
            long = "longitude"
        )
}

get_raw_data <- function(
    city,
    start_date,
    today,
    hourly = "temperature_2m",
    retrieval_function = openmeteo::weather_history,
    retry_rate = purrr::rate_backoff(max_times = 3),
    timeout_seconds = 60,
    log_retrieval = identical(
        retrieval_function,
        openmeteo::weather_history
    )
) {
    if (log_retrieval) {
        message(
            sprintf(
                "Retrieving Open-Meteo data for %s: %s through %s",
                city,
                format(as.Date(start_date), "%Y-%m-%d"),
                format(as.Date(today), "%Y-%m-%d")
            )
        )
    }

    last_retrieval_error <- NULL
    retrieve_and_capture_error <- function(...) {
        tryCatch(
            retrieval_function(...),
            error = function(error) {
                last_retrieval_error <<- error
                stop(error)
            }
        )
    }

    retrieve_with_retry <- purrr::insistently(
        retrieve_and_capture_error,
        rate = retry_rate,
        quiet = FALSE
    )

    tryCatch(
        httr::with_config(
            httr::timeout(timeout_seconds),
            retrieve_with_retry(
                city,
                start = start_date,
                end = today,
                hourly
            )
        ),
        purrr_error_rate_excess = function(error) {
            if (!is.null(last_retrieval_error)) {
                stop(last_retrieval_error)
            }

            stop(error)
        }
    )
}

get_current_year_start <- function(today) {
    lubridate::floor_date(lubridate::as_date(today), unit = "year")
}

combine_raw_data <- function(
    validated_historical_raw_data,
    validated_current_year_raw_data
) {
    dplyr::bind_rows(
        validated_historical_raw_data,
        validated_current_year_raw_data
    )
}

validate_raw_data <- function(raw_data) {
    if (!is.data.frame(raw_data)) {
        stop("Open-Meteo response must be data-frame-like.", call. = FALSE)
    }

    if (nrow(raw_data) == 0) {
        stop("Open-Meteo response is empty.", call. = FALSE)
    }

    required_columns <- c("datetime", "hourly_temperature_2m")
    missing_columns <- setdiff(required_columns, names(raw_data))

    if (length(missing_columns) > 0) {
        stop(
            "Open-Meteo response is missing required columns: ",
            paste(missing_columns, collapse = ", "),
            call. = FALSE
        )
    }

    if (!is.numeric(raw_data$hourly_temperature_2m)) {
        stop(
            "Open-Meteo response column `hourly_temperature_2m` must be numeric.",
            call. = FALSE
        )
    }

    non_missing_datetime <- !is.na(raw_data$datetime)
    parsed_dates <- rep(as.Date(NA), nrow(raw_data))

    if (any(non_missing_datetime)) {
        parsed_non_missing <- tryCatch(
            suppressWarnings(
                lubridate::as_date(raw_data$datetime[non_missing_datetime])
            ),
            error = function(e) NULL
        )

        if (is.null(parsed_non_missing) || any(is.na(parsed_non_missing))) {
            stop(
                "Open-Meteo response contains invalid `datetime` values.",
                call. = FALSE
            )
        }

        parsed_dates[non_missing_datetime] <- parsed_non_missing
    }

    usable_observation <- !is.na(parsed_dates) &
        !is.na(raw_data$hourly_temperature_2m)

    if (!any(usable_observation)) {
        stop(
            "Open-Meteo response contains no usable weather observations.",
            call. = FALSE
        )
    }

    raw_data
}



filter_data <- function(filtered_data) {
    filtered_data %>%
        drop_na() %>%
        mutate(date = as_date(datetime)) %>%
        filter(!(month(date) == 2 & mday(date) == 29))
}


make_historical_data <- function(filtered_data, today) {

    filtered_data %>%
        filter(
            year(date) != year(today),
            ) %>%
        # summarize( 
        #     hourly_temperature_2m = mean(hourly_temperature_2m), 
        #     .by = date
        # ) %>%
        mutate(
            month = month(date),
            mday = mday(date)
        ) %>%
        summarize(
            min = min(hourly_temperature_2m), 
            x5 = quantile(hourly_temperature_2m, 0.05),
            x25 = quantile(hourly_temperature_2m, 0.25),
            avg = mean(hourly_temperature_2m),
            x75 = quantile(hourly_temperature_2m, 0.75),
            x95 = quantile(hourly_temperature_2m, 0.95),
            max = max(hourly_temperature_2m), 
            .by = c(month, mday)
        ) %>%
        rowid_to_column(var = "day") %>%
        select(-c(month, mday))

}

make_calendar <- function(today) {

    first_day_this_year <- as_date(glue("{year(today)}-01-01"))
    last_day_this_year <- as_date(glue("{year(today)}-12-31"))

    tibble(
        date = seq(first_day_this_year, last_day_this_year, by = "+1 day")
    ) %>%
    filter(!(month(date) == 2 & mday(date) == 29)) %>%
    rowid_to_column(var = "day")

}

remove_incomplete_date <- function(filtered_data, reference_time) {
    last_date <- filtered_data %>%
        pull(date) %>%
        max()

    timezone <- "Europe/Berlin"
    day_start <- as.POSIXct(
        paste(last_date, "00:00:00"),
        tz = timezone
    )
    next_day_start <- as.POSIXct(
        paste(last_date + lubridate::days(1), "00:00:00"),
        tz = timezone
    )
    expected_rows <- as.numeric(
        difftime(next_day_start, day_start, units = "hours")
    )

    num_rows <- filtered_data %>%
        filter(date == last_date) %>%
        nrow()
    day_has_ended <- reference_time >= next_day_start

    if(!day_has_ended || num_rows != expected_rows) {
        filtered_data %>%
            filter(date != last_date)
    } else {
        filtered_data
    }
}

get_this_year <- function(filtered_data, reference_time) {

    data_w_date_check <- remove_incomplete_date(filtered_data, reference_time)

    data_w_date_check %>%
        filter(
            year(date) == max(year(date))
             ) %>%
        summarize(
            this_year_min = min(hourly_temperature_2m), 
            this_year_max = max(hourly_temperature_2m), 
            this_year_mean = mean(hourly_temperature_2m), 
            .by = date
        )

}

add_calendar_to_historical <- function(calendar, historical_data) {
    left_join(
        calendar,
        historical_data,
        by = join_by("day")
        ) %>%
        select(-day)
}

dummy_legend_data <- function(this_year_data) {
    most_recent_date <- get_most_recent_date(this_year_data)
    current_year <- year(most_recent_date)
    tribble(
        ~x, ~y, ~xend, ~yend, ~label,
        glue("{current_year}-05-28"), 0, glue("{current_year}-06-05"), 0, glue("Daily temp. range this year up to {day(most_recent_date)} {month(most_recent_date, label = TRUE)}."),
        glue("{current_year}-06-01"), -3, NA, NA, "All-time daily high temp. set this year",
        glue("{current_year}-06-01"), -6, NA, NA, "All-time daily low temp. set this year"
    ) %>%
    mutate(
        across(c(x, xend), ~ymd(.x)),
        text_x = if_else(is.na(xend), x + days(9), xend + days(5))
        )
}

make_plot <- function(history_with_calendar, this_year, heat_records, city, start_date, today) {

    font_add_google("Libre Franklin", "franklin")
    showtext_opts(dpi = 300)
    showtext_auto()

    fig_label <- make_fig_label(history_with_calendar)

    legend_data <- dummy_legend_data(this_year)


    history_with_calendar %>%
        ggplot(aes(x = date)) +
        geom_ribbon(
            aes(ymin = min, ymax = x5), 
            fill = "#2c7bb6",
            color = "grey30", 
            linewidth = 0.2
            ) +
        geom_ribbon(
            aes(ymin = x5, ymax = x25),
            fill = "#abd9e9",
            color = "grey30", 
            linewidth = 0.2
            ) +
        geom_ribbon(
            aes(ymin = x25, ymax = x75), 
            fill = "#ffffbf",
            color = "grey30", 
            linewidth = 0.2
            ) +
        geom_ribbon(
            aes(ymin = x75, ymax = x95), 
            fill = "#fdae61",
            color = "grey30", 
            linewidth = 0.2
            ) +
        geom_ribbon(
            aes(ymin = x95, ymax = max), 
            fill = "#d7191c",
            color = "grey30", 
            linewidth = 0.2
            ) +
        geom_line(
            aes(y = avg),
            color = "goldenrod", 
            linewidth = 1.0
            ) +
        # geom_point(
        #     data = this_year,
        #     aes(x = date, y = this_year_mean),
        #     color = c("black"),
        #     size = 0.35
            # linewidth = 0.6, 
            # bordercolor = "white",
            # borderwidth = 0.2, 
            # ) +
        geom_linerange(
            data = this_year,
            aes(x = date, ymin = this_year_min, ymax = this_year_max),
            color = c("black"),
            linewidth = 0.5, 
            # bordercolor = "white",
            # borderwidth = 0.2, 
            ) +
        geom_point(
            data = filter(new_records, new_record == "heat"),
            aes(x = date, y = this_year_max),
            color = "black",
            fill = "firebrick",
            shape = 21,
            inherit.aes = FALSE,
        ) +
        geom_point(
            data = filter(new_records, new_record == "cold"),
            aes(x = date, y = this_year_min),
            color = "black",
            fill = "dodgerblue",
            shape = 21,
            inherit.aes = FALSE,
        ) +
        geom_text(
            data = fig_label,
            aes(x = x, y = y, label = label), 
            hjust = 0,
            vjust = 0.35,
            size = 4.5,
            size.unit = "pt",
            family = "franklin",
            inherit.aes = FALSE
        ) +        
        geom_point(
            data = fig_label,
            aes(x = x, y = y),
            size = 0.3,
            inherit.aes = FALSE
        ) +
        geom_point( 
            data = filter(legend_data, is.na(xend)),
            aes(x = x, y = y), 
            shape = 21, 
            fill = c("firebrick", "dodgerblue")
        ) +
        geom_label(
            data = filter(legend_data, is.na(xend)), 
            aes(text_x, y, label = label),
            hjust = 0,
            size = 4, 
            size.unit = "pt", 
            family = "franklin", 
            fill = "white",
            label.size = 0
        ) +
        geom_segment(
            data = filter(legend_data, !is.na(xend)),
            aes(x = x, y = y, yend =yend, xend = xend), 
            linewidth = 0.6
        ) +
        geom_label(
            data = filter(legend_data, !is.na(xend)), 
            aes(text_x, y, label = label),
            hjust = 0,
            size = 4, 
            size.unit = "pt", 
            family = "franklin", 
            fill = "white",
            label.size = 0
        ) +
        scale_x_date(
            breaks = breaks_width("1 month"), 
            labels = date_format("%b")
            ) +
        scale_y_continuous(
            breaks = breaks_pretty(), 
            labels = label_number(
                suffix = "\u00B0C", 
                style_negative = "minus"
            )
        ) +
        labs(
            x = NULL, 
            y = NULL, 
         ) +
        coord_cartesian(expand = FALSE, clip = "off") +
        theme_classic() +
        theme(
            axis.line = element_blank(),
            axis.text = element_text(color = "black", size = 6),
            axis.ticks = element_blank(),
            panel.grid.major.x = element_line(
                linetype = "dotted", 
                color ="grey50"
            ),
            plot.caption.position = "plot",
            plot.caption = element_text(hjust = 0, size = 4, lineheight = 1.25),
            plot.margin = margin(t = 5, r = 55, b = 5, l = 5),
            plot.subtitle = element_text(margin = margin(b = 25), size = 10.5),
            plot.title = element_text(size = 12, face = "bold"), 
            plot.title.position = "plot", 
            text = element_text(family = "franklin")
        )

}




get_top_10_list <- function(filtered_data, type = "hottest") {

    if(type == "hottest") {
        filtered_data %>%
            summarize(
                temperature = max(hourly_temperature_2m),
                .by = date,
            ) %>%
            arrange(-temperature) %>%
            head(10)
    } else {
        filtered_data %>%
            summarize(
                temperature = min(hourly_temperature_2m),
                .by = date,
            ) %>%
            arrange(temperature) %>%
            head(10)
    }
}


get_new_records <- function(history_with_calendar, this_year) {

    history_with_calendar %>%
        left_join(this_year, by = join_by(date)) %>%
        select(date, max, min, this_year_max, this_year_min) %>%
        mutate(new_record = case_when(
            this_year_max > max ~ "heat", 
            this_year_min < min ~ "cold", 
            .default = NA
        )) %>%
        filter(!is.na(new_record))

}

make_fig_label <- function(history_with_calendar) {

    history_with_calendar %>%
        tail(1) %>%
        pivot_longer(-date, names_to = "label", values_to = "y") %>%
        rename(x = date) %>%
        mutate(
            label = case_when(
                label == "min" ~ "\u2014 Lowest", 
                label == "avg" ~ "\u2014 Average", 
                grepl("x\\d+", label) ~ paste0("\u2014 ", str_extract(label, '\\d+'), "th %"), 
                .default = "\u2014 Highest"
            )
        )


}

make_nice_date <- function(date) {
    glue("{day(date)} {month(date, label = TRUE)}, {year(date)}")
}

get_most_recent_date <- function(data) {
    data %>%
        pull(date) %>%
        max()
}

calculate_one_year_ago <- function(data) {

    most_recent_date <- get_most_recent_date(data)
    one_year_ago <- most_recent_date - days(364)
    all_days <- seq(one_year_ago, most_recent_date, by = 1)
    detect_leap_day <- str_detect(all_days, "\\d+-02-29")
    if (any(detect_leap_day)) {
        leap_day_position <- which(detect_leap_day)
        without_leap_day <- all_days[-leap_day_position]
        replacement_day <- min(all_days) - days(1)
        c(replacement_day, without_leap_day)
    } else {
        all_days
    }
}

get_historical_means <- function(filtered_data, today) {
    filtered_data %>%
        mutate(year = year(date)) %>%
        filter(year != year(today)) %>%
        summarize(temperature = mean(hourly_temperature_2m), .by = year)
}

get_most_extreme_year <- function(filtered_data, today, type = "hottest") {
    means <- get_historical_means(filtered_data, today)

    if (type == "hottest") {
        means_arranged <- means %>%
            arrange(-temperature)
    } else {
        means_arranged <- means %>%
            arrange(temperature)
    }

    means_arranged %>%
        head(1)
}

calculate_temperature_slope <- function(filtered_data, today) {
    means <- get_historical_means(filtered_data, today)
    lm(temperature ~ year, data = means) %>% 
        broom::tidy() %>%
        filter(term == "year") %>%
        pull(estimate) %>%
        round(3)
}
