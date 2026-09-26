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

Before planning or editing any non-trivial task, read `AGENTS.md`, `README.md`,
`ROADMAP.md`, and the issue or task contract. Treat the issue as the detailed
scope and acceptance criteria; the roadmap supplies phase-level direction.

Before declaring the task complete, review all three documents again for
accuracy and roadmap impact. In the final report, state separately for each
document what changed or why no change was needed.

Before making a non-trivial change:

1. Inspect the relevant existing code and configuration.
2. Identify the files that should need modification.
3. Avoid unrelated refactoring or dependency changes.

If solving a problem requires broadening the requested scope, explain why before making additional changes.

Do not change analytical behavior merely to make a test pass.

## Agent-assisted development

GitHub issues and PRs are the durable source of task and review state. Use `.github/ISSUE_TEMPLATE/agent-task.yml` to define desired behavior, acceptance criteria, required validation, and explicit out-of-scope items.

Implement on an isolated branch or worktree, keeping changes within the scoped issue. Use `.github/pull_request_template.md` to link the task and record changes, validation results, documentation review, and remaining limitations. Carry relevant decisions from conversations into the issue or PR so a fresh reviewer can work from the repository, issue, PR diff, tests, and documented instructions alone.

Deterministic tests and checks remain authoritative gates; agent review supplements them. Reviewer findings should identify concrete problems, their impact, and actionable corrections rather than broad stylistic preferences. Humans retain final merge approval unless repository policy explicitly changes.

Give agents only the permissions needed for their task; prefer trusted scripts or actions for privileged GitHub operations over model-generated shell logic. No agent execution or review automation is configured by these templates. If automated review/fix loops are introduced later, bound their iterations and escalate unresolved work to a human.

## External data boundary

Open-Meteo responses are external, untrusted inputs.

`validate_raw_data()` defines the minimum schema expected by the internal pipeline before transformation.

Keep validation of the external API contract separate from downstream transformation logic where practical.

Do not silently substitute, invent, or repair missing weather observations unless the task explicitly requires that behavior.

## R and dependency environment

Do not assume R is installed on the host.

The root `Dockerfile` is the canonical runtime definition for development and CI. R packages and Quarto are pinned for a given source revision, but other inputs and the published `latest` image tag may still change over time.

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

Measure line coverage of reusable R logic with `Rscript scripts/check_coverage.R`
inside the project container. CI requires at least the committed minimum in
that script. The minimum is a ratchet: raise it after sustained test gains; do
not lower it merely to make CI pass. Lowering it requires explicit human-approved
justification. Effectively complete line coverage is a long-term goal, but
coverage does not replace meaningful edge-case, regression, and integration
tests.

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

The image workflow prepares current `main` revisions with commit-specific canonical images and the moving `weather-image:latest` convenience tag. Preserve the `push.branches` filter and the job-level `github.ref` guard so manual dispatch from a non-main ref cannot update canonical images. An in-progress build for a superseded `main` revision may be canceled.

Every production dashboard revision that is published must use the canonical `sha-<commit>` image matching the explicitly checked-out source revision; do not use `weather-image:latest` for publication correctness.

Use minimal GitHub Actions permissions appropriate to the task.

## Documentation maintenance

For every non-trivial task, review `AGENTS.md`, `README.md`, and `ROADMAP.md`
again before completion. Update any document made inaccurate by changed
behavior, architecture, workflow, dependencies, commands, or project direction
in the same change. Routine implementation detail should not churn
`ROADMAP.md`; update it for phase-level direction, architectural intent, major
sequencing, or meaningful milestone status.

Pay particular attention when modifying `Dockerfile`, `DESCRIPTION`, `renv.lock`, `renv/**`, `.devcontainer/**`, `.github/workflows/**`, `_targets.R`, or `R/functions.R`. Deleting or renaming a documented file must update references to it.

For each of the three documents, explicitly report either its update or why
review found no update necessary. Documentation corrections are an exception to otherwise narrow implementation scopes.

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
