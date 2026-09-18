# Berlin Weather

Berlin Weather is an automated R and Quarto dashboard that compares recent weather in Berlin with observations from a historical record beginning in 1940. Its central idea is simple: a temperature is more meaningful when placed in seasonal and historical context. A 20 °C day may be routine in July and exceptional in February.

**[View the live dashboard](https://mrguyperson.quarto.pub/berlin_weather)**

The dashboard shows the current year's daily temperature ranges against long-term daily distributions, identifies new heat and cold records, lists extreme observed temperatures, and summarizes the hottest year, coldest year, and long-run annual temperature trend. Leap days are excluded so calendar days align consistently across years.

## Why this project exists

Most weather products answer “what is it now?” or “what happens next?” They do not necessarily explain whether a measurement is ordinary for this point in the year. This dashboard adds that context by comparing Berlin's recent conditions with more than eight decades of hourly observations.

The repository also demonstrates the engineering around a reproducible scientific-data product. Data ingestion, boundary validation, transformation, testing, dependency-aware caching, environment construction, rendering, and publication are defined in code and automated. The result is both a useful dashboard and an inspectable example of how to make a recurring analysis reliable without hiding its assumptions.

## How it works

```text
Open-Meteo
    ↓
retrieval + validation
    ↓
{targets} pipeline
    ↓
historical context + summaries
    ↓
Quarto dashboard
    ↓
automated publication
```

Open-Meteo supplies hourly `temperature_2m` observations. The pipeline retrieves the long-lived and frequently changing parts separately:

- the historical branch covers 1 January 1940 through 31 December of the previous year;
- the current-year branch covers 1 January of the current year through today.

Each response passes through `validate_raw_data()` before the datasets are combined. The boundary checks that a response is data-frame-like and non-empty, contains the expected datetime and temperature columns, has numeric temperatures and parseable non-missing datetimes, and includes at least one usable observation. It does not require every row to be complete: partially missing observations may pass the boundary check and are removed during filtering. Malformed responses fail explicitly rather than being repaired or replaced with invented values.

Retrieval uses a 60-second HTTP timeout and bounded exponential backoff, with at most three attempts by default. Only errors raised while retrieving are retried; a successfully retrieved but invalid response reaches validation and fails without another network request.

After ingestion, the pipeline removes incomplete rows and leap-day observations, calculates historical distributions for each calendar day, and derives the current-year ranges, records, extremes, and annual trend used by the dashboard. The most recent date is omitted from the current-year display if it does not contain 24 hourly rows.

[`{targets}`](https://docs.ropensci.org/targets/) declares the dependencies between these steps, persists intermediate results, and rebuilds only targets whose inputs have changed. The daily GitHub Actions workflow restores target objects and metadata from a year- and source-sensitive cache. This allows the stable historical branch to be reused when its inputs are unchanged while the always-cued date and dependent current-year results update. Quarto then reads the completed targets store and renders the dashboard for publication to Quarto Pub.

## Reproducible environment

The environment is described at complementary levels:

- `DESCRIPTION` declares the project's direct R runtime and development dependencies.
- `renv.lock` records the exact resolved R package versions and the R version used to create the lockfile.
- The root `Dockerfile` is the canonical runtime and build definition: it starts from R 4.4.3, installs required Linux libraries, Python and radian, installs Quarto 1.10.18 from a version-specific release asset verified against its pinned SHA-256 checksum, and restores the locked R library.
- GitHub Actions publishes that image to `ghcr.io/mrguyperson/weather-image`, using both the rolling `latest` tag and commit-SHA tags.
- `.devcontainer/devcontainer.json` provides an interactive VS Code environment from the same `latest` image.

The Dev Container runs as the non-root `vscode` user. Packages baked into the image live under `/opt/renv/library`; a writable per-user renv library is placed ahead of that canonical library for dependency changes on a branch. Its post-create `renv::restore()` reconciles the checked-out lockfile with the image, installing branch-specific differences into the writable layer without modifying the image library.

The R packages and Quarto are version-locked, but the overall image is not perfectly immutable: other upstream image and system-package inputs may still change over time, and `latest` is intentionally a moving image tag. Use a published `sha-<commit>` image tag when source-to-image traceability matters.

## Running the project

Pipeline and render operations need network access on a clean checkout. In addition to Open-Meteo, the pipeline geocodes Berlin through OpenStreetMap/Nominatim, and rendering may retrieve the Libre Franklin font from Google Fonts.

### VS Code Dev Container

The Dev Container is the easiest way to reproduce the full interactive environment. Open the repository in VS Code with the Dev Containers extension, choose **Reopen in Container**, and then run:

```bash
Rscript -e 'targets::tar_make()'
quarto render index.qmd
```

The first command builds or updates the pipeline; the second renders the dashboard using its stored outputs.

### Docker

Build the canonical image locally and mount the checkout at its configured working directory:

```bash
docker build -t berlin-weather .

docker run --rm -it \
  --mount type=bind,src="$PWD",dst=/project \
  --workdir /project \
  berlin-weather
```

Inside the container, run the same pipeline and render commands shown above. This is a direct way to run the canonical environment, but the image defaults to the root user and may therefore create root-owned files in a Linux host bind mount. For interactive development, the VS Code Dev Container is recommended because it runs as the non-root `vscode` user. The bind mount remains writable because `{targets}` must create or update `_targets/` and Quarto must write rendered output.

### Native R

With R 4.4.x and renv available, restore the package library from the repository root:

```bash
Rscript -e 'renv::restore()'
Rscript -e 'targets::tar_make()'
quarto render index.qmd
```

`renv::restore()` recreates the R dependency environment; it does not install Quarto or the system libraries required by packages with compiled dependencies. Those must be supplied separately, which is why the container is the more complete reproduction path.

## Testing

The `{testthat}` suite covers the external-data contract and important transformation and regression behavior: response shape and types, malformed timestamps, partial missingness, split-date boundaries and recombination, filtering, leap-day handling, incomplete final dates, retrieval logging, and bounded retries.

Retrieval tests inject local test functions into `get_raw_data()`. This exercises success and failure paths deterministically without deliberately failing real network calls, so the unit suite remains offline.

Run the suite in the canonical environment:

```bash
docker build -t berlin-weather-test .

docker run --rm \
  --mount type=bind,src="$PWD",dst=/project,readonly \
  --workdir /project \
  berlin-weather-test \
  Rscript -e 'testthat::test_dir("tests/testthat")'
```

If the locked R environment is already active, the direct equivalent is:

```bash
Rscript -e 'testthat::test_dir("tests/testthat")'
```

## Automation and publication

The workflows under `.github/workflows/` keep distinct responsibilities:

- **Tests:** pull requests and pushes to `main` build the proposed Dockerfile, check documentation paths, and run the offline test suite inside that image.
- **Canonical image:** pushes to `main` that change environment-defining inputs build and publish `latest` and commit-SHA images to GitHub Container Registry. Publication is protected by both the branch trigger and a job-level `github.ref` guard.
- **Dashboard publication:** pushes to `main`, a daily schedule, manual runs, and successful image builds run the pipeline in the published container and publish the Quarto dashboard.
- **Historical-state reuse:** the publication workflow caches selected `{targets}` objects and metadata using the calendar year plus hashes of pipeline, function, and Docker inputs, avoiding unnecessary retrieval and recomputation when that state remains valid.
- **Documentation integrity:** the test workflow runs `scripts/check_doc_paths.py` to catch stale repository-path references in `README.md` and `AGENTS.md`.

## Repository structure

```text
.
├── R/                       # Retrieval, validation, transformation, and analysis
├── tests/                   # Offline unit and regression tests
├── .github/workflows/       # Test, image-build, and publication automation
├── .devcontainer/           # VS Code Dev Container configuration
├── scripts/                 # Repository maintenance checks
├── _targets.R               # Pipeline definition
├── index.qmd                # Quarto dashboard source
├── Dockerfile               # Canonical runtime/build environment
├── DESCRIPTION              # Direct R dependencies
├── renv.lock                # Exact R dependency resolution
└── AGENTS.md                # Repository guidance for coding agents
```

Generated state under `_targets/` is managed by `{targets}` and should not be edited directly.

## Design principles

- **Validate external data at the boundary.** Open-Meteo responses must satisfy a small, explicit internal contract before transformation.
- **Retry retrieval failures, not invalid data.** Network-facing failures receive bounded retries; malformed successful responses fail at validation.
- **Use deterministic production automation.** `{targets}`, Docker, Quarto, and GitHub Actions define the recurring workflow end to end.
- **Keep dependencies and environments explicit.** Direct dependencies, resolved versions, and system requirements are represented by separate, reviewable files.
- **Protect behavior with regression tests.** Tests capture failures and edge cases so later changes can preserve intended behavior.
- **Avoid unnecessary recomputation.** Dependency tracking, persisted target state, and CI caches reuse stable work while allowing current observations to refresh.

## Technology

R · `{targets}` · `{tidyverse}` · Open-Meteo · `{testthat}` · `{renv}` · Quarto · Docker · VS Code Dev Containers · GitHub Actions · GitHub Container Registry
