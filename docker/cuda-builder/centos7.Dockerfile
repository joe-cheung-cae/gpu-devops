FROM nvidia/cuda:11.7.1-devel-centos7

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

RUN YUM_PROXY="${http_proxy:-${HTTP_PROXY}}" && \
    if [ -n "${YUM_PROXY}" ]; then echo "proxy=${YUM_PROXY}" >> /etc/yum.conf; fi && \
    sed -i 's|^mirrorlist=|#mirrorlist=|g' /etc/yum.repos.d/CentOS-Base.repo && \
    sed -i 's|^#baseurl=http://mirror.centos.org/centos/\$releasever|baseurl=http://vault.centos.org/7.9.2009|g' /etc/yum.repos.d/CentOS-Base.repo && \
    yum install -y \
      ca-certificates \
      centos-release-scl \
      curl \
      gcc \
      gcc-c++ \
      gdb \
      git \
      make \
      perl \
      rsync \
      unzip \
      wget \
      which && \
    yum clean all && \
    rm -rf /var/cache/yum

RUN sed -i 's|^mirrorlist=|#mirrorlist=|g' /etc/yum.repos.d/CentOS-SCLo-*.repo && \
    sed -i 's|^#baseurl=http://mirror.centos.org/centos/7/sclo/\$basearch/rh/|baseurl=http://vault.centos.org/7.9.2009/sclo/\$basearch/rh/|g' /etc/yum.repos.d/CentOS-SCLo-scl-rh.repo && \
    sed -i 's|^# baseurl=http://mirror.centos.org/centos/7/sclo/\$basearch/sclo/|baseurl=http://vault.centos.org/7.9.2009/sclo/\$basearch/sclo/|g' /etc/yum.repos.d/CentOS-SCLo-scl.repo && \
    yum install -y \
      rh-python38 \
      rh-python38-python-pip && \
    yum clean all && \
    rm -rf /var/cache/yum

RUN ln -sf /opt/rh/rh-python38/root/usr/bin/python3 /usr/local/bin/python3 && \
    ln -sf /opt/rh/rh-python38/root/usr/bin/pip3 /usr/local/bin/pip3

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
      ninja \
      'urllib3<2'

RUN ln -sf /opt/rh/rh-python38/root/usr/local/bin/conan /usr/local/bin/conan && \
    ln -sf /opt/rh/rh-python38/root/usr/local/bin/ninja /usr/local/bin/ninja

WORKDIR /workspace

CMD ["/bin/bash"]
