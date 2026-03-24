# GitLab GPU Runner 使用教程

本文档面向两类角色：

- 平台运维人员：负责构建 CUDA 镜像、部署 GitLab Runner、注册共享 Runner
- 项目开发人员：负责在项目 `.gitlab-ci.yml` 中接入共享 Runner 和标准构建镜像

本仓库当前采用单机 Docker 部署，适用于多个 CUDA/CMake 项目共享同一套 GitLab Runner 平台。

## 1. 平台能力概览

平台提供以下能力：

- 标准 CUDA 构建镜像：`cuda11.7-cmake3.26-centos7`
- GitLab Docker Runner 部署脚本
- 默认 GPU Runner 池和多卡 GPU Runner 池
- 宿主机校验、自检文档、最小示例流水线

默认标签约定：

- `gpu`：单卡 GPU 任务
- `gpu-multi`：多卡 GPU 任务
- `cuda`：需要 CUDA 工具链
- `cuda-11`：固定到 CUDA 11.7 平台基线

## 2. 目录说明

- `docker/cuda-builder/`：标准 CUDA builder 镜像定义
- `runner/`：Runner 配置模板和注册脚本
- `scripts/`：镜像构建、Compose 启动、宿主机校验脚本
- `examples/`：最小 CUDA/CMake 示例和 GitLab CI 示例
- `docs/`：操作文档、平台契约、自检文档

## 3. 宿主机准备

部署前，宿主机至少需要满足以下条件：

1. 已安装 Docker Engine
2. 已安装 Docker Compose 插件，或者独立的 `docker-compose`
3. 已安装 NVIDIA 驱动
4. 已安装 NVIDIA Container Toolkit，并且 Docker 能识别 `nvidia` runtime
5. 宿主机可以访问：
   - Docker 镜像仓库
   - CentOS Vault 或企业内部 YUM 镜像
   - GitHub Release

先执行宿主机自检：

```bash
scripts/verify-host.sh
```

期望结果：

- `docker --version` 正常输出
- `docker compose version` 或 `docker-compose --version` 正常输出
- `nvidia-smi` 正常输出 GPU 信息
- `docker info` 中能看到 `nvidia` runtime

## 3.1 CentOS 7 基线注意事项

当前 builder 镜像基于 `nvidia/cuda:11.7.1-devel-centos7`，因此有几个必须知道的现实约束：

- CentOS 7 已经 EOL，默认公共 mirror 不可靠
- Dockerfile 会自动把基础 YUM 源和 SCLo 源切到 `vault.centos.org`
- Python 3 不是来自系统默认仓库，而是来自 `rh-python38`
- `conan` 在 CentOS 7 上需要兼容旧 OpenSSL，因此镜像里显式限制了 `urllib3<2`

如果你的公司有内部 RPM/YUM 镜像，建议后续把 Dockerfile 中的 public vault 地址切换到内部源。

## 4. 环境变量配置

先复制一份环境变量模板：

```bash
cp .env.example .env
```

然后按你的 GitLab 环境修改 `.env` 中的关键字段：

- `GITLAB_URL`：GitLab 地址
- `RUNNER_REGISTRATION_TOKEN`：Runner 注册令牌
- `RUNNER_DOCKER_IMAGE`：Runner 默认 job image
- `RUNNER_SERVICE_IMAGE`：Runner 服务容器镜像
- `BUILDER_IMAGE`：标准 builder 镜像 tag
- `IMAGE_ARCHIVE_PATH`：离线镜像归档路径
- `RUNNER_GPU_CONCURRENCY`：单卡 Runner 池并发
- `RUNNER_MULTI_GPU_CONCURRENCY`：多卡 Runner 池并发

推荐做法：

- `RUNNER_DOCKER_IMAGE` 与 `BUILDER_IMAGE` 保持一致
- 使用内部镜像仓库地址，而不是长期依赖示例域名
- 发布时使用明确 tag，不要依赖 `latest`

