# Load packages required to define the pipeline:
library(targets)

# Set target options:
tar_option_set(
  packages = c("tidyverse", "openmeteo", "glue") 
)

# Run the R scripts in the R/ folder with your custom functions:
tar_source()

list(
  tar_target(
    name = city,
    command = "Berlin"
  ), 
  tar_target(
    name = lat,
    command = geocode(city)$latitude
  ),
  tar_target(
    name = long,
    command = geocode(city)$longitude
  ),
  tar_target(
    name = country,
    command = geocode(city)$country
  ),
  tar_target(
    name = start_date,
    command = "1940-01-01"
  ),
  tar_target(
    name = today,
    command = lubridate::today(),
    cue = tar_cue(mode = "always")
  ),
  tar_target(
    name = raw_data,
    command = get_raw_data(city, start_date, today)
  ),
  tar_target(
    name = filtered_data,
    command = filter_data(raw_data)
  ),
  tar_target(
    name = historical_data,
    command = make_historical_data(filtered_data, today)
  ),
  tar_target(
    name = calendar,
    command = make_calendar(today)
  ),
  tar_target(
    name = this_year,
    command = get_this_year(filtered_data)
  ),
  tar_target(
    name = history_with_calendar,
    command = add_calendar_to_historical(calendar, historical_data)
  ),
  tar_target(
    name = new_records,
    command = get_new_records(history_with_calendar, this_year)
  ),
  tar_target(
    name = top_10_hottest,
    command = get_top_10_list(filtered_data, type = "hottest")
  ),
  tar_target(
    name = top_10_coldest,
    command = get_top_10_list(filtered_data, type = "coldest")
  ),
  tar_target(
    name = hottest_year,
    command = get_most_extreme_year(filtered_data, today, "hottest")
  ),
  tar_target(
    name = coldest_year,
    command = get_most_extreme_year(filtered_data, today, "coldest")
  ),
  tar_target(
    name = temperature_slope,
    command = calculate_temperature_slope(filtered_data, today)
  )
)