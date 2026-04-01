# Ubuntu 20.04 离线安装 Docker CE Rootless + Docker Compose + NVIDIA Container Toolkit 操作手册

> 适用于：在线机 Ubuntu 22.04、离线机 Ubuntu 20.04  
> 目标：Rootless Docker、Docker Compose、NVIDIA GPU 容器支持、支持多用户 rootless Docker  
> 文档版本：v1.0

---

## 1. 目标与适用范围

本文档用于指导在 **Ubuntu 20.04 离线环境** 中完成以下能力建设：

- 安装 Docker CE
- 启用 Rootless Docker
- 启用 Docker Compose
- 安装 NVIDIA Container Toolkit
- 支持 `docker run --gpus all`
- 支持多用户分别使用 rootless Docker
- 兼容当前用户使用 **zsh**，将环境变量写入 `~/.zshrc`

本文档同时覆盖了本次实施过程中遇到的典型问题，包括：

- 旧 `docker.io` / `containerd` / `runc` 清理不彻底
- `containerd` 进程被 systemd 自动拉起
- `disable-nouveau.conf` 配置错误导致 `update-initramfs` / `dpkg` 报错
- Rootless Docker 配置后的 `docker` 组残余问题
- 多用户共存时的 rootless Docker 配置方式

---

## 2. 版本清单

本次实际使用并验证通过的版本如下：

### 2.1 Docker 相关

- `containerd.io_1.7.27-1_amd64.deb`
- `docker-ce_27.5.1-1~ubuntu.20.04~focal_amd64.deb`
- `docker-ce-cli_27.5.1-1~ubuntu.20.04~focal_amd64.deb`
- `docker-ce-rootless-extras_27.5.1-1~ubuntu.20.04~focal_amd64.deb`
- `docker-buildx-plugin_0.23.0-1~ubuntu.20.04~focal_amd64.deb`
- `docker-compose-plugin_2.35.1-1~ubuntu.20.04~focal_amd64.deb`

### 2.2 Rootless 依赖包

- `uidmap`
- `slirp4netns`
- `dbus-user-session`

### 2.3 NVIDIA Toolkit

- `nvidia-container-toolkit_1.19.0-1_amd64.deb`
- `nvidia-container-toolkit-base_1.19.0-1_amd64.deb`
- `libnvidia-container1_1.19.0-1_amd64.deb`
- `libnvidia-container-tools_1.19.0-1_amd64.deb`

### 2.4 GPU 验证镜像

- `nvidia/cuda:12.4.1-base-ubuntu20.04`

---

## 3. 架构说明

整体流程分为四部分：

1. 在线机准备离线包
2. 离线机清理旧环境
3. 离线机安装 Docker CE + Rootless + Compose + NVIDIA Toolkit
4. 验证与收尾

### 3.1 Rootless Docker 工作方式

Rootless Docker 不使用系统级 `/var/run/docker.sock`，而使用每个用户自己的 socket：

```bash
/run/user/<uid>/docker.sock
```

本机实际使用方式为：

```bash
export DOCKER_HOST=unix:///run/user/$(id -u)/docker.sock
```

### 3.2 多用户 rootless 的原则

多个用户可以共存，但必须遵循以下原则：

- 系统级 Docker 包只安装一次
- 每个用户各自拥有：
  - 独立的 rootless daemon
  - 独立的 `~/.config/docker/daemon.json`
  - 独立的 `/run/user/<uid>/docker.sock`
  - 独立的 `subuid/subgid`
- 每个用户都要单独执行一次：
  - `dockerd-rootless-setuptool.sh install`
  - `systemctl --user enable --now docker`
  - `nvidia-ctk runtime configure --runtime=docker --config=$HOME/.config/docker/daemon.json`（如果该用户也要 GPU）

---

# 第一部分：在线机准备

## 4. 在线机环境要求

