FROM nvidia/cuda:11.7.1-devel-ubuntu22.04

ARG DEBIAN_FRONTEND=noninteractive
ARG CMAKE_VERSION=3.26.0
ARG OPENMPI_VERSION=4.1.6
ARG http_proxy
ARG https_proxy
ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG no_proxy
ARG NO_PROXY

ENV OPENMPI_PREFIX=/opt/openmpi
ENV PATH="${OPENMPI_PREFIX}/bin:${PATH}"
ENV LD_LIBRARY_PATH="${OPENMPI_PREFIX}/lib:${LD_LIBRARY_PATH}"
ENV PKG_CONFIG_PATH="${OPENMPI_PREFIX}/lib/pkgconfig:${PKG_CONFIG_PATH}"

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      g++ \
      gcc \
      gdb \
      git \
      make \
      perl \
      python3 \
      python3-pip \
      rsync \
      unzip \
      wget && \
    rm -rf /var/lib/apt/lists/*

RUN wget -qO /tmp/cmake.sh "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-x86_64.sh" && \
    sh /tmp/cmake.sh --skip-license --prefix=/usr/local && \
    rm -f /tmp/cmake.sh

COPY docker/cuda-builder/install-openmpi.sh /usr/local/bin/install-openmpi.sh
RUN chmod +x /usr/local/bin/install-openmpi.sh && \
    OPENMPI_VERSION="${OPENMPI_VERSION}" OPENMPI_PREFIX="${OPENMPI_PREFIX}" /usr/local/bin/install-openmpi.sh

RUN python3 -m pip install --no-cache-dir \
      conan \
      ninja

WORKDIR /workspace

CMD ["/bin/bash"]
