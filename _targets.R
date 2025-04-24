# Load packages required to define the pipeline:
library(targets)
# library(tarchetypes) # Load other packages as needed.

# Set target options:
tar_option_set(
  packages = c("tidyverse", "openmeteo", "scales", "glue", "showtext", "ggborderline") # Packages that your targets need for their tasks.
  # format = "qs", # Optionally set the default storage format. qs is fast.
  #
  # Pipelines that take a long time to run may benefit from
  # optional distributed computing. To use this capability
  # in tar_make(), supply a {crew} controller
  # as discussed at https://books.ropensci.org/targets/crew.html.
  # Choose a controller that suits your needs. For example, the following
  # sets a controller that scales up to a maximum of two workers
  # which run as local R processes. Each worker launches when there is work
  # to do and exits if 60 seconds pass with no tasks to run.
  #
  #   controller = crew::crew_controller_local(workers = 2, seconds_idle = 60)
  #
  # Alternatively, if you want workers to run on a high-performance computing
  # cluster, select a controller from the {crew.cluster} package.
  # For the cloud, see plugin packages like {crew.aws.batch}.
  # The following example is a controller for Sun Grid Engine (SGE).
  # 
  #   controller = crew.cluster::crew_controller_sge(
  #     # Number of workers that the pipeline can scale up to:
  #     workers = 10,
  #     # It is recommended to set an idle time so workers can shut themselves
  #     # down if they are not running tasks.
  #     seconds_idle = 120,
  #     # Many clusters install R as an environment module, and you can load it
  #     # with the script_lines argument. To select a specific verison of R,
  #     # you may need to include a version string, e.g. "module load R/4.3.2".
  #     # Check with your system administrator if you are unsure.
  #     script_lines = "module load R"
  #   )
  #
  # Set other options as needed.
)

# Run the R scripts in the R/ folder with your custom functions:
tar_source()
today <- lubridate::today()

list(
  tar_target(
    name = data,
    command = tibble(x = rnorm(100), y = rnorm(100))
    # format = "qs" # Efficient storage for general data objects.
  ),
  tar_target(
    name = city,
    command = "Berlin"
  ), 
  tar_target(
    name = start_date,
    command = "1940-01-01"
  ),
  # tar_target(
  #   name = today,
  #   command = today()
  # ),
  tar_target(
    name = raw_data,
    command = get_raw_data(city, start_date, today)
  ),
  tar_target(
    name = historical_data,
    command = make_historical_data(raw_data, today)
  ),
  tar_target(
    name = calendar,
    command = make_calendar(today)
  ),
  tar_target(
    name = this_year,
    command = get_this_year(raw_data, today)
  ),
  tar_target(
    name = history_with_calendar,
    command = add_calendar_to_historical(calendar, historical_data)
  ),
  tar_target(
    name = heat_records,
    command = get_new_heat_records(history_with_calendar, this_year)
  ),
  tar_target(
    name = plot,
    command = make_plot(
      history_with_calendar, 
      this_year, 
      heat_records, 
      city, 
      start_date,
      today),
    format = "file"
  ),
  tar_target(
    name = top_10,
    command = get_top_10_hottest(raw_data)
  )
)