- 在线机操作系统：Ubuntu 22.04
- 可联网
- 已安装 Docker
- 能拉取 Ubuntu 20.04 容器镜像
- 能访问 Docker 官方下载地址
- 能访问 NVIDIA toolkit 仓库

---

## 5. 创建离线包目录

```bash
mkdir -p ~/offline-rootless-docker/{ubuntu20-debs,docker-ce-focal,nvidia-toolkit}
cd ~/offline-rootless-docker
```

---

## 6. 使用 Ubuntu 20.04 容器下载 rootless 依赖包

### 6.1 命令

```bash
docker run --rm -it \
  -v "$PWD/ubuntu20-debs:/pkgs" \
  ubuntu:20.04 bash -lc '
    export DEBIAN_FRONTEND=noninteractive
    apt update
    apt install -y --download-only \
      uidmap \
      slirp4netns \
      dbus-user-session
    cp -v /var/cache/apt/archives/*.deb /pkgs/
  '
```

### 6.2 说明

这一步的目的：

- 强制使用 **Ubuntu 20.04/focal** 的依赖包
- 避免在线机是 22.04 时误下载成 jammy 包
- 为离线 Ubuntu 20.04 提供 rootless 所需依赖

### 6.3 检查

```bash
ls -lh ~/offline-rootless-docker/ubuntu20-debs
```

---

## 7. 下载 Docker CE focal 离线包

### 7.1 查看 focal 包目录

```bash
BASE='https://download.docker.com/linux/ubuntu/dists/focal/pool/stable/amd64'
cd ~/offline-rootless-docker/docker-ce-focal

curl -fsSL "$BASE/" | grep -E 'docker-ce_|docker-ce-cli_|docker-ce-rootless-extras_|docker-buildx-plugin_|docker-compose-plugin_|containerd.io_' > index.html
```

### 7.2 确认可用版本

```bash
grep -oE 'docker-ce_[^"]+\.deb' index.html | sort -V | tail -n 20
grep -oE 'docker-ce-cli_[^"]+\.deb' index.html | sort -V | tail -n 20
grep -oE 'docker-ce-rootless-extras_[^"]+\.deb' index.html | sort -V | tail -n 20
grep -oE 'containerd.io_[^"]+\.deb' index.html | sort -V | tail -n 20
grep -oE 'docker-buildx-plugin_[^"]+\.deb' index.html | sort -V | tail -n 20
grep -oE 'docker-compose-plugin_[^"]+\.deb' index.html | sort -V | tail -n 20
```

### 7.3 下载最终选定版本

```bash
BASE='https://download.docker.com/linux/ubuntu/dists/focal/pool/stable/amd64'
cd ~/offline-rootless-docker/docker-ce-focal

curl -fLO "$BASE/containerd.io_1.7.27-1_amd64.deb"
curl -fLO "$BASE/docker-ce_27.5.1-1~ubuntu.20.04~focal_amd64.deb"
curl -fLO "$BASE/docker-ce-cli_27.5.1-1~ubuntu.20.04~focal_amd64.deb"
curl -fLO "$BASE/docker-ce-rootless-extras_27.5.1-1~ubuntu.20.04~focal_amd64.deb"
curl -fLO "$BASE/docker-buildx-plugin_0.23.0-1~ubuntu.20.04~focal_amd64.deb"
curl -fLO "$BASE/docker-compose-plugin_2.35.1-1~ubuntu.20.04~focal_amd64.deb"
```

### 7.4 生成校验值

```bash
cd ~/offline-rootless-docker/docker-ce-focal
sha256sum ./*.deb > SHA256SUMS
cat SHA256SUMS
```

---

## 8. 下载 NVIDIA Container Toolkit 离线包

### 8.1 创建目录

```bash
mkdir -p ~/offline-rootless-docker/nvidia-toolkit
cd ~/offline-rootless-docker/nvidia-toolkit
```

### 8.2 添加 key

```bash
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
| sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
```

