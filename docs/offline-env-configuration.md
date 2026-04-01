# 离线环境 `.env` 配置指南

本指南专门说明：当目标机器没有当前仓库 checkout，只拿到 `offline-images.tar.gz` 和 `project-operator-toolkit.tar.gz` 时，`.gpu-devops/.env` 应该如何配置。

## 1. 哪些变量会自动生成

执行：

```bash
scripts/import-project-bundle.sh --mode assets --input artifacts/project-operator-toolkit.tar.gz --target-dir /path/to/project
```

或手工解压 operator toolkit 之后，`.gpu-devops/.env` 至少应包含这些默认值：

```env
HOST_PROJECT_DIR=/path/to/project
CUDA_CXX_PROJECT_DIR=.
CUDA_CXX_BUILD_ROOT=.gpu-devops/artifacts/cuda-cxx-build
CUDA_CXX_INSTALL_ROOT=.gpu-devops/artifacts/cuda-cxx-install
CUDA_CXX_DEPS_ROOT=.gpu-devops/artifacts/deps
CUDA_CXX_CMAKE_GENERATOR=Ninja
CUDA_CXX_CMAKE_ARGS=
CUDA_CXX_BUILD_ARGS=
```

这些值的含义是：

- `HOST_PROJECT_DIR`：宿主机项目根目录，最终会挂载到容器内 `/workspace`
- `CUDA_CXX_PROJECT_DIR=.`：源码根默认就是项目根目录
- `CUDA_CXX_BUILD_ROOT`：按 `BUILD_PLATFORM` 划分的构建产物根目录
- `CUDA_CXX_INSTALL_ROOT`：按 `BUILD_PLATFORM` 划分的安装产物根目录
- `CUDA_CXX_DEPS_ROOT`：按 `BUILD_PLATFORM` 划分的项目本地依赖缓存根目录

## 2. 哪些变量必须手工补齐

导入脚本不会替你写入 GitLab 相关敏感配置。这些值必须由操作者补齐：

```env
GITLAB_URL=https://gitlab.example.internal
RUNNER_REGISTRATION_TOKEN=replace-me
RUNNER_DOCKER_IMAGE=tf-particles/devops/cuda-builder:cuda11.7-cmake3.26-centos7
RUNNER_SERVICE_IMAGE=tf-particles/devops/gitlab-runner:alpine-v16.10.1
```

如需自签名 HTTPS GitLab，还要补：

```env
RUNNER_TLS_CA_FILE=certs/gitlab-ca.crt
```

要求：

- `RUNNER_SERVICE_IMAGE` 必须和离线导入到本地 Docker 的 tag 完全一致
- `RUNNER_DOCKER_IMAGE` 必须指向已经导入的 builder image，默认推荐 `centos7`
- `RUNNER_TLS_CA_FILE` 指向 PEM 编码 CA 文件，源文件扩展名可以是 `.pem` 或 `.crt`

## 3. Docker executor 离线部署

推荐 `.env` 额外保留：

```env
BUILDER_IMAGE_FAMILY=tf-particles/devops/cuda-builder:cuda11.7-cmake3.26
BUILDER_DEFAULT_PLATFORM=centos7
BUILDER_PLATFORMS=centos7,rocky8,ubuntu2204
RUNNER_CONTAINER_NAME=gitlab-runner-devops-docker
RUNNER_REGISTRATION_CONTAINER_NAME=gitlab-runner-devops-register
RUNNER_TAG_LIST=gpu,cuda,cuda-11
RUNNER_MULTI_TAG_LIST=gpu-multi,cuda,cuda-11
```

离线部署顺序：

```bash
.gpu-devops/scripts/import-images.sh --input /path/to/offline-images.tar.gz
.gpu-devops/scripts/prepare-builder-deps.sh --platform centos7
.gpu-devops/scripts/runner-compose.sh up -d
.gpu-devops/runner/register-runner.sh gpu
```

如果要多卡池：

```bash
.gpu-devops/runner/register-runner.sh multi
```

## 4. shell runner 离线部署

shell runner 路径适用于：GitLab job 作为 Linux 用户 `gitlab-runner` 通过普通 shell executor 运行，但 build/test/deploy 仍通过 `.gpu-devops/scripts/compose.sh` 在 builder image 中完成。

推荐在 `.env` 中增加：

```env
RUNNER_SHELL_USER=gitlab-runner
```

前置条件：

- `gitlab-runner` 用户可以执行 Docker 和 `docker compose`
- `HOST_PROJECT_DIR` 指向的项目目录对 `gitlab-runner` 可访问
- 本地 Docker 已导入 builder images

