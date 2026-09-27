compact_weather_fixture <- function() {
    timezone <- "Europe/Berlin"
    hourly_grid <- function(dates) {
        as.POSIXct(
            sprintf(
                "%s %02d:00:00",
                rep(as.character(dates), each = 24),
                rep(0:23, times = length(dates))
            ),
            format = "%Y-%m-%d %H:%M:%S",
            tz = timezone
        )
    }

    historical_dates <- seq(
        as.Date("2021-01-01"), as.Date("2023-12-31"), by = "day"
    )
    historical_raw <- tibble::tibble(
        datetime = hourly_grid(historical_dates),
        hourly_temperature_2m = rep(c(0, 2, 4), each = 365 * 24)
    )

    clock_labels <- format(
        historical_raw$datetime, "%Y-%m-%d %H:%M:%S", tz = timezone
    )
    jan1 <- startsWith(clock_labels, "2021-01-01 ")
    jan2 <- startsWith(clock_labels, "2022-01-02 ")
    historical_raw$hourly_temperature_2m[jan1] <- -1000
    historical_raw$hourly_temperature_2m[jan2] <- 1000
    # A missing hour and a duplicate retain 24 rows but fail the wall-clock contract.
    historical_raw$datetime[clock_labels == "2022-01-02 04:00:00"] <-
        historical_raw$datetime[clock_labels == "2022-01-02 03:00:00"]
    historical_raw <- historical_raw[!clock_labels %in% c(
        "2021-01-01 00:00:00", "2021-01-01 01:00:00"
    ), ]
    historical_raw <- dplyr::bind_rows(
        historical_raw,
        tibble::tibble(
            datetime = hourly_grid(as.Date("2024-02-29")),
            hourly_temperature_2m = rep(1000, 24)
        )
    )

    current_dates <- as.Date(c(
        "2025-09-16", "2025-09-17", "2025-09-18", "2025-09-19"
    ))
    current_raw <- tibble::tibble(
        datetime = hourly_grid(current_dates),
        hourly_temperature_2m = c(
            rep(c(-20, 4), 12),
            rep(c(0, 20), 12),
            rep(c(0, 20), 12),
            rep(c(-100, 100), 12)
        )
    )

    list(
        historical_raw = historical_raw,
        current_raw = current_raw,
        today = as.Date("2025-09-19"),
        reference_time = as.POSIXct(
            "2025-09-19 12:00:00", tz = timezone
        )
    )
}
