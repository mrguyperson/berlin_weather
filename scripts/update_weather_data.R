# ================================================
# update_weather_data.R
# ================================================

library(bigrquery)
library(dplyr)
library(lubridate)
library(purrr)
library(tibble)
library(glue)
library(tidyr)
library(openmeteo)

# ----------------------------------------
# 1. AUTHENTICATION
# ----------------------------------------
if (nzchar(Sys.getenv("GCP_SERVICE_ACCOUNT_KEY"))) {
  message("Auth: using env service account key")
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
logtbl  <- "update_log"

bq_tbl      <- bq_table(project, dataset, table)
bq_log_tbl  <- bq_table(project, dataset, logtbl)

today_utc <- today(tzone = "UTC")
yesterday <- today_utc - days(1)

# ----------------------------------------
# 2. LOGGING HELPER
# ----------------------------------------
log_event <- function(action,
                      the_date = NA,
                      rows_written = NA_integer_,
                      model_from = NA_character_,
                      model_to   = NA_character_,
                      status = "ok",
                      error_message = NA_character_) {

  entry <- tibble(
    ts = with_tz(now(), "UTC"),
    action = action,
    the_date = as_date(the_date),
    rows_written = as.integer(rows_written),
    model_from = model_from,
    model_to = model_to,
    status = status,
    error_message = error_message
  )

  # Create log table if missing
  if (!bq_table_exists(bq_log_tbl)) {
    bq_table_create(
      bq_log_tbl,
      fields = entry,
      partitioning_type = "DAY",
      partitioning_field = "ts"
    )
  }

  bq_table_upload(
    bq_log_tbl,
    entry,
    write_disposition = "WRITE_APPEND",
    quiet = TRUE
  )
}

log_event("run_start")

# ----------------------------------------
# 3. helper functions
# ----------------------------------------

fetch_day_openmeteo <- function(day, api_model, label_model) {
  weather_history(
    location = "Berlin",
    start    = day,
    end      = day,
    hourly   = list("temperature_2m", "precipitation"),
    model    = api_model,
    timezone = "UTC"
  ) %>%
    mutate(
      date = as_date(datetime),
      model = label_model
    ) %>%
    # ensure that no other columns are added
    select(
      datetime,
      hourly_temperature_2m,
      hourly_precipitation,
      date,
      model
    )
}

is_full_clean_day <- function(df) {
  nrow(df) == 24 &&
    all(!is.na(df$hourly_temperature_2m)) &&
    all(!is.na(df$hourly_precipitation))
}

# ----------------------------------------
# 4. IDENTIFY NON-ERA5 DATES + LAST TABLE DATE
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
  pull(date) %>%
  as_date()

message("Non-ERA5 dates: ",
        if (length(non_era5_dates)) paste(non_era5_dates, collapse=", ") else "(none)")

log_event("non_era5_scan", rows_written = length(non_era5_dates))

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
# 5. ERA5 UPGRADE LOOP (preallocated, index-based)
# ----------------------------------------

era5_upgrades <- vector("list", length(non_era5_dates))

if (length(non_era5_dates) > 0) {

  for (i in seq_along(non_era5_dates)) {

    d <- non_era5_dates[[i]]

    message("Trying ERA5 upgrade ", d, " ...")

    df <- tryCatch(
      fetch_day_openmeteo(d, api_model = "era5", label_model = "era5"),
      error = function(e) {
        message("Error fetching ERA5 for ", d, ": ", e$message)
        log_event("era5_fetch_error", the_date = d, status = "error", error_message = e$message)
        NULL
      }
    )

    # Stop at first incomplete day
    if (is.null(df) || !is_full_clean_day(df)) {
      message("Stopping ERA5 upgrade at ", d, ": incomplete or NA.")
      log_event("era5_upgrade_stop", the_date = d, status = "stopped")

      # trim unused tail
      if (i > 1) {
        era5_upgrades <- era5_upgrades[1:(i - 1)]
      } else {
        era5_upgrades <- list()
      }

      break
    }

    era5_upgrades[[i]] <- df

    log_event("era5_upgraded",
              the_date = d,
              rows_written = nrow(df),
              model_from = "nonera5",
              model_to = "era5")

    message("Upgraded ", d, " to ERA5.")
  }
}

# remove NULLs
era5_upgrades <- Filter(Negate(is.null), era5_upgrades)

era5_upgrade_df <- if (length(era5_upgrades) > 0) {
  bind_rows(era5_upgrades)
} else {
  tibble()
}

# ----------------------------------------
# 6. NEW RECENT NONERA5 DAYS (yesterday only)
# ----------------------------------------

new_nonera5_df <- tibble()

if (!is.na(last_table_date) && yesterday > last_table_date) {

  # Only fetch full days, so yesterday
  new_days <- last_table_date + days(1)
  new_days <- new_days[new_days <= yesterday]

  fetched <- map(new_days, function(d) {

    df <- tryCatch(
      fetch_day_openmeteo(d, api_model = "best_match", label_model = "nonera5"),
      error = function(e) {
        log_event("nonera5_fetch_error", the_date = d, status = "error", error_message = e$message)
        NULL
      }
    )

    if (is.null(df)) return(NULL)

    if (is_full_clean_day(df)) {
      log_event("nonera5_new_full_day", the_date = d, rows_written = nrow(df))
      df
    } else {
      log_event("nonera5_new_incomplete", the_date = d, status = "skipped")
      NULL
    }
  })

  new_nonera5_df <- compact(fetched) %>% bind_rows()
}

# ----------------------------------------
# 7. STAGING
# ----------------------------------------

# If BOTH are empty, exit early
if (nrow(era5_upgrade_df) == 0 && nrow(new_nonera5_df) == 0) {
  message("No ERA5 upgrades and no new non-ERA5 data. Exiting.")
  log_event("nothing_to_upload")
  quit(save = "no")
}

staging <- bind_rows(era5_upgrade_df, new_nonera5_df) %>%
  arrange(datetime, desc(model)) %>%
  distinct(datetime, .keep_all = TRUE)

log_event("staged_rows", rows_written = nrow(staging))

# ----------------------------------------
# 8. DELETE NONERA5 FOR ERA5-UPGRADED DATES
# ----------------------------------------

if (nrow(era5_upgrade_df) > 0) {

  upgrade_dates <- unique(era5_upgrade_df$date)

  if (length(upgrade_dates) > 0) {

    date_list_sql <- paste0("DATE('", upgrade_dates, "')", collapse = ", ")

    delete_nonera5_sql <- glue("
      DELETE FROM `{project}.{dataset}.{table}`
      WHERE date IN ({date_list_sql})
        AND (model IS NULL OR model != 'era5')
    ")

    bq_project_query(project, delete_nonera5_sql)

    log_event("deleted_nonera5_for_upgrades",
              model_from = "nonera5",
              model_to = "era5",
              error_message = paste("Dates:", paste(upgrade_dates, collapse = ", ")))
  }
}

# ----------------------------------------
# 9. UPLOAD
# ----------------------------------------

bq_table_upload(
  x = bq_tbl,
  values = staging,
  write_disposition = "WRITE_APPEND",
  quiet = FALSE
)

log_event("uploaded_rows", rows_written = nrow(staging))

# ----------------------------------------
# 10. FINAL DEDUPE (remove nonERA5 when ERA5 exists)
# ----------------------------------------

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

bq_project_query(project, cleanup_sql)

log_event("dedupe_cleanup_done")

log_event("run_end")

message("✅ Update complete.")