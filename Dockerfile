# ------------------------------------------------------------------------------
# Base image: stable R environment
# ------------------------------------------------------------------------------
FROM rocker/r-ver:4.4.2

# ------------------------------------------------------------------------------
# System libraries needed for your workflows
# ------------------------------------------------------------------------------

RUN apt-get update && apt-get install -y \
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
# Install Quarto
# ------------------------------------------------------------------------------

RUN wget -q https://quarto.org/download/latest/quarto-linux-amd64.deb \
    && dpkg -i quarto-linux-amd64.deb \
    && rm quarto-linux-amd64.deb

# ------------------------------------------------------------------------------
# Pin CRAN to a reproducible snapshot
# ------------------------------------------------------------------------------
ENV CRAN=https://packagemanager.posit.co/cran/2025-02-28

RUN echo "options(repos = c(CRAN='${CRAN}'))" >> /usr/local/lib/R/etc/Rprofile.site

# ------------------------------------------------------------------------------
# Install R packages using install2.r
# Faster and more stable than pak in Docker
# ------------------------------------------------------------------------------

RUN install2.r --error --skipinstalled \
    here \
    tidyverse \
    igraph \
    targets \
    tarchetypes \
    dplyr \
    lubridate \
    jsonlite \
    httr \
    readxl \
    openmeteo \
    bigrquery \
    gt \
    leaflet \
    quarto

# ------------------------------------------------------------------------------
# Set working directory
# (GitHub Actions mounts your repository here)
# ------------------------------------------------------------------------------
WORKDIR /project

# ------------------------------------------------------------------------------
# Default command for interactive runs (overridden in CI)
# ------------------------------------------------------------------------------
CMD ["bash"]