### 8.3 添加仓库

```bash
curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
| sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
| sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
```

### 8.4 更新仓库并下载

```bash
sudo apt update

apt download nvidia-container-toolkit
apt download nvidia-container-toolkit-base
apt download libnvidia-container1
apt download libnvidia-container-tools
```

### 8.5 生成校验值

```bash
sha256sum ~/offline-rootless-docker/nvidia-toolkit/*.deb > ~/offline-rootless-docker/nvidia-toolkit/SHA256SUMS
cat ~/offline-rootless-docker/nvidia-toolkit/SHA256SUMS
```

---

## 9. 打包离线安装包

```bash
cd ~/offline-rootless-docker
tar czf offline-rootless-docker-focal.tar.gz ubuntu20-debs docker-ce-focal nvidia-toolkit
ls -alh
```

将 `offline-rootless-docker-focal.tar.gz` 拷贝到离线机。

---

# 第二部分：离线机安装

## 10. 离线机前提条件

- Ubuntu 20.04
- NVIDIA 驱动已安装并可用
- 能访问本地文件系统中的离线包
- 当前使用用户为普通用户，例如 `zhangc`
- shell 为 `zsh`

---

## 11. 解压离线安装包

```bash
cd ~/Downloads
mkdir -p ~/offline-rootless-docker
tar xzf offline-rootless-docker-focal.tar.gz -C ~/offline-rootless-docker
cd ~/offline-rootless-docker
ls -alh
```

---

## 12. 彻底清理旧环境

> 本步骤适用于“清理安装”，即不保留旧配置、旧 images、旧容器、旧 volumes。

### 12.1 停止旧服务

```bash
sudo systemctl stop docker.service 2>/dev/null || true
sudo systemctl stop docker.socket 2>/dev/null || true
sudo systemctl disable docker.service 2>/dev/null || true
sudo systemctl disable docker.socket 2>/dev/null || true

systemctl --user stop docker.service 2>/dev/null || true
systemctl --user disable docker.service 2>/dev/null || true
systemctl --user daemon-reload

sudo systemctl stop containerd.service 2>/dev/null || true
sudo systemctl disable containerd.service 2>/dev/null || true

pkill -f dockerd-rootless 2>/dev/null || true
pkill -f rootlesskit 2>/dev/null || true
pkill -f slirp4netns 2>/dev/null || true
sudo pkill -9 dockerd 2>/dev/null || true
sudo pkill -9 containerd 2>/dev/null || true
```

检查无残留进程：

```bash
ps -ef | egrep 'dockerd|containerd|rootlesskit|slirp4netns' | grep -v grep
```

### 12.2 卸载旧包

```bash
sudo apt purge -y docker docker.io containerd runc
sudo apt purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras
sudo apt purge -y nvidia-container-toolkit nvidia-container-toolkit-base libnvidia-container1 libnvidia-container-tools
sudo apt autoremove -y
sudo apt clean
```

### 12.3 删除旧数据与配置

```bash
sudo rm -rf /var/lib/docker
sudo rm -rf /var/lib/containerd
sudo rm -rf /etc/docker
sudo rm -f /var/run/docker.sock

rm -rf ~/.local/share/docker
rm -rf ~/.config/docker
rm -rf ~/.docker
rm -f /run/user/$(id -u)/docker.sock
rm -f /run/user/$(id -u)/docker.pid
rm -rf /run/user/$(id -u)/docker

rm -f ~/.config/systemd/user/docker.service
rm -f ~/.config/systemd/user/docker.socket
systemctl --user daemon-reload

sudo sed -i '/^zhangc:/d' /etc/subuid
sudo sed -i '/^zhangc:/d' /etc/subgid
```

### 12.4 检查是否清干净

```bash
dpkg -l | egrep 'docker|containerd|runc|nvidia-container' || true
```

---

## 13. 修复 `disable-nouveau.conf` 的典型问题

