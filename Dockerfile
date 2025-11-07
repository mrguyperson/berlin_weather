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
# Install R packages using install2.r
# Faster and more stable than pak in Docker
# ------------------------------------------------------------------------------

RUN install2.r --error --skipinstalled \
    languageserver \
    lintr \
    styler \
    here \
    tidyverse \
    igraph \
    targets \
    tarchetypes \
    dplyr \
    lubridate \
    jsonlite \
    httpgd \
    httr \
    readxl \
    openmeteo \
    bigrquery \
    gt \
    leaflet \
    showtext \
    quarto

RUN Rscript -e 'install.packages("vscDebugger", repos = "https://manuelhentschel.r-universe.dev")'

# ------------------------------------------------------------------------------
# Set working directory
# (GitHub Actions mounts your repository here)
# ------------------------------------------------------------------------------
WORKDIR /project

# ------------------------------------------------------------------------------
# Default command for interactive runs (overridden in CI)
# ------------------------------------------------------------------------------
CMD ["bash"]
