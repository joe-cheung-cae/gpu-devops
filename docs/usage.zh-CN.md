# 项目使用指南

本文档按使用目的拆分为两条主线，方便快速上手：

- 平台运维人员：负责部署共享 GitLab GPU Runner 并完成注册
- 研发工程师：负责使用标准 builder 镜像或本地 Compose 流程构建 CUDA/CMake 项目

## 1. 平台运维使用流程

### 步骤 1：准备宿主机和配置文件

```bash
cp .env.example .env
scripts/verify-host.sh
```

然后编辑 `.env`，至少确认以下变量：

- `GITLAB_URL`
- `RUNNER_REGISTRATION_TOKEN`
- `BUILDER_IMAGE_FAMILY`
- `BUILDER_IMAGE`
- `RUNNER_DOCKER_IMAGE`
- 如果 GitLab HTTPS 使用自签名证书，还要设置 `RUNNER_TLS_CA_FILE`

### 步骤 2：构建 builder 镜像

构建默认平台镜像：

```bash
scripts/prepare-chrono-source-cache.sh
scripts/build-builder-image.sh
```

构建指定平台镜像：

```bash
scripts/build-builder-image.sh --platform ubuntu2204
```

构建全部支持平台：

```bash
scripts/build-builder-image.sh --all-platforms
```

`scripts/prepare-chrono-source-cache.sh` 是可选步骤。它会在宿主机生成 `docker/cuda-builder/deps/chrono-source.tar.gz`，让 Dockerfile 在构建时优先解压本地 Chrono 源码归档，而不是每次都重新下载。

### 步骤 3：准备 Runner 服务镜像并导出离线包

在联网环境中，先准备 Runner 服务镜像，再导出部署镜像：

```bash
scripts/prepare-runner-service-image.sh
scripts/export-images.sh
```

会生成：

- `artifacts/offline-images.tar.gz`
- `artifacts/offline-images.tar.gz.images.txt`
- `artifacts/offline-images.tar.gz.sha256`

按需导出示例：

```bash
scripts/export-images.sh --only-runner-service --output artifacts/offline-runner-service.tar.gz
scripts/export-images.sh --only-build-images --output artifacts/offline-build-images.tar.gz
scripts/export-images.sh --only-build-images --platform centos7 --output artifacts/offline-build-images-centos7.tar.gz
```

`--only-runner-service` 只导出 `RUNNER_SERVICE_IMAGE`。`--only-build-images` 只导出 builder image 矩阵。如果只想导出单个平台，例如 `centos7`，可以再加 `--platform <name>`。

如果离线机器上不保留完整仓库代码，建议同时导出 operator toolkit：

```bash
scripts/export-project-bundle.sh --mode assets --output artifacts/project-operator-toolkit.tar.gz
```

### 步骤 4：在离线机器导入资产

如果离线机器上仍保留当前仓库代码，可以先导入 operator toolkit：

```bash
scripts/import-project-bundle.sh --mode assets --input artifacts/project-operator-toolkit.tar.gz --target-dir /path/to/project
```

如果离线机器上没有仓库 checkout，则先手工解压 toolkit：

```bash
mkdir -p /path/to/project/.gpu-devops
tmpdir="$(mktemp -d)"
tar -xzf artifacts/project-operator-toolkit.tar.gz -C "${tmpdir}"
cp -R "${tmpdir}/assets/." /path/to/project/.gpu-devops/
```

然后按 [offline-env-configuration.md](/home/joe/repo/gpu-devops/docs/offline-env-configuration.md) 生成 `.gpu-devops/.env`，再导入镜像归档：

```bash
scripts/import-images.sh --input artifacts/offline-images.tar.gz
```

如果你是手工解压 toolkit，则应执行：

```bash
.gpu-devops/scripts/import-images.sh --input /path/to/offline-images.tar.gz
.gpu-devops/scripts/runner-compose.sh up -d
.gpu-devops/runner/register-runner.sh gpu
.gpu-devops/runner/register-shell-runner.sh gpu
```

如果导入或解压了 toolkit，后续命令请在 `/path/to/project/.gpu-devops/` 目录下执行。

### 步骤 5：启动 Runner 服务

```bash
scripts/runner-compose.sh up -d
scripts/runner-compose.sh ps
```

预期结果是 `gitlab-runner` 容器正常启动并保持运行。

### 步骤 6：在 GitLab 中注册 Runner

注册默认单卡 Runner 池：

```bash
runner/register-runner.sh gpu
```

注册多卡 Runner 池：

```bash
runner/register-runner.sh multi
```

默认标签如下：

- 单卡池：`gpu`、`cuda`、`cuda-11`
- 多卡池：`gpu-multi`、`cuda`、`cuda-11`

如果你的环境要求 CI job 作为 Linux 用户 `gitlab-runner` 通过普通 shell executor 运行，则应注册 shell-runner 路径：

```bash
sudo -u gitlab-runner -H runner/register-shell-runner.sh gpu
sudo -u gitlab-runner -H runner/register-shell-runner.sh multi
```

这条路径要求：

- `gitlab-runner` 用户可以执行 Docker 和 `docker compose`
- 目标项目目录对 `gitlab-runner` 可访问
- builder 镜像已经存在于本地 Docker
- 项目 job 通过 `.gpu-devops/scripts/compose.sh run --rm cuda-cxx-centos7` 调用构建

### 步骤 7：验证平台与本地 build 环境可用性

```bash
scripts/compose.sh run --rm cuda-cxx-centos7
```

然后把 [examples/gitlab-ci/shared-gpu-runner.yml](/home/joe/repo/gpu-devops/examples/gitlab-ci/shared-gpu-runner.yml) 放到一个测试项目里，确认 `gpu-smoke`、`cuda-cmake-build` 和 `multi-gpu-smoke` 都能成功执行。