## 5. 构建标准 CUDA Builder 镜像

执行：

```bash
scripts/build-builder-image.sh
```

该脚本会：

- 读取 `.env` 中的 `BUILDER_IMAGE`
- 构建 `docker/cuda-builder/Dockerfile`
- 在你的环境中自动尝试复用 Docker daemon 代理配置
- 当代理指向 `127.0.0.1` / `localhost` 时，自动用 `--network host` 兼容本机代理

如果目标环境无法访问外网，可以在联网环境额外执行：

```bash
scripts/export-images.sh
```

该脚本会把 `BUILDER_IMAGE`、`RUNNER_DOCKER_IMAGE`、`RUNNER_SERVICE_IMAGE` 去重后导出到 `IMAGE_ARCHIVE_PATH`。把归档复制到目标机器后，再执行：

```bash
scripts/import-images.sh
```

即可一键导入部署所需镜像。

镜像内默认包含：

- `nvcc`
- `cmake 3.26.0`
- `ninja`
- `gcc/g++`
- `git`
- `gdb`
- `python3`
- `pip`
- `conan`

构建成功后，可以验证版本：

```bash
docker run --rm "${BUILDER_IMAGE}" nvcc --version
docker run --rm "${BUILDER_IMAGE}" cmake --version
docker run --rm "${BUILDER_IMAGE}" conan --version
```

期望结果：

- `nvcc` 显示 `release 11.7`
- `cmake` 显示 `3.26.0`
- `conan` 能输出版本号

## 6. 启动 GitLab Runner 服务

执行：

```bash
scripts/compose.sh up -d
scripts/compose.sh ps
```

Compose 入口脚本会自动选择：

- `docker compose`
- 或 `docker-compose`

Runner 主容器使用镜像：

- `gitlab/gitlab-runner:alpine-v16.10.1`

运行后可检查：

```bash
docker logs gitlab-runner
```

期望结果：

- 容器已启动
- 没有明显配置挂载错误
- `runner/config/` 和 `runner/cache/` 已正常挂载

## 7. 注册共享 Runner

本平台设计了两个 Runner 池：

### 7.1 默认 GPU Runner 池

适用于单卡构建任务：

```bash
runner/register-runner.sh gpu
```

默认标签：

- `gpu`
- `cuda`
- `cuda-11`

### 7.2 多卡 GPU Runner 池

适用于需要多张 GPU 可见的任务：

```bash
runner/register-runner.sh multi
```

默认标签：

- `gpu-multi`
- `cuda`
- `cuda-11`

注册完成后，GitLab 界面中应能看到两个共享 Runner：

- 一个面向普通 GPU 任务
- 一个面向多卡任务

## 8. 项目如何接入共享 Runner

项目侧不需要自己维护 Runner，只需要在 `.gitlab-ci.yml` 中：

1. 使用平台提供的标准 builder image
2. 填写正确的 tags
3. 在 job 中执行自己的构建命令

示例：

```yaml
default:
  image: registry.example.com/devops/cuda-builder:cuda11.7-cmake3.26-centos7
  tags:
    - gpu
    - cuda
    - cuda-11
```

完整示例参考：

- [examples/gitlab-ci/shared-gpu-runner.yml](/home/joe/repo/gpu-devops/examples/gitlab-ci/shared-gpu-runner.yml)

### 8.1 单卡任务示例

```yaml
gpu-smoke:
  stage: verify
  tags:
    - gpu
    - cuda
    - cuda-11
  script:
    - nvidia-smi
    - nvcc --version
    - cmake --version
```

### 8.2 多卡任务示例

```yaml
multi-gpu-smoke:
  stage: verify
  tags:
    - gpu-multi
    - cuda
    - cuda-11
  variables:
    GPU_COUNT: "2"
  script:
    - echo "Requested GPU count: ${GPU_COUNT}"
    - nvidia-smi
```

注意：

