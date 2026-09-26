# Berlin Weather roadmap

## Vision and working contract

Berlin Weather should make current conditions intelligible against a long,
carefully validated historical record. The near-term product remains a useful
static Quarto dashboard; richer interaction, additional weather variables, and
more locations should grow from tested data models rather than bypass them.

`main` must remain deployable and visually usable after every merged step.
Replacement architecture should normally be built and validated underneath
existing behavior before the user interface switches to it. New scientific
variables must be ingested, validated, and tested before they appear in the
dashboard. Prefer static, reproducible publication while it can satisfy the
interaction needs; do not assume a server is necessary in advance.

This document records phase-level direction and major sequencing, not a task
ledger. GitHub issues define scoped acceptance criteria; PRs record implementation,
validation, and review state. Phase boundaries may be adjusted as evidence
emerges without turning this file into a per-issue changelog.

## Planned progression

### Foundation and temperature data

1. Establish deterministic line-coverage measurement and a reviewed coverage
   floor, while retaining meaningful behavioral, edge-case, and integration tests.
2. Add a compact deterministic integration fixture that exercises the pipeline
   without live weather or map services.
3. Build an interaction-ready daily temperature data model beneath the current
   plot, preserving its statistical meaning and output while the new path is tested.
4. Derive historical daily-minimum and daily-maximum context for richer hover
   information, clearly separate from the pooled-hourly bands in today's figure.

### Interactive temperature experience

5. Prototype an interactive temperature plot and verify visual and statistical
   parity with the existing presentation before switching the production view.
6. Replace the production temperature plot only when it remains usable in the
   published static dashboard.
7. Add clear hover details for current and historical context without obscuring
   the core comparison.
8. Add zoom and month-level exploration that works on desktop and smaller screens.
9. Allow selection of a comparison year without conflating its daily range with
   the historical pooled-hourly distribution.
10. Publish stable, documented downloadable temperature datasets consistent
    with the displayed analysis.

### Precipitation and dashboard structure

11. Audit precipitation sources, units, completeness, and interpretation before
    deciding what a scientifically defensible comparison can show.
12. Add precipitation retrieval, boundary validation, and tested summaries.
13. Introduce a coherent multi-page Temperature / Precipitation dashboard while
    preserving the existing temperature view.
14. Add interactive precipitation presentation only after its data model and
    static summaries are verified.

### Locations and interface confidence

15. Separate location and timezone assumptions from Berlin-specific analysis.
16. Test date boundaries, completeness, and statistics across multiple timezone
    and daylight-saving regimes.
17. Generate static targets for a finite, curated set of cities.
18. Add a finite client-side city selector over those prebuilt results.
19. Add browser-level tests for the interactive user journeys, alongside the R
    unit and integration suite.
20. Reassess whether curated static cities meet the product need. Only if
    arbitrary user-selected locations are required should a server-backed
    architecture such as Shiny be evaluated against its operational cost.

## Continuous testing workstream

Coverage and test quality advance throughout these phases, not as final cleanup.
Ratchet the committed line-coverage floor upward after sustained gains toward
effectively complete coverage of reusable R application logic. Line coverage
alone cannot establish correctness: keep explicit regression tests for data
contracts, scientific edge cases, and integration behavior, and add browser
tests when the interface becomes interactive.
