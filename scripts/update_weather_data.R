library(bigrquery)
library(dplyr)
library(lubridate)
library(readr)
library(openmeteo)

project <- "peaceful-parity-476712-q0"
dataset <- "berlin_weather"
table <- "daily_observations_partitioned"

# Authenticate
# bq_auth(json_file = Sys.getenv("GCP_SERVICE_ACCOUNT_KEY"))
bq_auth(path = "peaceful-parity-476712-q0-e0413d71db46.json")

# Get the most recent date in BigQuery
latest_date_query <- glue::glue("
  SELECT MAX(DATE(datetime)) AS latest_date
  FROM `{project}.{dataset}.{table}`
")

latest_date <- bq_project_query(project, latest_date_query) %>%
  bq_table_download() %>%
  pull(latest_date)

# If the table is empty, set a fallback start date
if (is.na(latest_date)) latest_date <- as_date("1940-01-01")

# Quit if table already up to date
if (latest_date + 1 == today()) {
  message("No new days to fetch — data already up to date.")
  quit(save = "no")
}

# Fetch only the missing dates from API
city <- "Berlin"
hourly_params <- c("temperature_2m", "precipitation")

message_contents <- glue::glue("Fetching data ({paste(hourly_params, collapse = ', ')}) for {city}")

message(message_contents)

new_data <- weather_history(city, start = latest_date + 1, end = today() - 1, hourly_params)

# 4. Clean and append to BigQuery
cleaned <- new_data %>%
  mutate(datetime = as_datetime(datetime)) %>%
  arrange(datetime)

bq_table_upload(
  x = bq_table(project, dataset, table),
  values = cleaned,
  write_disposition = "WRITE_APPEND"
)

message("Uploaded ", nrow(cleaned), " new rows covering ",
        paste0(min(dates_to_fetch), " to ", max(dates_to_fetch)))
