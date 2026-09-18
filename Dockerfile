# ------------------------------------------------------------------------------
# Base image: stable R environment
# ------------------------------------------------------------------------------
FROM rocker/r-ver:4.4.3

ARG QUARTO_VERSION=1.10.18
ARG QUARTO_SHA256=4bdf5a17df300003beb2f8f0e4dfe568e2ca0ff91318220c8537d2655015c430

# ------------------------------------------------------------------------------
# System libraries needed for your workflows
# ------------------------------------------------------------------------------

RUN apt-get update && apt-get install -y -y --no-install-recommends \
    gdal-bin \
    libgdal-dev \
    libgeos-dev \
    libglpk-dev \
    libproj-dev \
    libsqlite3-dev \
    libudunits2-dev \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libfontconfig1-dev \
    libfreetype6-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    wget \
    ca-certificates \
    git \
    && rm -rf /var/lib/apt/lists/*


# ------------------------------------------------------------------------------
# Install python, pip, and radian
# ------------------------------------------------------------------------------
RUN apt-get update && apt-get install -y python3-pip python3-venv && \
    pip install --break-system-packages radian


# ------------------------------------------------------------------------------
# Install Quarto
# ------------------------------------------------------------------------------

RUN wget -q \
        "https://github.com/quarto-dev/quarto-cli/releases/download/v${QUARTO_VERSION}/quarto-${QUARTO_VERSION}-linux-amd64.deb" \
        -O /tmp/quarto.deb \
    && echo "${QUARTO_SHA256}  /tmp/quarto.deb" | sha256sum --check --strict \
    && dpkg -i /tmp/quarto.deb \
    && rm /tmp/quarto.deb

# ------------------------------------------------------------------------------
# Restore the locked R package environment
# ------------------------------------------------------------------------------

ENV RENV_PATHS_LIBRARY=/opt/renv/library
ENV RENV_CONFIG_CACHE_SYMLINKS=FALSE

WORKDIR /project

COPY renv.lock .Rprofile ./
COPY renv/activate.R renv/settings.json renv/

RUN Rscript -e 'renv::restore(prompt = FALSE, repos = c(CRAN = Sys.getenv("CRAN"), vscDebugger = "https://manuelhentschel.r-universe.dev"))'
RUN Rscript -e 'stopifnot(file.symlink(renv::paths$library(), "/opt/renv/library-current"))'

# ------------------------------------------------------------------------------
# Non-root user for VS Code Dev Containers
# ------------------------------------------------------------------------------

RUN useradd --create-home --shell /bin/bash vscode

# ------------------------------------------------------------------------------
# Set working directory
# (GitHub Actions mounts your repository here)
# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
# Default command for interactive runs (overridden in CI)
# ------------------------------------------------------------------------------
CMD ["bash"]
