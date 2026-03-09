# Ubuntu 部署指南

本文档适用于仓库位于 `/projects/we-mp-rss` 的单机 Ubuntu 部署，默认在服务器基于本地源码构建 Docker 镜像，并通过国内代理镜像源拉取基础镜像。

## 架构

- Nginx 对外提供 `80/443`
- 应用容器监听 `127.0.0.1:8001`
- 默认使用项目原生 SQLite，数据库文件保存在 `runtime/data`
- 应用镜像默认构建为本地标签 `we-mp-rss:local`

## 前置条件

1. Ubuntu 22.04 或 24.04 LTS
2. 云安全组只开放 `22/80/443`
3. 域名已解析到云主机
4. 仓库路径固定为 `/projects/we-mp-rss`
5. 不额外配置 MySQL，保持项目默认 SQLite

## Docker 国内镜像源

项目 Dockerfile 已默认使用以下代理域名：

- Docker Hub: `docker.1ms.run`
- GHCR: `ghcr.1ms.run`
- NPM: `https://registry.npmmirror.com`

建议同时为 Docker daemon 配置镜像加速，避免 `docker build` 时回退到官方源：

```bash
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json >/dev/null <<'EOF'
{
  "registry-mirrors": [
    "https://docker.1ms.run"
  ]
}
EOF
sudo systemctl restart docker
```

## 安装运行时

```bash
sudo apt update
sudo apt install -y ca-certificates curl gnupg nginx certbot python3-certbot-nginx
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://mirrors.ustc.edu.cn/docker-ce/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://mirrors.ustc.edu.cn/docker-ce/linux/ubuntu $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

## 首次部署

1. 创建运行目录

```bash
mkdir -p /projects/we-mp-rss/runtime/data
```

2. 准备环境变量

```bash
cd /projects/we-mp-rss
cp deploy/.env.example deploy/.env.prod
```

编辑 `deploy/.env.prod`，至少修改：

- `DOMAIN`
- `ADMIN_PASSWORD`
- `SECRET_KEY`

默认已经配置本地构建和国内代理参数：

- `WERSS_LOCAL_IMAGE=we-mp-rss:local`
- `DOCKERHUB_MIRROR=docker.1ms.run`
- `GHCR_MIRROR=ghcr.1ms.run`
- `NPM_REGISTRY=https://registry.npmmirror.com`

3. 执行部署

```bash
cd /projects/we-mp-rss
chmod +x deploy/*.sh
./deploy/deploy.sh
```

部署脚本执行的是：

- `docker compose build --pull app`
- `docker compose up -d`

会在服务器本地构建前端和应用镜像，但默认会通过代理地址拉取 `node:20` 与运行时基础镜像。

4. 检查应用

```bash
cd /projects/we-mp-rss/deploy
docker compose --env-file .env.prod -f docker-compose.prod.yml ps
docker compose --env-file .env.prod -f docker-compose.prod.yml logs -f app
curl http://127.0.0.1:8001/api/openapi.json
```

## Nginx 反向代理

1. 复制模板

```bash
sudo cp /projects/we-mp-rss/deploy/nginx.we-mp-rss.conf /etc/nginx/sites-available/we-mp-rss.conf
```

2. 将其中的 `server_name rss.example.com;` 改成你的域名

3. 启用站点

```bash
sudo ln -sf /etc/nginx/sites-available/we-mp-rss.conf /etc/nginx/sites-enabled/we-mp-rss.conf
sudo nginx -t
sudo systemctl enable --now nginx
sudo systemctl reload nginx
```

## HTTPS

```bash
sudo certbot --nginx -d your-domain.example.com
```

## 升级

```bash
cd /projects/we-mp-rss
git pull
./deploy/deploy.sh
```

## 备份

```bash
cd /projects/we-mp-rss
./deploy/backup.sh
```

备份内容：

- `runtime/data` 压缩包
- 其中包含 SQLite 数据库文件与运行时缓存
- 当前部署配置副本

## 常见问题

### 国内云主机拉镜像慢或失败

先单独测试代理基础镜像：

```bash
docker pull docker.1ms.run/library/node:20
docker pull ghcr.1ms.run/rachelos/base-full:latest
```

如果代理基础镜像可拉取，`./deploy/deploy.sh` 就可以直接本地构建。

### 管理员账号没有变化

管理员账号只在空库首次初始化时生效。已经有数据后，修改 `.env.prod` 不会覆盖现有账号。

### SQLite 数据库文件在哪

默认数据库文件位于 `/projects/we-mp-rss/runtime/data/db.db`。只要保留 `runtime/data`，数据库就会持久化。

### 8001 端口无法访问

该方案故意只绑定 `127.0.0.1:8001`。公网应通过 Nginx 的 `80/443` 访问。

### 浏览器采集异常

默认使用 `webkit`。如果运行环境缺少浏览器依赖或应用启动异常，直接查看容器日志：

```bash
cd /projects/we-mp-rss/deploy
docker compose --env-file .env.prod -f docker-compose.prod.yml logs -f app
```

## 可选方案

如果你的服务器可以稳定访问官方源，也可以在 `deploy/.env.prod` 中覆盖：

- `DOCKERHUB_MIRROR`
- `GHCR_MIRROR`
- `NPM_REGISTRY`

例如改回官方源：

```bash
DOCKERHUB_MIRROR=docker.io
GHCR_MIRROR=ghcr.io
NPM_REGISTRY=https://registry.npmjs.org
```
