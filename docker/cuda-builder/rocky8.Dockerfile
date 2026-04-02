FROM nvidia/cuda:11.7.1-devel-rockylinux8

ARG DEBIAN_FRONTEND=noninteractive
ARG CMAKE_VERSION=3.26.0
ARG http_proxy
ARG https_proxy
ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG no_proxy
ARG NO_PROXY

RUN dnf install -y epel-release && \
    dnf install -y \
      ca-certificates \
      ccache \
      curl \
      gcc-toolset-11-binutils \
      gcc-toolset-11-gcc \
      gcc-toolset-11-gcc-c++ \
      gcc \
      gcc-c++ \
      gdb \
      git \
      libuuid-devel \
      make \
      perl \
      python3 \
      python3-pip \
      rsync \
      tar \
      unzip \
      wget \
      zlib-devel \
      which && \
    dnf clean all && \
    rm -rf /var/cache/dnf

ENV PATH="/opt/rh/gcc-toolset-11/root/usr/bin:${PATH}"
ENV LD_LIBRARY_PATH="/opt/rh/gcc-toolset-11/root/usr/lib64:${LD_LIBRARY_PATH}"

RUN wget -qO /tmp/cmake.sh "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-x86_64.sh" && \
    sh /tmp/cmake.sh --skip-license --prefix=/usr/local && \
    rm -f /tmp/cmake.sh

RUN python3 -m pip install --no-cache-dir \
      conan \
      ninja

WORKDIR /workspace

CMD ["/bin/bash"]
