FROM docker.io/rocker/geospatial:latest

RUN apt update && apt install -y --no-install-recommends python3-pip libglpk-dev

RUN pip3 install radian

RUN install2.r languageserver \
    httpgd \
    jsonlite \
    here \
    microbenchmark \
    readxl