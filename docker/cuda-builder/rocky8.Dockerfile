FROM nvidia/cuda:11.7.1-devel-rockylinux8

ARG DEBIAN_FRONTEND=noninteractive
ARG CMAKE_VERSION=3.26.0
ARG OPENMPI_VERSION=4.1.6
ARG EIGEN3_VERSION=3.4.0
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

RUN dnf install -y \
      ca-certificates \
      curl \
      gcc \
      gcc-c++ \
      gdb \
      git \
      make \
      perl \
      python3 \
      python3-pip \
      rsync \
      tar \
      unzip \
      wget \
      which && \
    dnf clean all && \
    rm -rf /var/cache/dnf

RUN wget -qO /tmp/cmake.sh "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-x86_64.sh" && \
    sh /tmp/cmake.sh --skip-license --prefix=/usr/local && \
    rm -f /tmp/cmake.sh

COPY docker/cuda-builder/install-openmpi.sh /usr/local/bin/install-openmpi.sh
RUN chmod +x /usr/local/bin/install-openmpi.sh && \
    OPENMPI_VERSION="${OPENMPI_VERSION}" OPENMPI_PREFIX="${OPENMPI_PREFIX}" /usr/local/bin/install-openmpi.sh

COPY docker/cuda-builder/install-eigen3.sh /usr/local/bin/install-eigen3.sh
RUN chmod +x /usr/local/bin/install-eigen3.sh && \
    EIGEN3_VERSION="${EIGEN3_VERSION}" EIGEN3_PREFIX="/usr/local" /usr/local/bin/install-eigen3.sh

RUN python3 -m pip install --no-cache-dir \
      conan \
      ninja

WORKDIR /workspace

CMD ["/bin/bash"]
