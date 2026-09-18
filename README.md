# Berlin Weather

A reproducible R data pipeline and Quarto dashboard that compares current weather in Berlin with its historical context.

The dashboard answers a simple question:

> **How unusual is today’s weather in Berlin compared with the same time of year over the historical record?**

Rather than showing only a conventional forecast, the project retrieves hourly weather observations, builds historical distributions, and presents current conditions alongside long-term patterns.

## Why this project exists

Daily weather reports are good at telling us what the temperature is, but not necessarily what that temperature means.

A 20 °C day can be ordinary in July and remarkable in February. This project provides that context by comparing recent Berlin weather with historical observations dating back to 1940.

The project also serves as a practical example of a reproducible analytical workflow. It is designed so that data retrieval, validation, transformation, testing, visualization, and publication are automated and can be recreated from a clean environment.

## How it works

The project uses an R `{targets}` pipeline to coordinate the full workflow:

```text
Open-Meteo
    ↓
retrieve weather data
    ↓
validate API responses
    ↓
clean and filter observations
    ↓
build historical weather summaries
    ↓
compare current weather with history
    ↓
render Quarto dashboard
    ↓
publish automatically
```

### Data retrieval

Weather observations come from the [Open-Meteo](https://open-meteo.com/) historical weather API.

The pipeline is split into two ingestion branches:

```text
Historical baseline
1940-01-01 → December 31 of the previous year

Current year
January 1 → today
```

The stable historical portion can therefore be reused rather than downloading the entire multi-decade dataset every day.

Each API response is validated independently before the datasets are combined. Validation checks include required columns, usable timestamps, numeric temperature data, and the presence of valid observations.

Transient retrieval failures are retried with bounded backoff, while malformed data fails validation rather than being silently repaired.

### Data processing

The project uses `{targets}` to describe dependencies between analytical steps.

This provides:

* automatic dependency tracking;
* incremental rebuilding when inputs change;
* persistent intermediate results;
* reproducible execution order; and
* visibility into which parts of the analysis need to rerun.

Daily publication normally requires retrieving only the current year's observations. Historical targets can be restored from the GitHub Actions cache and skipped when unchanged.

### Dashboard

The final dashboard is written in [Quarto](https://quarto.org/) and generated from the processed `{targets}` outputs.

It presents current Berlin weather in the context of the historical record rather than as isolated measurements.

## Reproducibility

The project supports two reproducibility paths.

### Docker / Dev Container

The canonical environment is defined by the root `Dockerfile`.

It includes:

* R 4.4.3;
* Quarto;
* required Linux system libraries;
* Python and radian; and
* the exact R dependency set restored from `renv.lock`.

The same container environment is used for automated workflows and interactive development.

The container image is published to GitHub Container Registry:

```text
ghcr.io/mrguyperson/weather-image
```

The rolling development image is tagged:

```text
latest
```

Builds are also tagged with their Git commit SHA so a specific source revision can be associated with a specific environment image.

### Native R with renv

Users who do not want to use Docker can recreate the R package environment with [`renv`](https://rstudio.github.io/renv/).

With R 4.4.x installed:

```r
renv::restore()
```

`renv.lock` records the exact R package versions used by the project, while `DESCRIPTION` declares the project's direct runtime and development dependencies.

A native installation still requires compatible system libraries and Quarto to be installed separately; the Docker image provides the more complete environment definition.

## Development environment

VS Code development uses a Dev Container built from the same canonical image used elsewhere in the project.

The image contains an immutable R package library representing the committed `renv.lock`.

Interactive development runs as a non-root `vscode` user so files created in the workspace remain owned by the host user rather than by root.

Branch-specific package changes can use a writable development library layered in front of the canonical image library:

```text
Writable development library
        ↓
packages changed on the current branch

Canonical /opt/renv/library
        ↓
packages already provided by the image
```

This makes it possible to experiment with dependency changes without modifying the canonical environment inside the running container.

A typical dependency update is:

1. Add the direct dependency to `DESCRIPTION`.
2. Install it with `renv::install()`.
3. Test the change.
4. Run `renv::snapshot()`.
5. Commit `DESCRIPTION` and `renv.lock`.
6. Merge the change.
7. Let GitHub Actions rebuild the canonical image from the new lockfile.

## Testing

Unit and regression tests use `{testthat}`.

The test suite covers behavior including:

* Open-Meteo response validation;
* malformed timestamps and invalid temperature data;
* handling of partially missing observations;
* historical/current-year boundary calculations;
* recombination of independently retrieved datasets;
* weather filtering behavior;
* order-independent removal of incomplete final dates;
* retry behavior for transient retrieval failures; and
* retrieval observability.

Tests are offline and deterministic: they use injected fake retrieval functions rather than deliberately making failing network requests.

Run the full suite with:

```r
testthat::test_dir("tests/testthat")
```

or in the canonical container:

```bash
docker run --rm \
  --mount type=bind,src="$PWD",dst=/project,readonly \
  --workdir /project \
  berlin-weather-test \
  Rscript -e 'testthat::test_dir("tests/testthat")'
```

## Continuous integration and publication

GitHub Actions handles several distinct jobs.

### Tests

Pull requests build the proposed root `Dockerfile` and run the complete test suite.

This is deliberate: a pull request that changes the environment should test the proposed environment rather than the previously published container image.

Docker layer caching reduces repeated installation work between CI runs.

### Environment image

Changes to environment-defining files trigger a rebuild of the canonical container image, including changes to:

```text
Dockerfile
renv.lock
.Rprofile
renv/activate.R
renv/settings.json
```

The resulting image is published to GitHub Container Registry.

### Daily dashboard update

The publication workflow restores the `{targets}` state when available, retrieves current weather data, rebuilds affected analytical targets, and publishes the updated Quarto dashboard.

The cache is intentionally structured so that stable historical weather data can be reused while current-year observations continue to update.

## Repository structure

```text
.
├── R/
│   └── functions.R          # Retrieval, validation and analysis functions
├── tests/
│   └── testthat/            # Unit and regression tests
├── .github/
│   └── workflows/           # CI, image build and publication automation
├── .devcontainer/           # VS Code Dev Container configuration
├── _targets.R               # targets pipeline definition
├── index.qmd                # Quarto dashboard
├── Dockerfile               # Canonical runtime environment
├── DESCRIPTION              # Direct R dependencies
├── renv.lock                # Exact R dependency versions
└── AGENTS.md                # Repository guidance for coding agents
```

Generated `{targets}` state is not edited manually.

## Running the project

With the required environment available, run the pipeline with:

```r
targets::tar_make()
```

Render the dashboard with:

```bash
quarto render index.qmd
```

A completely clean pipeline run requires network access because the project retrieves external data from services including Open-Meteo and geocoding services.

## Design principles

Several choices in this project are intentional.

**Validate external data at the boundary.**
Unexpected API responses should fail clearly before entering the analytical pipeline.

**Retry infrastructure failures, not bad data.**
Transient network failures can be retried. A successfully retrieved but invalid response should fail validation.

**Prefer deterministic automation to agentic automation.**
Daily work is handled by `{targets}`, Docker, and GitHub Actions. Coding agents are used for development, investigation, testing, and maintenance rather than as part of the production data pipeline.

**Keep the analytical environment explicit.**
`DESCRIPTION` declares direct dependencies, `renv.lock` fixes package versions, and Docker defines the surrounding system environment.

**Test bugs before fixing them.**
Regression tests reproduce identified failures before production code is changed, so fixed behavior remains protected.

**Avoid unnecessary recomputation.**
Stable historical data, Docker layers, and target metadata are cached where doing so does not compromise correctness.

## Technology

The project primarily uses:

* R
* `{targets}`
* `{tidyverse}`
* `{openmeteo}`
* `{testthat}`
* `{renv}`
* Quarto
* Docker
* VS Code Dev Containers
* GitHub Actions
* GitHub Container Registry

## Status

This is an actively maintained personal project. In addition to the dashboard itself, it is used to explore reproducible scientific computing, data-pipeline reliability, automated testing, and containerized development workflows.
