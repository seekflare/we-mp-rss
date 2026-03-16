# Ubuntu 部署指南

本文档适用于仓库位于 `/projects/we-mp-rss` 的单机 Ubuntu 部署。默认在服务器基于本地源码构建 Docker 镜像，并通过国内代理镜像源拉取基础镜像。

支持两种访问模式：

- 域名模式：`https://your-domain`，适合长期公网访问
- IP 模式：`http://<public-ip>`，适合个人使用或不想处理备案/证书的场景

如果你已经按域名模式上线，后续想回退到 IP 访问，请直接看 `docs/domain-to-ip-access.md`。

## 架构

- Nginx 对外提供 `80`，域名模式可额外提供 `443`
- 应用容器监听 `127.0.0.1:8001`
- 默认使用项目原生 SQLite，数据库文件保存在 `runtime/data`
- 应用镜像默认构建为本地标签 `we-mp-rss:local`
- RSS 绝对地址由 `RSS_SCHEME` 和 `DOMAIN` 共同生成，格式为 `${RSS_SCHEME}://${DOMAIN}/`

## 前置条件

1. Ubuntu 22.04 或 24.04 LTS
2. 仓库路径固定为 `/projects/we-mp-rss`
3. 不额外配置 MySQL，保持项目默认 SQLite
4. 根据访问模式准备网络入口：
   - IP 模式：云安全组开放 `22/80`
   - 域名模式：云安全组开放 `22/80/443`
5. 根据访问模式准备入口：
   - IP 模式：服务器已绑定固定公网 IP
   - 域名模式：域名已解析到当前云主机

## Docker 国内镜像源

项目 Dockerfile 已默认使用以下代理地址：

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

### 1. 创建运行目录

```bash
mkdir -p /projects/we-mp-rss/runtime/data
```

### 2. 准备环境变量

```bash
cd /projects/we-mp-rss
cp deploy/.env.example deploy/.env.prod
```

编辑 `deploy/.env.prod`，至少修改：

- `DOMAIN`
- `RSS_SCHEME`
- `ADMIN_PASSWORD`
- `SECRET_KEY`

填写规则：

- `DOMAIN` 只填域名或公网 IP，不要带 `http://` 或 `https://`
- 域名模式：`RSS_SCHEME=https`
- IP 模式：`RSS_SCHEME=http`

例如：

```dotenv
# 域名模式
DOMAIN=we-rss.xyz
RSS_SCHEME=https

# IP 模式
DOMAIN=1.2.3.4
RSS_SCHEME=http
```

默认已经配置本地构建和国内代理参数：

- `WERSS_LOCAL_IMAGE=we-mp-rss:local`
- `DOCKERHUB_MIRROR=docker.1ms.run`
- `GHCR_MIRROR=ghcr.1ms.run`
- `NPM_REGISTRY=https://registry.npmmirror.com`

### 3. 执行部署

```bash
cd /projects/we-mp-rss
chmod +x deploy/*.sh
./deploy/deploy.sh
```

部署脚本执行的是：

- `docker compose build --pull app`
- `docker compose up -d`

会在服务器本地构建前端和应用镜像，并通过代理地址拉取 `node:20` 与运行时基础镜像。

### 4. 检查应用

```bash
cd /projects/we-mp-rss/deploy
docker compose --env-file .env.prod -f docker-compose.prod.yml ps
docker compose --env-file .env.prod -f docker-compose.prod.yml logs -f app
docker compose --env-file .env.prod -f docker-compose.prod.yml exec app env | grep RSS_BASE_URL
curl http://127.0.0.1:8001/api/openapi.json
```

预期：

- 容器状态为 `Up`
- `RSS_BASE_URL` 形如 `https://your-domain/` 或 `http://<public-ip>/`
- 本机 `127.0.0.1:8001` 可访问 OpenAPI

## Nginx 反向代理

### 域名模式

复制域名模板：

```bash
sudo cp /projects/we-mp-rss/deploy/nginx.we-mp-rss.conf /etc/nginx/sites-available/we-mp-rss.conf
```

将其中的 `server_name rss.example.com;` 改成你的域名，然后启用站点：

```bash
sudo ln -sf /etc/nginx/sites-available/we-mp-rss.conf /etc/nginx/sites-enabled/we-mp-rss.conf
sudo nginx -t
sudo systemctl enable --now nginx
sudo systemctl reload nginx
```

### IP 模式

复制 IP 专用模板：

```bash
sudo cp /projects/we-mp-rss/deploy/nginx.we-mp-rss.ip.conf /etc/nginx/sites-available/we-mp-rss.conf
sudo ln -sf /etc/nginx/sites-available/we-mp-rss.conf /etc/nginx/sites-enabled/we-mp-rss.conf
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl enable --now nginx
sudo systemctl reload nginx
```

这个模板会直接以 `80 default_server` 对外提供 `http://<public-ip>/`。

## HTTPS

仅域名模式需要执行：

```bash
sudo certbot --nginx -d your-domain.example.com
```

如果只使用 IP 访问，跳过此步骤。

## 验证

### 域名模式

```bash
curl -I http://your-domain.example.com
curl -I https://your-domain.example.com
curl https://your-domain.example.com/api/openapi.json
curl https://your-domain.example.com/rss
```

### IP 模式

```bash
curl -I http://<public-ip>/
curl http://<public-ip>/api/openapi.json
curl http://<public-ip>/rss
ss -lntp | grep -E ':80|:443|:8001'
```

IP 模式下建议看到：

- `80` 正常监听
- `8001` 只绑定 `127.0.0.1:8001`
- 不再强制跳转 `https`

## 升级

```bash
cd /projects/we-mp-rss
git pull
./deploy/deploy.sh
```

如果你使用 IP 模式，升级后建议额外确认：

```bash
grep '^RSS_SCHEME=' /projects/we-mp-rss/deploy/.env.prod
cd /projects/we-mp-rss/deploy
docker compose --env-file .env.prod -f docker-compose.prod.yml exec app env | grep RSS_BASE_URL
```

## 备份

```bash
cd /projects/we-mp-rss
./deploy/backup.sh
```

备份内容：

- `runtime/data` 压缩包
- `docker-compose.prod.yml`
- 域名模板和 IP 模板
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

### 8001 端口无法从公网访问

该方案故意只绑定 `127.0.0.1:8001`。公网应通过 Nginx 的 `80` 或 `80/443` 访问。

### 页面能打开，但 RSS 或 OPML 里的链接不对

优先检查：

- `DOMAIN` 是否填成了带协议的值
- `RSS_SCHEME` 是否和当前访问方式一致
- `RSS_BASE_URL` 是否已经生效并带结尾 `/`

确认命令：

```bash
cd /projects/we-mp-rss/deploy
docker compose --env-file .env.prod -f docker-compose.prod.yml exec app env | grep RSS_BASE_URL
```

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