注册方式：

```bash
sudo -u gitlab-runner -H .gpu-devops/runner/register-shell-runner.sh gpu
sudo -u gitlab-runner -H .gpu-devops/runner/register-shell-runner.sh multi
```

shell-runner 示例中：

- `BUILD_PLATFORM` 只控制 Linux 平台
- 默认 Linux 平台是 `centos7`，这个默认值来自 `shared-gpu-shell-runner.yml`，不是 `.env` 配置
- Linux build/test/deploy 会复用：
  - `${CUDA_CXX_DEPS_ROOT}/${BUILD_PLATFORM}`
  - `${CUDA_CXX_BUILD_ROOT}/${BUILD_PLATFORM}`
  - `${CUDA_CXX_INSTALL_ROOT}/${BUILD_PLATFORM}`
- Windows job 与 Linux job 并行存在，但不依赖 `BUILD_PLATFORM`

## 5. 离线 rootless Docker 准备

从当前版本开始，Linux 上的项目侧入口 `scripts/compose.sh` 和 `scripts/prepare-builder-deps.sh` 默认要求 rootless Docker。离线主机如果还没有完成 rootless Docker 准备，这两个入口会直接失败；只有在迁移旧环境时才建议临时设置 `CUDA_CXX_ALLOW_ROOTFUL_DOCKER=1` 继续运行。

离线主机至少要提前准备这些前置条件：

- `uidmap` 相关工具可用，也就是 `newuidmap` 和 `newgidmap`
- `/etc/subuid` 和 `/etc/subgid` 已为目标 Linux 用户分配 subordinate UID/GID 范围
- 目标 Linux 用户可以启动自己的 user-level systemd 服务

建议在联网环境提前准备好 rootless Docker 所需的软件包或企业内部镜像源，再把它们带到离线主机。完成软件安装后，在离线主机上以目标 Linux 用户执行官方初始化命令：

```bash
dockerd-rootless-setuptool.sh install
systemctl --user enable docker
systemctl --user start docker
sudo loginctl enable-linger "$USER"
export DOCKER_HOST=unix:///run/user/$(id -u)/docker.sock
docker info | grep -i rootless
```

说明：

- `dockerd-rootless-setuptool.sh install` 会初始化用户态 Docker daemon
- `/run/user/<uid>/docker.sock` 是 rootless Docker 常见的本地 socket 路径
- `loginctl enable-linger` 可以让用户退出登录后 user-level daemon 继续保留
- `docker info` 中应能看到 `rootless`，否则项目侧脚本仍会拒绝执行

如果你是通过 shell runner 离线部署，则 rootless Docker 应该为实际执行 job 的 Linux 用户准备，通常就是 `gitlab-runner`。如果你短期内还不能完成迁移，可以在过渡期显式导出：

```bash
export CUDA_CXX_ALLOW_ROOTFUL_DOCKER=1
```

这个变量只建议用于兼容旧环境，不应作为长期默认配置。

## 6. 推荐的离线 `.env` 最小示例

下面这份 `.gpu-devops/.env` 可以作为离线外部项目的推荐起点：

```env
GITLAB_URL=https://gitlab.example.internal
RUNNER_REGISTRATION_TOKEN=replace-me
RUNNER_TLS_CA_FILE=certs/gitlab-ca.crt

BUILDER_IMAGE_FAMILY=tf-particles/devops/cuda-builder:cuda11.7-cmake3.26
BUILDER_DEFAULT_PLATFORM=centos7
BUILDER_PLATFORMS=centos7,rocky8,ubuntu2204

RUNNER_DOCKER_IMAGE=tf-particles/devops/cuda-builder:cuda11.7-cmake3.26-centos7
RUNNER_SERVICE_IMAGE=tf-particles/devops/gitlab-runner:alpine-v16.10.1

HOST_PROJECT_DIR=/path/to/project
CUDA_CXX_PROJECT_DIR=.
CUDA_CXX_BUILD_ROOT=.gpu-devops/artifacts/cuda-cxx-build
CUDA_CXX_INSTALL_ROOT=.gpu-devops/artifacts/cuda-cxx-install
CUDA_CXX_DEPS_ROOT=.gpu-devops/artifacts/deps
CUDA_CXX_CMAKE_GENERATOR=Ninja
CUDA_CXX_CMAKE_ARGS=
CUDA_CXX_BUILD_ARGS=
```

如果导入脚本已经生成了 `.gpu-devops/.env`，通常只需要在此基础上补齐 GitLab 和 Runner 相关变量即可。
