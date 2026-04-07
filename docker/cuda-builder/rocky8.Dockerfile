ARG CUDA_VERSION=11.7.1
FROM nvidia/cuda:${CUDA_VERSION}-devel-rockylinux8

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
