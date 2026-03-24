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

### 步骤 2：构建 builder 镜像

构建默认平台镜像：

```bash
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

### 步骤 3：启动 Runner 服务

```bash
scripts/runner-compose.sh up -d
scripts/runner-compose.sh ps
```

预期结果是 `gitlab-runner` 容器正常启动并保持运行。

### 步骤 4：在 GitLab 中注册 Runner

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

### 步骤 5：验证平台可用性

```bash
scripts/compose.sh run --rm cuda-cxx-centos7
```

然后把 [examples/gitlab-ci/shared-gpu-runner.yml](/home/joe/repo/gpu-devops/examples/gitlab-ci/shared-gpu-runner.yml) 放到一个测试项目里，确认 `gpu-smoke`、`cuda-cmake-build` 和 `multi-gpu-smoke` 都能成功执行。

## 2. 研发工程师使用流程

### 方式 A：使用 Docker Compose 本地构建项目

先在 `.env` 中把项目路径指向你的代码目录：

- `HOST_PROJECT_DIR=/path/to/your/project`
- `CUDA_CXX_PROJECT_DIR=.`
- `CUDA_CXX_BUILD_ROOT=./artifacts/cuda-cxx-build`

执行单平台构建：

```bash
scripts/compose.sh run --rm cuda-cxx-centos7
```

执行多平台构建：

```bash
scripts/compose.sh up --abort-on-container-exit cuda-cxx-centos7 cuda-cxx-ubuntu2204
```

构建产物会写入 `${CUDA_CXX_BUILD_ROOT}/<platform>`。

### 方式 B：在 `.gitlab-ci.yml` 中使用共享 Runner

可以直接参考 [examples/gitlab-ci/shared-gpu-runner.yml](/home/joe/repo/gpu-devops/examples/gitlab-ci/shared-gpu-runner.yml)。

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

### 方式 C：把集成资产导入到其他项目

在本仓库执行：

```bash
scripts/export-project-bundle.sh
scripts/import-project-bundle.sh --target-dir /path/to/other/project
```

目标项目会收到 `.gpu-devops/` 目录，其中包含 Compose 文件、包装脚本、文档、示例 CI 配置，以及自动生成的 `.env`。