如果安装过程中出现：

```text
ignoring bad line starting with "blackList"
```

说明 `/etc/modprobe.d/disable-nouveau.conf` 内容错误。

### 13.1 正确修复方法

```bash
cat <<'EOF' | sudo tee /etc/modprobe.d/disable-nouveau.conf
blacklist nouveau
options nouveau modeset=0
EOF

sudo update-initramfs -u
sudo dpkg --configure -a
```

> 注意：不能写成 `blackList`，也不能把两行写成一个带引号的字符串。

---

## 14. 安装 rootless 依赖包

```bash
cd ~/offline-rootless-docker/ubuntu20-debs
ls -lh
sudo dpkg -i ./*.deb
sudo dpkg --configure -a
```

### 14.1 检查依赖是否安装成功

```bash
which newuidmap
which newgidmap
which slirp4netns
dpkg -l | egrep 'uidmap|slirp4netns|dbus-user-session'
```

预期结果：

- `/usr/bin/newuidmap`
- `/usr/bin/newgidmap`
- `/usr/bin/slirp4netns`
- `uidmap`、`slirp4netns`、`dbus-user-session` 状态为 `ii`

---

## 15. 安装 Docker CE + Compose + Rootless Extras

```bash
cd ~/offline-rootless-docker/docker-ce-focal
ls -lh

sudo dpkg -i containerd.io_*.deb
sudo dpkg -i docker-ce-cli_*.deb docker-buildx-plugin_*.deb docker-compose-plugin_*.deb
sudo dpkg -i docker-ce_*.deb docker-ce-rootless-extras_*.deb
sudo dpkg --configure -a
```

### 15.1 检查安装结果

```bash
docker version
which dockerd-rootless-setuptool.sh
docker compose version
```

预期结果：

- `docker version` 正常
- `dockerd-rootless-setuptool.sh` 存在
- `docker compose version` 正常输出

---

## 16. 配置 Rootless Docker

### 16.1 subordinate uid/gid

```bash
echo 'zhangc:100000:65536' | sudo tee -a /etc/subuid
echo 'zhangc:100000:65536' | sudo tee -a /etc/subgid

grep '^zhangc:' /etc/subuid
grep '^zhangc:' /etc/subgid
```

### 16.2 检查 user namespace 参数

```bash
cat /proc/sys/kernel/unprivileged_userns_clone
cat /proc/sys/user/max_user_namespaces
```

如果第一项不是 `1`，执行：

```bash
echo 'kernel.unprivileged_userns_clone=1' | sudo tee /etc/sysctl.d/99-rootless-docker.conf
echo 'user.max_user_namespaces=28633' | sudo tee -a /etc/sysctl.d/99-rootless-docker.conf
sudo sysctl --system
```

### 16.3 关闭系统级 Docker

```bash
sudo systemctl disable --now docker.service docker.socket
sudo rm -f /var/run/docker.sock
sudo systemctl disable --now containerd.service
```

### 16.4 安装并启动 rootless daemon

```bash
dockerd-rootless-setuptool.sh install

systemctl --user daemon-reload
systemctl --user enable --now docker
systemctl --user status docker --no-pager

sudo loginctl enable-linger zhangc
```

### 16.5 使用 zsh 写入环境变量

```bash
grep -q 'DOCKER_HOST=unix:///run/user/$(id -u)/docker.sock' ~/.zshrc || \
echo 'export DOCKER_HOST=unix:///run/user/$(id -u)/docker.sock' >> ~/.zshrc

source ~/.zshrc
echo "$DOCKER_HOST"
```

---

## 17. 安装 NVIDIA Container Toolkit

```bash
cd ~/offline-rootless-docker/nvidia-toolkit
ls -lh
sudo dpkg -i ./*.deb
sudo dpkg --configure -a
```

检查：

```bash
which nvidia-ctk
dpkg -l | egrep 'nvidia-container-toolkit|libnvidia-container'
```

