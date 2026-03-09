# Ubuntu 源码部署指南

本文档适用于仓库位于 `/projects/we-mp-rss` 的单机 Ubuntu 部署。

## 架构

- Nginx 对外提供 `80/443`
- 应用容器监听 `127.0.0.1:8001`
- 默认使用项目原生 SQLite，数据库文件保存在 `runtime/data`
- 前端生产构建产物复制到仓库根目录 `static/`

## 前置条件

1. Ubuntu 22.04 或 24.04 LTS
2. 云安全组只开放 `22/80/443`
3. 域名已解析到云主机
4. 仓库路径固定为 `/projects/we-mp-rss`
5. 不额外配置 MySQL，保持项目默认 SQLite

## 安装运行时

```bash
sudo apt update
sudo apt install -y ca-certificates curl gnupg nginx snapd
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
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

3. 执行部署

```bash
cd /projects/we-mp-rss
chmod +x deploy/*.sh
./deploy/deploy.sh
```

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
sudo snap install core
sudo snap refresh core
sudo snap install --classic certbot
sudo ln -sf /snap/bin/certbot /usr/bin/certbot
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

### 前端页面未更新

重新执行：

```bash
cd /projects/we-mp-rss
./deploy/build-frontend.sh
```

### 管理员账号没有变化

管理员账号只在空库首次初始化时生效。已经有数据后，修改 `.env.prod` 不会覆盖现有账号。

### SQLite 数据库文件在哪

默认数据库文件位于 `/projects/we-mp-rss/runtime/data/db.db`。只要保留 `runtime/data`，数据库就会持久化。

### 8001 端口无法访问

该方案故意只绑定 `127.0.0.1:8001`。公网应通过 Nginx 的 `80/443` 访问。

### 浏览器采集异常

默认使用 `webkit`。如果运行环境缺少浏览器依赖，先检查基础镜像是否可正常构建，再查看应用日志。
