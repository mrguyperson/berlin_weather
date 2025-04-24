# library(openmeteo)
# library(tidyverse)
# library(scales)
# library(glue)
# library(showtext)
# library(ggborderline)




# city <- "Berlin"

# start_date <- "1940-01-01"

get_raw_data <- function(city, start_date, today, hourly = "temperature_2m") {

    weather_history(city, start = start_date, end = today, hourly)


}
# daily_min_max <- data %>%
#     mutate(
#         year = year(datetime),
#         month = month(datetime),
#         day = day(datetime),
#         date = ymd(glue::glue("{year}-{month}-{day}"))) %>%
#     filter(year != year(today())) %>% 
#     summarize(
#         min = min(hourly_temperature_2m, na.rm = T),
#         max = max(hourly_temperature_2m, na.rm = T),
#         x5 = quantile(hourly_temperature_2m, 0.05, na.rm = T),
#         x20 = quantile(hourly_temperature_2m, 0.2, na.rm = T),
#         x40 = quantile(hourly_temperature_2m, 0.4, na.rm = T),
#         x60 = quantile(hourly_temperature_2m, 0.6, na.rm = T),
#         x80 = quantile(hourly_temperature_2m, 0.8, na.rm = T),
#         x95 = quantile(hourly_temperature_2m, 0.95, na.rm = T),
#         .by = c(month, day)
#     )

# data %>%
#     mutate(
#         year = year(datetime)) %>%
#     filter(year != year(today())) %>%
#     summarize(
#         temperature = mean(hourly_temperature_2m, na.rm = TRUE), 
#         .by = year
#     ) %>%
#     ggplot(aes(x = year, y = temperature)) +
#     geom_line()

# year_temp <- data %>%
#     mutate(
#         year = year(datetime)) %>%
#     filter(year != year(today())) %>%
#     summarize(
#         yearly_mean = mean(hourly_temperature_2m, na.rm = TRUE), 
#         .by = year
#     )

# data %>%
#     mutate(
#         year = year(datetime),
#         month = month(datetime, label = TRUE), 
#         day = yday(datetime)) %>%
#     filter(year != year(today())) %>%
#     summarize(
#         temperature = mean(hourly_temperature_2m, na.rm = TRUE), 
#         .by = c(year, day)
#     ) %>%
#     left_join(year_temp, by = join_by(year)) %>%
#     ggplot(aes(x = day, y = temperature, group = year, color = yearly_mean)) +
#     geom_line(show.legend = FALSE, alpha = 0.25) +
#     scale_color_viridis_c() +
#     theme_classic()

