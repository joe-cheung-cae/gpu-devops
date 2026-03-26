FROM nvidia/cuda:11.7.1-devel-ubuntu22.04

ARG DEBIAN_FRONTEND=noninteractive
ARG CMAKE_VERSION=3.26.0
ARG OPENMPI_VERSION=4.1.6
ARG EIGEN3_VERSION=3.4.0
ARG CHRONO_GIT_URL=https://github.com/projectchrono/chrono.git
ARG CHRONO_GIT_REF=3eb56218b
ARG CHRONO_BUILD_PARALLEL=6
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
      zlib1g-dev \
      wget && \
    rm -rf /var/lib/apt/lists/*

RUN wget -qO /tmp/cmake.sh "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-x86_64.sh" && \
    sh /tmp/cmake.sh --skip-license --prefix=/usr/local && \
    rm -f /tmp/cmake.sh

COPY docker/cuda-builder/install-openmpi.sh /usr/local/bin/install-openmpi.sh
RUN chmod +x /usr/local/bin/install-openmpi.sh && \
    OPENMPI_VERSION="${OPENMPI_VERSION}" OPENMPI_PREFIX="${OPENMPI_PREFIX}" /usr/local/bin/install-openmpi.sh

COPY docker/cuda-builder/install-eigen3.sh /usr/local/bin/install-eigen3.sh
RUN chmod +x /usr/local/bin/install-eigen3.sh && \
    EIGEN3_VERSION="${EIGEN3_VERSION}" EIGEN3_PREFIX="/usr/local" /usr/local/bin/install-eigen3.sh

COPY docker/cuda-builder/install-chrono.sh /usr/local/bin/install-chrono.sh
RUN chmod +x /usr/local/bin/install-chrono.sh && \
    CHRONO_GIT_URL="${CHRONO_GIT_URL}" \
    CHRONO_GIT_REF="${CHRONO_GIT_REF}" \
    CHRONO_BUILD_PARALLEL="${CHRONO_BUILD_PARALLEL}" \
    /usr/local/bin/install-chrono.sh

COPY docker/cuda-builder/deps/CMake-hdf5-1.14.1-2.tar.gz /tmp/CMake-hdf5-1.14.1-2.tar.gz
COPY docker/cuda-builder/install-hdf5.sh /usr/local/bin/install-hdf5.sh
RUN chmod +x /usr/local/bin/install-hdf5.sh && \
    CHRONO_BUILD_PARALLEL="${CHRONO_BUILD_PARALLEL}" \
    /usr/local/bin/install-hdf5.sh

COPY docker/cuda-builder/deps/h5engine-sph.tar.gz /tmp/h5engine-sph.tar.gz
COPY docker/cuda-builder/deps/h5engine-dem.tar.gz /tmp/h5engine-dem.tar.gz
COPY docker/cuda-builder/install-h5engine.sh /usr/local/bin/install-h5engine.sh
RUN chmod +x /usr/local/bin/install-h5engine.sh && \
    CHRONO_BUILD_PARALLEL="${CHRONO_BUILD_PARALLEL}" \
    /usr/local/bin/install-h5engine.sh

RUN python3 -m pip install --no-cache-dir \
      conan \
      ninja

WORKDIR /workspace

CMD ["/bin/bash"]
