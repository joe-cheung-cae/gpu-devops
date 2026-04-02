FROM nvidia/cuda:11.7.1-devel-ubuntu22.04

ARG DEBIAN_FRONTEND=noninteractive
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
      tar \
      unzip \
      uuid-dev \
      zlib1g-dev && \
    rm -rf /var/lib/apt/lists/*

COPY third_party/cache/cmake-3.26.0-linux-x86_64.tar.gz /tmp/deps/
RUN tar -xzf /tmp/deps/cmake-3.26.0-linux-x86_64.tar.gz -C /usr/local --strip-components=1 && \
    rm -f /tmp/deps/cmake-3.26.0-linux-x86_64.tar.gz

RUN python3 -m pip install --no-cache-dir \
      conan \
      ninja

WORKDIR /workspace

CMD ["/bin/bash"]
