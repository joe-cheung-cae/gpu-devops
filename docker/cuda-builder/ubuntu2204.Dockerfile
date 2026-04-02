FROM nvidia/cuda:11.7.1-devel-ubuntu22.04

ARG DEBIAN_FRONTEND=noninteractive
ARG CMAKE_VERSION=3.26.0
ARG http_proxy
ARG https_proxy
ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG no_proxy
ARG NO_PROXY

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      ccache \
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
      uuid-dev \
      zlib1g-dev \
      wget && \
    rm -rf /var/lib/apt/lists/*

RUN wget -qO /tmp/cmake.sh "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-x86_64.sh" && \
    sh /tmp/cmake.sh --skip-license --prefix=/usr/local && \
    rm -f /tmp/cmake.sh

RUN python3 -m pip install --no-cache-dir \
      conan \
      ninja

WORKDIR /workspace

CMD ["/bin/bash"]
