FROM nvidia/cuda:11.7.1-devel-centos7

ARG DEBIAN_FRONTEND=noninteractive
ARG CMAKE_VERSION=3.26.0
ARG http_proxy
ARG https_proxy
ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG no_proxy
ARG NO_PROXY

RUN YUM_PROXY="${http_proxy:-${HTTP_PROXY}}" && \
    if [ -n "${YUM_PROXY}" ]; then echo "proxy=${YUM_PROXY}" >> /etc/yum.conf; fi && \
    sed -i 's|^mirrorlist=|#mirrorlist=|g' /etc/yum.repos.d/CentOS-Base.repo && \
    sed -i 's|^#baseurl=http://mirror.centos.org/centos/\$releasever|baseurl=http://vault.centos.org/7.9.2009|g' /etc/yum.repos.d/CentOS-Base.repo && \
    yum install -y epel-release && \
    yum install -y \
      ca-certificates \
      ccache \
      centos-release-scl \
      curl \
      gcc \
      gcc-c++ \
      gdb \
      git \
      libuuid-devel \
      make \
      perl \
      rsync \
      unzip \
      wget \
      zlib-devel \
      which && \
    yum clean all && \
    rm -rf /var/cache/yum

RUN sed -i 's|^mirrorlist=|#mirrorlist=|g' /etc/yum.repos.d/CentOS-SCLo-*.repo && \
    sed -i 's|^#baseurl=http://mirror.centos.org/centos/7/sclo/\$basearch/rh/|baseurl=http://vault.centos.org/7.9.2009/sclo/\$basearch/rh/|g' /etc/yum.repos.d/CentOS-SCLo-scl-rh.repo && \
    sed -i 's|^# baseurl=http://mirror.centos.org/centos/7/sclo/\$basearch/sclo/|baseurl=http://vault.centos.org/7.9.2009/sclo/\$basearch/sclo/|g' /etc/yum.repos.d/CentOS-SCLo-scl.repo && \
    yum install -y \
      devtoolset-11-binutils \
      devtoolset-11-gcc \
      devtoolset-11-gcc-c++ \
      rh-python38 \
      rh-python38-python-pip && \
    yum clean all && \
    rm -rf /var/cache/yum

ENV PATH="/opt/rh/devtoolset-11/root/usr/bin:${PATH}"
ENV LD_LIBRARY_PATH="/opt/rh/devtoolset-11/root/usr/lib64:${LD_LIBRARY_PATH}"

RUN ln -sf /opt/rh/rh-python38/root/usr/bin/python3 /usr/local/bin/python3 && \
    ln -sf /opt/rh/rh-python38/root/usr/bin/pip3 /usr/local/bin/pip3

RUN wget -qO /tmp/cmake.sh "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-x86_64.sh" && \
    sh /tmp/cmake.sh --skip-license --prefix=/usr/local && \
    rm -f /tmp/cmake.sh

RUN python3 -m pip install --no-cache-dir \
      conan \
      ninja \
      'urllib3<2'

RUN ln -sf /opt/rh/rh-python38/root/usr/local/bin/conan /usr/local/bin/conan && \
    ln -sf /opt/rh/rh-python38/root/usr/local/bin/ninja /usr/local/bin/ninja

WORKDIR /workspace

CMD ["/bin/bash"]
