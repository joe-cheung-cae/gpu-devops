# GitLab GPU Shell Runner 教程

本文面向两类人：

- 平台运维：构建 CUDA 镜像、注册 shell runner
- 研发工程师：在 `.gitlab-ci.yml` 中使用共享平台

该仓库面向单台带 NVIDIA GPU 的 Docker 主机。CI job 通过 GitLab 的
shell executor 执行，并在 job 中调用 `compose.sh` 进入 builder 镜像。

## 1. 平台提供的内容

- CUDA builder 镜像族：`cuda11.7-cmake3.26-{centos7|rocky8|ubuntu2204}`
- shell runner 注册流程
- 离线镜像导出/导入与可移植 operator toolkit
- CI 示例与 CUDA/CMake smoke 工程

默认标签策略：

- `gpu`：单卡任务
- `gpu-multi`：多卡任务
- `cuda`：需要 CUDA 工具链的任务
- `cuda-11`：固定到 CUDA 11.7 基线的任务

## 2. 仓库结构

- `docker/cuda-builder/`：标准 CUDA builder 镜像定义
- `runner/`：shell runner 注册脚本
- `scripts/`：镜像构建、Compose 包装器、宿主机校验
- `scripts/export/`、`scripts/import/`、`scripts/common/`：bundle 内部实现
- `examples/`：CUDA/CMake 示例与 CI 示例
- `docs/`：运维与使用文档

## 3. 宿主机前置条件

主机需要提供：

1. Docker Engine
2. Docker Compose 插件或独立 `docker-compose`
3. NVIDIA driver
4. NVIDIA Container Toolkit 并在 Docker 中暴露 `nvidia` runtime
5. 能访问镜像仓库与基础镜像源

先运行校验脚本：

```bash
scripts/verify-host.sh
```

期望结果：

- `docker --version` 可用
- `docker compose version` 或 `docker-compose --version` 可用
- `nvidia-smi` 正常输出
- `docker info` 中可见 `nvidia` runtime

## 4. 支持的 builder 平台

当前支持：

- `centos7` -> `nvidia/cuda:11.7.1-devel-centos7`
- `rocky8` -> `nvidia/cuda:11.7.1-devel-rockylinux8`
- `ubuntu2204` -> `nvidia/cuda:11.7.1-devel-ubuntu22.04`

说明：

- `centos7` 仍保留兼容性，仓库会改写到 `vault.centos.org`
- 所有平台的基础镜像只包含通用 CUDA/C++ 工具链
- 项目依赖会后置到 `${CUDA_CXX_THIRD_PARTY_ROOT}/<platform>`

## 5. 配置 `.env`

创建 `.env`：

```bash
cp .env.example .env
```

需要关注的变量：

- `GITLAB_URL`
- `RUNNER_REGISTRATION_TOKEN`
- `RUNNER_SHELL_USER`
- `RUNNER_TLS_CA_FILE`（GitLab 自签名证书时使用）
- `BUILDER_IMAGE_FAMILY`
- `BUILDER_DEFAULT_PLATFORM`
- `BUILDER_PLATFORMS`
- `BUILDER_IMAGE`
- `IMAGE_ARCHIVE_PATH`
- `RUNNER_GPU_CONCURRENCY` / `RUNNER_MULTI_GPU_CONCURRENCY`

建议：

- 使用内部镜像仓库
- 避免 `latest`，使用固定 tag
- 自签名 HTTPS 时先设置 `RUNNER_TLS_CA_FILE`

## 6. 构建 builder 镜像

```bash
scripts/prepare-third-party-cache.sh
scripts/build-builder-image.sh
scripts/build-builder-image.sh --platform ubuntu2204
scripts/build-builder-image.sh --all-platforms
```

`scripts/prepare-third-party-cache.sh` 会准备 `chrono`、`eigen3`、`openmpi`、
`muparserx` 的本地归档（可选但推荐）。

项目依赖通过以下步骤准备到 `CUDA_CXX_THIRD_PARTY_ROOT/<platform>`：

```bash
scripts/prepare-builder-deps.sh --platform centos7
scripts/install-third-party.sh --host linux --platform centos7
```

## 7. 离线镜像导出与导入

联网环境：

```bash
scripts/export/images.sh
```

离线环境：

```bash
scripts/import/images.sh --input "${IMAGE_ARCHIVE_PATH}"
```

如果离线主机没有仓库 checkout，先导出并解压 operator toolkit：

```bash
scripts/export/project-bundle.sh --mode assets --output artifacts/project-operator-toolkit.tar.gz
```

然后：

```bash
mkdir -p /path/to/project/.gpu-devops
tmpdir="$(mktemp -d)"
tar -xzf artifacts/project-operator-toolkit.tar.gz -C "${tmpdir}"
cp -R "${tmpdir}/assets/." /path/to/project/.gpu-devops/
```

按 [offline-env-configuration.md](offline-env-configuration.md) 补齐 `.gpu-devops/.env`，
之后在 `/path/to/project/.gpu-devops/` 下执行：

```bash
.gpu-devops/scripts/import/images.sh --input /path/to/offline-images.tar.gz
.gpu-devops/scripts/prepare-builder-deps.sh --platform centos7
.gpu-devops/scripts/install-third-party.sh --host linux --platform centos7
.gpu-devops/runner/register-shell-runner.sh gpu
.gpu-devops/scripts/compose.sh run --rm cuda-cxx-centos7
```

如果其他项目也要使用同一套镜像和工具包：

```bash
scripts/export/project-bundle.sh
scripts/import/project-bundle.sh --target-dir /path/to/other/project
```

## 8. 注册 shell runner

注册单卡池：

```bash
runner/register-shell-runner.sh gpu
```

注册多卡池：

```bash
runner/register-shell-runner.sh multi
```

shell runner 以 `gitlab-runner`（或 `RUNNER_SHELL_USER`）身份执行，需要
具备 Docker 与 `docker compose` 权限。

## 9. 本地 Compose 构建

```bash
scripts/prepare-builder-deps.sh --platform centos7
scripts/install-third-party.sh --host linux --platform centos7
scripts/compose.sh run --rm cuda-cxx-centos7
scripts/compose.sh up --abort-on-container-exit cuda-cxx-centos7 cuda-cxx-ubuntu2204
```

`CUDA_CXX_PROJECT_DIR` 选择 `/workspace` 内的源码目录，构建与安装产物
分别写入 `${CUDA_CXX_BUILD_ROOT}` 与 `${CUDA_CXX_INSTALL_ROOT}`。

如需自定义 CMake 或 build 参数，可参考
[cuda-cxx.env.example](../examples/env/cuda-cxx.env.example)。

## 10. CI 示例

请参考：

- [examples/gitlab-ci/shared-gpu-shell-runner.yml](../examples/gitlab-ci/shared-gpu-shell-runner.yml)

示例默认 `BUILD_PLATFORM=centos7`，并在 job 内调用
`.gpu-devops/scripts/compose.sh`。

## 11. 常见问题

### 11.1 CUDA 基础镜像无法拉取

检查：

- Docker registry 配置
- 代理设置
- Docker daemon 是否需要重启

尝试直接拉取：

```bash
docker pull nvidia/cuda:11.7.1-devel-centos7
docker pull nvidia/cuda:11.7.1-devel-rockylinux8
docker pull nvidia/cuda:11.7.1-devel-ubuntu22.04
```
