# Berlin Weather — Agent Instructions

## Project overview

This repository builds and publishes a Quarto dashboard comparing recent Berlin weather with historical weather observations.

The project is primarily written in R and uses:

* Open-Meteo as the external weather-data source
* `{targets}` for the analysis pipeline
* Quarto for the dashboard
* Docker for the canonical containerized runtime
* `testthat` for automated tests
* GitHub Actions for testing, image building, and publishing

## Repository structure

* `R/functions.R` contains the main R functions.
* `_targets.R` defines the analysis pipeline.
* `index.qmd` contains the main Quarto dashboard.
* `Dockerfile` defines the canonical project runtime environment.
* `.devcontainer/devcontainer.json` uses the image built from the root `Dockerfile`.
* `tests/testthat/` contains automated tests.
* `.github/workflows/` contains CI/CD workflows.
* `_targets/` contains generated `{targets}` state and should not be edited directly.

## Working principles

Keep changes narrowly scoped to the requested task.

Before making a non-trivial change:

1. Inspect the relevant existing code and configuration.
2. Identify the files that should need modification.
3. Avoid unrelated refactoring or dependency changes.

If solving a problem requires broadening the requested scope, explain why before making additional changes.

Do not change analytical behavior merely to make a test pass.

## External data boundary

Open-Meteo responses are external, untrusted inputs.

`validate_raw_data()` defines the minimum schema expected by the internal pipeline before transformation.

Keep validation of the external API contract separate from downstream transformation logic where practical.

Do not silently substitute, invent, or repair missing weather observations unless the task explicitly requires that behavior.

## R and dependency environment

Do not assume R is installed on the host.

The root `Dockerfile` is the canonical runtime definition for development and CI, but it is not fully version-locked: R packages, Quarto, and the published image tag may change over time.

Do not install host-level packages or introduce new project dependencies unless required by the task. Ask before downloading, installing, or substantially changing dependencies when approval is required.

Prefer the project's existing R tools and conventions rather than introducing another language or framework for work that naturally belongs in R.

## Tests

Run the automated tests after changes that could affect R behavior.

Keep unit tests offline and deterministic.

The test suite can be run in the project container with:

```bash
docker build -t berlin-weather-test .

docker run --rm \
  --mount type=bind,src="$PWD",dst=/project,readonly \
  --workdir /project \
  berlin-weather-test \
  Rscript -e 'testthat::test_dir("tests/testthat")'
```

Use targeted tests while developing when appropriate, but run the complete suite before considering a relevant change complete.

Never report that tests pass unless they were actually executed successfully. If tests cannot run, state the reason.

## Targets and Quarto

When modifying `_targets.R` or pipeline functions:

* preserve clear separation between data retrieval, validation, transformation, analysis, and presentation;
* consider how the change affects downstream targets;
* do not edit generated files under `_targets/` directly.

Treat full `{targets}` and Quarto validation as network-dependent integration operations: they may contact Open-Meteo, OpenStreetMap/Nominatim, and Google Fonts, and a clean checkout must rebuild ignored target objects. Run them when warranted and external access is available, and report any validation that could not be performed.

## GitHub Actions

Keep CI and production publishing concerns separate.

The automated test workflow should test pull requests and `main`.

The production `weather-image:latest` image must only be published from `main`. Preserve both the `push.branches` filter and the job-level `github.ref` guard in the image-build workflow unless explicitly requested otherwise.

Use minimal GitHub Actions permissions appropriate to the task.

## Documentation maintenance

When changing architecture, workflows, dependency management, Dev Container behavior, pipeline structure, or user-facing commands, review both `README.md` and `AGENTS.md`. Update documentation in the same change whenever its description becomes inaccurate.

Pay particular attention when modifying `Dockerfile`, `DESCRIPTION`, `renv.lock`, `renv/**`, `.devcontainer/**`, `.github/workflows/**`, `_targets.R`, or `R/functions.R`. Deleting or renaming a documented file must update references to it.

If these files change but the documentation remains accurate, explicitly report that both documents were reviewed and no update was necessary. Documentation updates needed to prevent false guidance are an exception to otherwise narrow implementation scopes.

## Verification before completion

For code or configuration changes:

1. Review the final diff for unrelated changes.
2. Run `git diff --check`.
3. Run relevant automated tests.
4. Run additional pipeline/render validation when warranted.
5. Report:

   * files changed;
   * behavior changed;
   * commands actually run;
   * test/build results;
   * anything that could not be verified.

Do not commit, push, merge, publish, or modify production data unless explicitly requested.
