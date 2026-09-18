# ------------------------------------------------------------------------------
# Base image: stable R environment
# ------------------------------------------------------------------------------
FROM rocker/r-ver:4.4.3

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

RUN wget -q https://quarto.org/download/latest/quarto-linux-amd64.deb \
    && dpkg -i quarto-linux-amd64.deb \
    && rm quarto-linux-amd64.deb

# ------------------------------------------------------------------------------
# Restore the locked R package environment
# ------------------------------------------------------------------------------

ENV RENV_PATHS_LIBRARY=/opt/renv/library

WORKDIR /project

COPY renv.lock .Rprofile ./
COPY renv/activate.R renv/settings.json renv/

RUN Rscript -e 'renv::restore(prompt = FALSE, repos = c(CRAN = Sys.getenv("CRAN"), vscDebugger = "https://manuelhentschel.r-universe.dev"))'

# ------------------------------------------------------------------------------
# Set working directory
# (GitHub Actions mounts your repository here)
# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
# Default command for interactive runs (overridden in CI)
# ------------------------------------------------------------------------------
CMD ["bash"]
