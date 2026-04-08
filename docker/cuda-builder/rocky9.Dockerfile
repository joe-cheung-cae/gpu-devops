ARG CUDA_VERSION=11.7.1
FROM nvidia/cuda:${CUDA_VERSION}-devel-rockylinux9

ARG DEBIAN_FRONTEND=noninteractive
ARG http_proxy
ARG https_proxy
ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG no_proxy
ARG NO_PROXY
ARG PIP_DEFAULT_TIMEOUT=120

RUN dnf install -y epel-release && \
    dnf install -y \
      autoconf \
      automake \
      bison \
      bzip2 \
      ca-certificates \
      ccache \
      curl \
      file \
      flex \
      gcc-toolset-11-binutils \
      gcc-toolset-11-gcc \
      gcc-toolset-11-gcc-c++ \
      gcc \
      gcc-c++ \
      gcc-gfortran \
      gdb \
      git \
      gzip \
      libtool \
      libuuid-devel \
      make \
      m4 \
      patch \
      perl \
      pkgconf-pkg-config \
      python3 \
      python3-pip \
      rsync \
      tar \
      unzip \
      xz \
      zlib-devel \
      which && \
    dnf clean all && \
    rm -rf /var/cache/dnf

ENV PATH="/opt/rh/gcc-toolset-11/root/usr/bin:${PATH}"
ENV LD_LIBRARY_PATH="/opt/rh/gcc-toolset-11/root/usr/lib64:${LD_LIBRARY_PATH}"

COPY third_party/cache/cmake-3.26.0-linux-x86_64.tar.gz /tmp/deps/
RUN tar -xzf /tmp/deps/cmake-3.26.0-linux-x86_64.tar.gz -C /usr/local --strip-components=1 && \
    rm -f /tmp/deps/cmake-3.26.0-linux-x86_64.tar.gz

ENV PATH="/usr/local/bin:${PATH}"

RUN PIP_DEFAULT_TIMEOUT="${PIP_DEFAULT_TIMEOUT}" python3 -m pip install --no-cache-dir \
      conan \
      ninja

WORKDIR /workspace

CMD ["/bin/bash"]
