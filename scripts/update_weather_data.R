# ================================================
# update_weather_data.R
# Complete corrected script
# ================================================

library(bigrquery)
library(dplyr)
library(lubridate)
library(purrr)
library(tibble)
library(glue)
library(tidyr)

# ----------------------------------------
# 1. AUTHENTICATION
# ----------------------------------------
if (nzchar(Sys.getenv("GCP_SERVICE_ACCOUNT_KEY"))) {
  message("Auth: using service account from env")
  tmp <- tempfile(fileext = ".json")
  writeLines(Sys.getenv("GCP_SERVICE_ACCOUNT_KEY"), tmp)
  bq_auth(path = tmp)
} else {
  message("Auth: using local key file")
  bq_auth(path = "keys/weather-dashboard-key.json")
}

project <- "peaceful-parity-476712-q0"
dataset <- "berlin_weather"
table   <- "daily_observations"
bq_tbl  <- bq_table(project, dataset, table)

today_utc <- today(tzone = "UTC")
yesterday <- today_utc - days(1)

# ----------------------------------------
# 2. Helper functions
# ----------------------------------------

# Fetch a day's data
fetch_day_openmeteo <- function(day, api_model, label_model) {
  weather_history(
    location = "Berlin",
    start = day,
    end   = day,
    hourly   = list("temperature_2m", "precipitation"),
    model    = api_model,        # "era5" explicitly OR "best_match"
    timezone = "UTC"
  ) %>%
  mutate(
    date = as_date(datetime),
    model = label_model
  )
}

# Check 24-hour completeness + no NAs
is_full_clean_day <- function(df_day) {
  nrow(df_day) == 24 &&
    all(!is.na(df_day$hourly_temperature_2m)) &&
    all(!is.na(df_day$hourly_precipitation))
}

# ----------------------------------------
# 3. Identify non-ERA5 rows and last table date
# ----------------------------------------

non_era5_dates <- bq_table_download(
  bq_project_query(
    project,
    glue("
      SELECT DISTINCT date
      FROM `{project}.{dataset}.{table}`
      WHERE model IS NULL OR model != 'era5'
    ")
  )
) %>%
  mutate(date = as_date(date)) %>%
  arrange(date) %>%
  pull(date)

message("Non-ERA5 dates: ",
        if (length(non_era5_dates)) paste(non_era5_dates, collapse=", ") else "(none)")

last_table_date_tbl <- bq_table_download(
  bq_project_query(
    project,
    glue("SELECT MAX(date) AS last_date FROM `{project}.{dataset}.{table}`")
  )
)
last_table_date <- as_date(last_table_date_tbl$last_date)

message("Last date in table: ",
        ifelse(is.na(last_table_date), "(empty)", as.character(last_table_date)))

# ----------------------------------------
# 4. ERA5 upgrade pass over existing non-ERA5 dates
# ----------------------------------------

era5_upgrades <- vector("list", length(non_era5_dates))

if (length(non_era5_dates) > 0) {
  for (d in seq_along(non_era5_dates)) {

    message("Trying ERA5 upgrade ", non_era5_dates[[d]], " ...")

    df <- tryCatch(
      fetch_day_openmeteo(non_era5_dates[[d]], api_model="era5", label_model="era5"),
      error = function(e) {
        message("Error fetching ERA5 for ", non_era5_dates[[d]], ": ", e$message)
        NULL
      }
    )

    # Incomplete or NA → stop upgrading further
    if (is.null(df) || !is_full_clean_day(df)) {
      message("Stopping ERA5 upgrade at ", non_era5_dates[[d]], ": incomplete or NA.")
      break
    }

    # Good → store it
    era5_upgrades[[d]] <- df
    message("Upgraded ", non_era5_dates[[d]], " to ERA5.")
  }
}

era5_upgrade_df <- 
  if (length(era5_upgrades) > 0) bind_rows(era5_upgrades) else tibble()

# ----------------------------------------
# 5. New days after last_table_date up to yesterday (nonERA5)
# ----------------------------------------

new_nonera5_df <- tibble()

if (!is.na(last_table_date)) {

  if (yesterday > last_table_date) {
    new_days <- seq(last_table_date + days(1), yesterday, by="1 day")

    message("New days to fetch (nonERA5): ", paste(new_days, collapse=", "))

    new_fetched <- map(new_days, function(d) {

      df <- tryCatch(
        fetch_day_openmeteo(d, api_model="best_match", label_model="nonera5"),
        error = function(e) {
          message("Error fetching new nonERA5 for ", d, ": ", e$message)
          NULL
        }
      )

      if (is.null(df)) return(NULL)
      if (is_full_clean_day(df)) df else {
        message("Skipping ", d, ": incomplete (not 24 clean hours)")
        NULL
      }
    })

    new_nonera5_df <- compact(new_fetched) %>% bind_rows()

  } else {
    message("No new days to fetch; table is up-to-date to >= yesterday.")
  }
}

# ----------------------------------------
# 6. Combine staged data
# ----------------------------------------

staging <- bind_rows(era5_upgrade_df, new_nonera5_df)

if (nrow(staging) == 0) {
  message("No data to upload.")
  quit(save="no")
}

# Deduplicate timestamps: ERA5 wins (sorted descending model)
staging <- staging %>%
  arrange(datetime, desc(model)) %>%
  distinct(datetime, .keep_all = TRUE)

message("Rows staged for upload: ", nrow(staging))

# ----------------------------------------
# 7. Delete old nonERA5 rows for upgraded dates
# ----------------------------------------

if (nrow(era5_upgrade_df) > 0) {

  upgrade_dates <- unique(era5_upgrade_df$date)

  if (length(upgrade_dates) > 0) {
    message("Deleting nonERA5 rows for upgraded dates: ",
            paste(upgrade_dates, collapse=", "))

    date_list_sql <- paste0("DATE('", upgrade_dates, "')", collapse=", ")

    delete_nonera5_sql <- glue("
      DELETE FROM `{project}.{dataset}.{table}`
      WHERE date IN ({date_list_sql})
        AND (model IS NULL OR model != 'era5')
    ")

    bq_project_query(project, delete_nonera5_sql)
  }

} else {
  message("No ERA5 upgrades performed; no deletion of nonERA5 rows needed.")
}

# ----------------------------------------
# 8. Upload staged rows
# ----------------------------------------

message("Uploading ", nrow(staging), " rows to BigQuery...")

bq_table_upload(
  x = bq_tbl,
  values = staging,
  write_disposition = "WRITE_APPEND",
  quiet = FALSE
)

# ----------------------------------------
# 9. Final cleanup: remove any nonERA5 duplicates where ERA5 exists
# ----------------------------------------
if (nrow(era5_upgrade_df) > 0) {
  cleanup_sql <- glue("
    DELETE FROM `{project}.{dataset}.{table}` t
    WHERE (t.model IS NULL OR t.model != 'era5')
      AND EXISTS (
        SELECT 1
        FROM `{project}.{dataset}.{table}` s
        WHERE s.datetime = t.datetime
          AND s.model = 'era5'
      )
  ")

  message("Final cleanup: removing nonERA5 duplicates...")
  bq_project_query(project, cleanup_sql)
}
message("✅ Update complete.")