如果使用 shell-runner 路径，则从 [examples/gitlab-ci/shared-gpu-shell-runner.yml](/home/joe/repo/gpu-devops/examples/gitlab-ci/shared-gpu-shell-runner.yml) 开始。它在同一个 pipeline 里同时保留 Linux 和 Windows job，并把 `BUILD_PLATFORM=centos7` 作为默认的 Linux compose 构建平台。这个默认值来自 CI 示例，不来自 `.env`。`rocky8` 和 `ubuntu2204` 仍然是受支持的 Linux 备选值。

## 2. 研发工程师使用流程

### 方式 A：使用 Docker Compose 本地构建项目

先在 `.env` 中把项目路径指向你的代码目录：

- `HOST_PROJECT_DIR=/path/to/your/project`
- `CUDA_CXX_PROJECT_DIR=.`
- `CUDA_CXX_BUILD_ROOT=./artifacts/cuda-cxx-build`
- `CUDA_CXX_INSTALL_ROOT=./artifacts/cuda-cxx-install`

执行单平台构建：

```bash
scripts/compose.sh run --rm cuda-cxx-centos7
```

执行多平台构建：

```bash
scripts/compose.sh up --abort-on-container-exit cuda-cxx-centos7 cuda-cxx-ubuntu2204
```

构建产物会写入 `${CUDA_CXX_BUILD_ROOT}/<platform>`，安装产物会写入 `${CUDA_CXX_INSTALL_ROOT}/<platform>`。

Linux builder image 现在也内置了 `uuid/uuid.h` 对应的开发头文件和 `ccache`。如果你要在自己的 CMake 项目里启用编译缓存，可增加：

- `-DCMAKE_C_COMPILER_LAUNCHER=ccache`
- `-DCMAKE_CXX_COMPILER_LAUNCHER=ccache`

### 方式 B：在 `.gitlab-ci.yml` 中使用共享 Runner

可以直接参考 [examples/gitlab-ci/shared-gpu-runner.yml](/home/joe/repo/gpu-devops/examples/gitlab-ci/shared-gpu-runner.yml)。

如果同一个项目还需要 Linux 物理机编译或 Windows 编译，可以继续参考混合 Runner 组织说明：[gitlab-ci-multi-environment.md](/home/joe/repo/gpu-devops/docs/gitlab-ci-multi-environment.md)。

基础配置示例：

```yaml
default:
  image: tf-particles/devops/cuda-builder:cuda11.7-cmake3.26-centos7
  tags:
    - gpu
    - cuda
    - cuda-11
```

如果项目依赖 `rocky8` 或 `ubuntu2204` 基线，只需要切换镜像 tag 后缀。

### 方式 C：使用 shell runner 并在 job 中调用 `docker compose`

可以直接参考 [examples/gitlab-ci/shared-gpu-shell-runner.yml](/home/joe/repo/gpu-devops/examples/gitlab-ci/shared-gpu-shell-runner.yml)。

这个路径适用于 GitLab job 必须作为 Linux 用户 `gitlab-runner` 通过普通 shell executor 运行的情况。job 本身不再使用 `image:`，而是在脚本里调用：

```yaml
script:
  - .gpu-devops/scripts/compose.sh run --rm "cuda-cxx-${BUILD_PLATFORM}"
```

示例默认的 Linux 变量如下：

- `BUILD_PLATFORM=centos7`

Linux shell-runner 构建支持 `centos7`、`rocky8` 和 `ubuntu2204`。示例中同时包含单独的 Windows 标签 job，因此 Windows 和 Linux job 可以并行执行，而不需要额外的 `BUILD_OS` 开关。

示例还同时提供了 Linux 和 Windows 的 `test`、`deploy` 阶段，便于团队在同一条 shell-runner 流水线中继续扩展测试执行和部署交接逻辑。
在 Linux 的 deploy job 中，会再次根据 `BUILD_PLATFORM` 选择对应的平台部署 shell，例如 `./scripts/deploy-centos7.sh`、`./scripts/deploy-rocky8.sh` 或 `./scripts/deploy-ubuntu2204.sh`。
对于 Linux job，示例会把按平台区分的产物保留在 `${CUDA_CXX_BUILD_ROOT}/${BUILD_PLATFORM}` 和 `${CUDA_CXX_INSTALL_ROOT}/${BUILD_PLATFORM}` 下。build 路径继续沿用 compose 现有约定，额外的 install 路径则显式保留给后续 `test` 和 `deploy` job 复用。
如果你要按变量维度查看离线 `.env` 的推荐配置，包括自动生成值、Docker executor、shell runner 以及自签名 HTTPS GitLab，请继续参考 [offline-env-configuration.md](/home/joe/repo/gpu-devops/docs/offline-env-configuration.md)。

### 方式 D：把集成资产导入到其他项目

在本仓库执行：

```bash
scripts/export-project-bundle.sh
scripts/import-project-bundle.sh --target-dir /path/to/other/project
```

目标项目会收到 `.gpu-devops/` 目录，其中包含 Compose 文件、operator 脚本、runner 资产、Docker 构建资产、文档、示例 CI 配置，以及自动生成的 `.env`。

如果你只想导镜像或只想导文件，可以执行：

```bash
scripts/export-project-bundle.sh --mode images
scripts/import-project-bundle.sh --mode images --input artifacts/project-integration-bundle.tar.gz

scripts/export-project-bundle.sh --mode assets
scripts/import-project-bundle.sh --mode assets --target-dir /path/to/other/project
```

现在无论是镜像归档还是 project bundle，导出时都会生成同名的 `.sha256` 文件。导入脚本默认会先校验这个 hash，再执行导入或解包；只有在你明确要跳过完整性校验时，才应使用 `--skip-hash-check`。