make_historical_data <- function(raw_data, today) {

    raw_data %>%
        drop_na() %>%
        mutate(
            year = year(datetime),
            month = month(datetime),
            mday = mday(datetime)
        ) %>%
        filter(
            year != year(today),
            !(month == 2 & mday == 29)
            ) %>%
        summarize(
            min = min(hourly_temperature_2m), 
            x5 = quantile(hourly_temperature_2m, 0.05),
            x20 = quantile(hourly_temperature_2m, 0.2),
            x40 = quantile(hourly_temperature_2m, 0.4),
            median = median(hourly_temperature_2m),
            x60 = quantile(hourly_temperature_2m, 0.6),
            x80 = quantile(hourly_temperature_2m, 0.8),
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


get_this_year <- function(raw_data, today) {
    
    raw_data %>%
        drop_na() %>%
        filter(
            year(datetime) == year(today), 
            !(month(datetime) == 2 & mday(datetime) == 29)
            ) %>%
        mutate(
            date = as_date(datetime), 
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

make_plot <- function(history_with_calendar, this_year, heat_records, city, start_date, today) {

    font_add_google("Libre Franklin", "franklin")
    showtext_opts(dpi = 300)
    showtext_auto()

    fig_label <- make_fig_label(history_with_calendar)

    p <- history_with_calendar %>%
        ggplot(aes(x = date)) +
        geom_ribbon(
            aes(ymin = min, ymax = x5), 
            fill = "#4575b4",
            color = "grey30", 
            linewidth = 0.2
            ) +
        geom_ribbon(
            aes(ymin = x5, ymax = x20),
            fill = "#91bfdb",
            color = "grey30", 
            linewidth = 0.2
            ) +
        geom_ribbon(
            aes(ymin = x20, ymax = x40), 
            fill = "#e0f3f8",
            color = "grey30", 
            linewidth = 0.2
            ) +
        geom_ribbon(
            aes(ymin = x40, ymax = x60), 
            fill = "#ffffbf",
            color = "grey30", 
            linewidth = 0.2
            ) +
        geom_ribbon(
            aes(ymin = x60, ymax = x80), 
            fill = "#fee090",
            color = "grey30", 
            linewidth = 0.2
            ) +
        geom_ribbon(
            aes(ymin = x80, ymax = x95), 
            fill = "#fc8d59",
            color = "grey30", 
            linewidth = 0.2
            ) +
        geom_ribbon(
            aes(ymin = x95, ymax = max), 
            fill = "#d73027",
            color = "grey30", 
            linewidth = 0.2
            ) +
        # geom_line(
        #     aes(y = median),
        #     color = "gold", 
        #     linewidth = 1.5
        #     ) +
        # geom_line(
        #     data = this_year, 
        #     mapping = aes(x = day, y = min),
        #     color = "#313695") +
        geom_borderline(
            data = this_year,
            aes(x = date, y = this_year_max),
            color = "black", 
            linewidth = 0.6, 
            borderwidth = 0.2, 
            ) +
        geom_point(
            data = heat_records,
            aes(x = date, y = this_year_max),
            color = "black",
            fill = "forestgreen",
            shape = 21,
            inherit.aes = FALSE,
        ) +
        geom_text(
            data = fig_label,
            aes(x = x, y = y, label = label), 
            hjust = 0,
            vjust = 0.35,
            size = 5,
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
            title = glue("Daily temperatures in {city} since {make_nice_date(start_date)}"), 
            caption = 
                glue(
                    "Most recent data from {make_nice_date(get_most_recent_data(this_year))}.
                    Last updated {make_nice_date(today)}."
                    )
        ) +
        coord_cartesian(expand = FALSE, clip = "off") +
        theme_classic() +
        theme(
            axis.line = element_blank(),
            axis.text = element_text(color = "black"),
            axis.ticks = element_blank(),
            panel.grid.major.x = element_line(
                linetype = "dotted", 
                color ="grey50"
            ),
            plot.caption.position = "plot",
            plot.caption = element_text(hjust = 0, size = 6),
            plot.margin = margin(t = 5, r = 60, b = 5, l = 5),
            plot.title = element_text(size = 16, face = "bold"), 
            plot.title.position = "plot", 
            text = element_text(family = "franklin")
        )

    path <- "test.png"
    ggsave(path, p, width = 8, height = 4)
    path
}




get_top_10_hottest <- function(raw_data) {
    raw_data %>%
        drop_na() %>%
        mutate(
            date = as_date(datetime)
            ) %>%
        summarize(
            temperature = max(hourly_temperature_2m),
            .by = date,
        ) %>%
        arrange(-temperature) %>%
        head(10)
}


get_new_heat_records <- function(history_with_calendar, this_year) {

    history_with_calendar %>%
        left_join(this_year, by = join_by(date)) %>%
        select(date, max, this_year_max) %>%
        mutate(new_record = this_year_max > max) %>%
        filter(new_record)

}

make_fig_label <- function(history_with_calendar) {

    history_with_calendar %>%
        tail(1) %>%
        pivot_longer(-date, names_to = "label", values_to = "y") %>%
        rename(x = date) %>%
        filter(label != "median") %>%
        mutate(
            label = case_when(
                label == "min" ~ "\u2014 Lowest recorded", 
                grepl("x95", label) ~ "\u2014 95th percentile", 
                grepl("x\\d+", label) ~ paste0("\u2014 ", str_extract(label, '\\d+'), "th"), 
                .default = "\u2014 Highest recorded"
            )
        )


}

make_nice_date <- function(date) {
    glue("{day(date)} {month(date, label = TRUE)}, {year(date)}")
}

get_most_recent_data <- function(this_year) {
    this_year %>%
        pull(date) %>%
        max()
}