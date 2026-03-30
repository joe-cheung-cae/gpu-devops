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
```

`--only-runner-service` 只导出 `RUNNER_SERVICE_IMAGE`。`--only-build-images` 只导出 builder image 矩阵。

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
cat > /path/to/project/.gpu-devops/.env <<'EOF'
HOST_PROJECT_DIR=/path/to/project
CUDA_CXX_PROJECT_DIR=.
CUDA_CXX_BUILD_ROOT=.gpu-devops/artifacts/cuda-cxx-build
CUDA_CXX_CMAKE_GENERATOR=Ninja
CUDA_CXX_CMAKE_ARGS=
CUDA_CXX_BUILD_ARGS=
EOF
```

然后导入镜像归档：

```bash
scripts/import-images.sh --input artifacts/offline-images.tar.gz
```

如果你是手工解压 toolkit，则应执行：

```bash
.gpu-devops/scripts/import-images.sh --input /path/to/offline-images.tar.gz
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

### 步骤 7：验证平台与本地 build 环境可用性

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

### 方式 C：把集成资产导入到其他项目

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