---

## 18. 配置 rootless Docker 的 NVIDIA runtime

### 18.1 普通用户执行

```bash
nvidia-ctk runtime configure --runtime=docker --config=$HOME/.config/docker/daemon.json
systemctl --user restart docker
```

### 18.2 管理员执行 `no-cgroups`

```bash
sudo nvidia-ctk config --set nvidia-container-cli.no-cgroups --in-place
systemctl --user restart docker
```

### 18.3 检查 runtime 配置

```bash
docker info | grep -i runtime -A 8
cat ~/.config/docker/daemon.json
```

预期结果：

- `Runtimes:` 中包含 `nvidia`
- `daemon.json` 中存在 `nvidia-container-runtime`

---

## 19. 导入 CUDA 测试镜像

### 19.1 在线机导出

```bash
docker pull nvidia/cuda:12.4.1-base-ubuntu20.04
docker save -o nvidia-cuda-12.4.1-base-ubuntu20.04.tar nvidia/cuda:12.4.1-base-ubuntu20.04
```

### 19.2 离线机导入

```bash
docker load -i nvidia-cuda-12.4.1-base-ubuntu20.04.tar
```

---

# 第三部分：验证

## 20. 验证 rootless Docker

```bash
echo "$DOCKER_HOST"
docker info
docker run --rm hello-world
```

---

## 21. 验证 Docker Compose

```bash
docker compose version
```

---

## 22. 验证 GPU 容器

```bash
nvidia-smi
docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu20.04 nvidia-smi
```

---

## 23. 验证 Compose + GPU

### 23.1 创建测试目录

```bash
mkdir -p ~/compose-gpu-test
cd ~/compose-gpu-test
```

### 23.2 写入 `compose.yaml`

```bash
cat > compose.yaml <<'EOF'
services:
  nvidia-smi:
    image: nvidia/cuda:12.4.1-base-ubuntu20.04
    command: nvidia-smi
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
EOF
```

### 23.3 运行

```bash
docker compose up
```

---

# 第四部分：常见问题

## 24. `ubuntu20-debs` 安装时报错

### 24.1 现象

安装 `ubuntu20-debs` 时出现：

```text
ignoring bad line starting with "blackList"
```

### 24.2 原因

`/etc/modprobe.d/disable-nouveau.conf` 内容写错。

### 24.3 处理

```bash
cat <<'EOF' | sudo tee /etc/modprobe.d/disable-nouveau.conf
blacklist nouveau
options nouveau modeset=0
EOF

sudo update-initramfs -u
sudo dpkg --configure -a
```

---

## 25. `containerd` 已 stop，但又自动起来

### 25.1 原因

`containerd.service` 仍被 systemd 管理。

### 25.2 处理

```bash
sudo systemctl stop containerd.service
sudo systemctl disable containerd.service
sudo pkill -9 containerd
ps -ef | egrep 'dockerd|containerd|rootlesskit|slirp4netns' | grep -v grep
```

---

## 26. 旧 `docker` 组仍有残留

### 26.1 检查

```bash
getent group docker
id zhangc
groups zhangc
echo "$DOCKER_HOST"
ls -l /var/run/docker.sock 2>/dev/null || true
ls -l /run/user/$(id -u)/docker.sock 2>/dev/null || true
```

### 26.2 现象说明

如果当前输出类似：

- 用户仍属于 `docker` 组
- 但实际使用的是 `/run/user/<uid>/docker.sock`

说明：

- rootless Docker 正常
- 旧 docker group 权限仍有残余
- 当前用户不再依赖该组

### 26.3 只移除当前用户

```bash
sudo gpasswd -d zhangc docker
```

重新登录后检查：

```bash
groups zhangc
docker info
docker compose version
```

> 注意：如果 `docker` 组里还有其他用户（如 `gitlab-runner`），不要直接删整个组。