- v1 中，多卡调度是通过独立 Runner 池隔离，不是 GitLab 调度器精确分配 GPU 数量
- 如果项目需要额外依赖，建议在项目流水线中安装，或者在平台基础镜像上派生项目镜像

## 9. 最小 CUDA/CMake 样例验证

仓库已提供一个最小样例：

- [examples/cuda-smoke/CMakeLists.txt](/home/joe/repo/gpu-devops/examples/cuda-smoke/CMakeLists.txt)
- [examples/cuda-smoke/main.cu](/home/joe/repo/gpu-devops/examples/cuda-smoke/main.cu)

项目流水线可直接使用：

```bash
cmake -S examples/cuda-smoke -B build -G Ninja
cmake --build build
```

如果要在本机验证，也可以直接运行：

```bash
cmake -S examples/cuda-smoke -B /tmp/cuda-smoke-build -G "Unix Makefiles"
cmake --build /tmp/cuda-smoke-build
```

## 10. 推荐上线流程

建议按下面顺序上线：

1. 执行 `scripts/verify-host.sh`
2. 构建并验证 builder 镜像
3. 启动 `gitlab-runner` 容器
4. 注册 `gpu` Runner
5. 注册 `gpu-multi` Runner
6. 在测试项目中使用示例 CI 文件
7. 通过 smoke pipeline 后，再开放给业务项目使用

## 11. 常见问题排查

### 11.1 `docker build` 无法拉取 CUDA 基础镜像

排查项：

- Docker daemon 镜像源是否可用
- 网络代理是否配置正确
- Docker daemon 是否需要重启
- 是否能单独执行：

```bash
docker pull nvidia/cuda:11.7.1-devel-centos7

### 11.1.1 CentOS 7 特殊说明

CentOS 7 已经进入 EOL，默认 `mirrorlist.centos.org` 不再稳定可用，因此当前 Dockerfile 会在构建时自动把基础 Yum 源切到 `vault.centos.org`。

如果你在企业网络里还有内部 YUM 镜像，建议后续改成内部源，减少对公网 vault 的依赖。

### 11.1.2 CentOS 7 兼容性建议

CentOS 7 可以满足当前 CUDA 11.7 + CMake 3.26 的平台目标，但它并不适合作为长期演进基线。建议你在后续版本规划里明确：

- 是否继续保留 CentOS 7 兼容性
- 是否迁移到 Rocky Linux / AlmaLinux
- 是否迁移到受支持的 Ubuntu LTS 基线

如果未来需要更新的 Python、OpenSSL 或 Conan 生态，CentOS 7 的维护成本会越来越高。
```

### 11.2 构建卡在下载 CMake

本仓库当前从 GitHub Release 下载 CMake 安装脚本。若卡住，请检查：

- 构建容器是否能访问 GitHub
- 本机代理是否只绑定在 `127.0.0.1`
- `scripts/build-builder-image.sh` 是否已使用最新版，支持代理透传和 `--network host`

### 11.3 容器内提示没有 GPU

如果只是运行：

```bash
docker run --rm "${BUILDER_IMAGE}" nvcc --version
```

出现 “NVIDIA Driver was not detected” 警告是正常的，因为这个命令没有启用 GPU runtime。

真正要验证 GPU 可见性时，请在 Runner job 中执行：

```bash
nvidia-smi
```

或者手动测试：

```bash
docker run --rm --gpus all "${BUILDER_IMAGE}" nvidia-smi
```

### 11.4 Runner 注册成功但任务不执行

重点检查：

- GitLab 项目中的 tags 是否和 Runner 标签完全一致
- Runner 是否是 shared runner
- `RUNNER_RUN_UNTAGGED` 是否被关闭
- GitLab 项目是否允许使用 shared runner

## 12. 参考文档

- [docs/operations.md](/home/joe/repo/gpu-devops/docs/operations.md)
- [docs/self-check.md](/home/joe/repo/gpu-devops/docs/self-check.md)
- [docs/platform-contract.md](/home/joe/repo/gpu-devops/docs/platform-contract.md)