---

## 27. 多个用户都需要 rootless Docker

### 27.1 设计原则

- 系统公共包只安装一次
- 每个用户各自拥有：
  - 自己的 rootless daemon
  - 自己的 `/run/user/<uid>/docker.sock`
  - 自己的 `~/.config/docker/daemon.json`
  - 自己的 `subuid/subgid`
- 每个用户都要单独执行：
  - `dockerd-rootless-setuptool.sh install`
  - `systemctl --user enable --now docker`
  - `loginctl enable-linger <user>`
  - 写自己的 `~/.zshrc`
  - 如需 GPU，再各自执行一次 `nvidia-ctk runtime configure`

### 27.2 为第二个用户配置示例

管理员执行：

```bash
echo 'fengkw:165536:65536' | sudo tee -a /etc/subuid
echo 'fengkw:165536:65536' | sudo tee -a /etc/subgid
sudo loginctl enable-linger fengkw
```

第二个用户登录后执行：

```bash
dockerd-rootless-setuptool.sh install
systemctl --user daemon-reload
systemctl --user enable --now docker
echo 'export DOCKER_HOST=unix:///run/user/$(id -u)/docker.sock' >> ~/.zshrc
source ~/.zshrc
docker info
docker compose version
```

如果该用户也需要 GPU：

```bash
nvidia-ctk runtime configure --runtime=docker --config=$HOME/.config/docker/daemon.json
systemctl --user restart docker
```

---

## 28. rootless Docker 出现无 cgroups 警告

### 28.1 现象

```text
WARNING: Running in rootless-mode without cgroups.
```

### 28.2 说明

当前主机未以完整 cgroup v2 模式向 rootless Docker 提供 cgroup 支持。

### 28.3 处理建议

如果以下命令已正常执行，则当前可直接使用：

```bash
docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu20.04 nvidia-smi
```

因此该告警在当前环境下可接受，不阻塞使用。

---

## 29. 最终收尾检查

```bash
echo "$DOCKER_HOST"
docker info
docker compose version
docker run --rm hello-world
docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu20.04 nvidia-smi
getent group docker
groups zhangc
```

---

## 30. 回滚建议

如果需要回滚到“未安装 Docker CE / Rootless / NVIDIA Toolkit”的状态，可执行：

```bash
sudo systemctl stop docker.service 2>/dev/null || true
sudo systemctl stop docker.socket 2>/dev/null || true
systemctl --user stop docker.service 2>/dev/null || true
systemctl --user disable docker.service 2>/dev/null || true
systemctl --user daemon-reload

sudo systemctl stop containerd.service 2>/dev/null || true
sudo systemctl disable containerd.service 2>/dev/null || true

sudo apt purge -y docker docker.io docker-ce docker-ce-cli docker-ce-rootless-extras docker-buildx-plugin docker-compose-plugin containerd containerd.io runc
sudo apt purge -y nvidia-container-toolkit nvidia-container-toolkit-base libnvidia-container1 libnvidia-container-tools
sudo apt autoremove -y
sudo apt clean

sudo rm -rf /var/lib/docker /var/lib/containerd /etc/docker
sudo rm -f /var/run/docker.sock

rm -rf ~/.local/share/docker ~/.config/docker ~/.docker
rm -rf /run/user/$(id -u)/docker
rm -f /run/user/$(id -u)/docker.sock
rm -f /run/user/$(id -u)/docker.pid
rm -f ~/.config/systemd/user/docker.service ~/.config/systemd/user/docker.socket
systemctl --user daemon-reload
```

---

## 31. 最终结论

完成本文档后，离线 Ubuntu 20.04 环境将具备以下能力：

- Docker CE
- Rootless Docker
- Docker Compose
- NVIDIA Container Toolkit
- `docker run --gpus all`
- 支持多个用户分别配置自己的 rootless Docker
- 当前用户使用 `zsh` 环境正常
