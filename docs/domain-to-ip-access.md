# 从域名访问回退到 IP 访问

本文档适用于已经在 Ubuntu 云服务器上部署好 `we-mp-rss`，并且已经按域名模式配置过 Nginx、Certbot、甚至旧域名跳转，现在要回退成公网 IP 访问的场景。

默认假设：

- 项目路径为 `/projects/we-mp-rss`
- 使用 Docker Compose 部署
- 使用 Nginx 反向代理
- 应用容器仍监听 `127.0.0.1:8001`
- 你只想保留 `http://<public-ip>/` 访问

如果你只是新装并直接使用 IP 访问，请看 `docs/ubuntu-deploy.md` 中的 IP 模式。

## 回退前说明

- 不需要迁移数据库，保留 `/projects/we-mp-rss/runtime/data` 即可
- 这次回退的关键点有四个：
  - `deploy/.env.prod` 里的 `DOMAIN`
  - `deploy/.env.prod` 里的 `RSS_SCHEME`
  - Nginx 站点配置
  - 旧域名跳转、`443` 和证书残留
- 项目当前会根据 `RSS_SCHEME` 和 `DOMAIN` 自动生成：

```bash
RSS_BASE_URL=${RSS_SCHEME}://${DOMAIN}/
```

回退到 IP 模式时，目标结果应为：

```bash
DOMAIN=<你的公网IP>
RSS_SCHEME=http
RSS_BASE_URL=http://<你的公网IP>/
```

## 步骤 1：盘点当前服务器状态

先确认当前公网 IP，以及服务器上是否还保留域名和证书配置：

```bash
PUBLIC_IP="$(curl -4 ifconfig.me)"
echo "$PUBLIC_IP"

grep '^DOMAIN=' /projects/we-mp-rss/deploy/.env.prod
grep '^RSS_SCHEME=' /projects/we-mp-rss/deploy/.env.prod

sudo nginx -T | grep -nE 'server_name|listen 443|ssl_certificate|return 301 https|we-rss.xyz|gpt6.best'
sudo ls -l /etc/nginx/sites-enabled
sudo certbot certificates
```

重点关注：

- `.env.prod` 是否还是 `DOMAIN=we-rss.xyz`
- `.env.prod` 是否缺少 `RSS_SCHEME`
- Nginx 是否还保留 `listen 443 ssl`
- 是否还启用了旧域名跳转站点，例如 `gpt6.best-redirect.conf`

## 步骤 2：备份现有配置

```bash
cp /projects/we-mp-rss/deploy/.env.prod /projects/we-mp-rss/deploy/.env.prod.bak.$(date +%F-%H%M%S)
cp /projects/we-mp-rss/deploy/docker-compose.prod.yml /projects/we-mp-rss/deploy/docker-compose.prod.yml.bak.$(date +%F-%H%M%S)
sudo cp /etc/nginx/sites-available/we-mp-rss.conf /etc/nginx/sites-available/we-mp-rss.conf.bak.$(date +%F-%H%M%S)
```

如果当前站点文件不是 `we-mp-rss.conf`，请改成你的实际文件名。

## 步骤 3：切换应用对外地址

把 `DOMAIN` 改成公网 IP，把 `RSS_SCHEME` 改成 `http`：

```bash
PUBLIC_IP="$(curl -4 ifconfig.me)"
sed -i "s/^DOMAIN=.*/DOMAIN=${PUBLIC_IP}/" /projects/we-mp-rss/deploy/.env.prod

if grep -q '^RSS_SCHEME=' /projects/we-mp-rss/deploy/.env.prod; then
  sed -i 's/^RSS_SCHEME=.*/RSS_SCHEME=http/' /projects/we-mp-rss/deploy/.env.prod
else
  printf '\nRSS_SCHEME=http\n' >> /projects/we-mp-rss/deploy/.env.prod
fi

grep -E '^(DOMAIN|RSS_SCHEME)=' /projects/we-mp-rss/deploy/.env.prod
```

预期输出：

```bash
DOMAIN=<你的公网IP>
RSS_SCHEME=http
```

## 步骤 4：重建或重启应用容器

只想让环境变量立即生效时：

```bash
cd /projects/we-mp-rss/deploy
sudo docker compose --env-file .env.prod -f docker-compose.prod.yml up -d --force-recreate app
sudo docker compose --env-file .env.prod -f docker-compose.prod.yml ps
sudo docker compose --env-file .env.prod -f docker-compose.prod.yml exec app env | grep RSS_BASE_URL
```

如果你想按项目标准流程重新构建部署：

```bash
cd /projects/we-mp-rss
chmod +x deploy/*.sh
./deploy/deploy.sh
```

预期 `RSS_BASE_URL` 为：

```bash
RSS_BASE_URL=http://<你的公网IP>/
```

## 步骤 5：用 IP 专用模板覆盖 Nginx

如果你之前按域名方案跑过 Certbot，原来的站点文件通常已经混入了 `443`、证书路径和 `http -> https` 跳转。不要直接在旧文件上做小修小补，直接覆盖为 IP 模板更稳妥。

执行：

```bash
sudo cp /projects/we-mp-rss/deploy/nginx.we-mp-rss.ip.conf /etc/nginx/sites-available/we-mp-rss.conf
sudo ln -sf /etc/nginx/sites-available/we-mp-rss.conf /etc/nginx/sites-enabled/we-mp-rss.conf
sudo rm -f /etc/nginx/sites-enabled/default
sudo rm -f /etc/nginx/sites-enabled/gpt6.best-redirect.conf
sudo rm -f /etc/nginx/sites-enabled/we-rss.xyz-redirect.conf
sudo nginx -t
sudo systemctl enable --now nginx
sudo systemctl reload nginx
```

如果旧跳转站点文件名不是上面这两个，请按 `ls /etc/nginx/sites-enabled` 实际文件名删除对应软链。

## 步骤 6：验证 IP 访问是否已生效

```bash
PUBLIC_IP="$(curl -4 ifconfig.me)"

curl http://127.0.0.1:8001/api/openapi.json
curl -I "http://${PUBLIC_IP}/"
curl "http://${PUBLIC_IP}/api/openapi.json"
curl "http://${PUBLIC_IP}/rss"

ss -lntp | grep -E ':80|:443|:8001'
sudo nginx -T | grep -nE 'server_name|listen 443|ssl_certificate|return 301 https|we-rss.xyz|gpt6.best'
```

预期结果：

- `http://127.0.0.1:8001/api/openapi.json` 可返回接口描述
- `http://<public-ip>/` 返回 `200`
- `http://<public-ip>/api/openapi.json` 可返回接口描述
- `http://<public-ip>/rss` 返回 XML
- `8001` 只监听 `127.0.0.1:8001`
- Nginx 输出中不再有 `listen 443 ssl`
- 不再有 `return 301 https://...`

## 步骤 7：可选清理旧域名和证书

如果你已经确定不再通过这些域名访问这个服务，可以继续清理。

### 1. 删除证书

```bash
sudo certbot certificates
sudo certbot delete --cert-name we-rss.xyz
sudo certbot delete --cert-name gpt6.best
```

只删除明确属于这个服务的证书。如果某张证书还被别的站点使用，不要删。

### 2. 删除 DNS 解析

在域名服务商控制台删除或停用：

- `we-rss.xyz`
- `www.we-rss.xyz`
- `gpt6.best`
- `www.gpt6.best`

如果你只是暂时不想让它作为主入口，也可以先保留 DNS，不影响 IP 访问。

### 3. 收紧安全组

IP 模式建议只开放：

- `22`
- `80`

可以关闭：

- `443`
- `8001`

## 常见问题

### 1. 首页能打开，但 RSS 或 OPML 里的链接还是旧域名

通常是因为只换了 Nginx，没有重建应用容器，或者 `.env.prod` 里的 `DOMAIN` / `RSS_SCHEME` 没改全。

重新检查：

```bash
grep -E '^(DOMAIN|RSS_SCHEME)=' /projects/we-mp-rss/deploy/.env.prod
cd /projects/we-mp-rss/deploy
sudo docker compose --env-file .env.prod -f docker-compose.prod.yml exec app env | grep RSS_BASE_URL
```

### 2. `http://127.0.0.1:8001` 正常，但公网 IP 打不开

优先检查：

- 云安全组是否放行 `80`
- 本机防火墙是否放行 `80`
- Nginx 是否成功加载了 IP 模板

排查命令：

```bash
sudo systemctl status nginx --no-pager
sudo nginx -t
ss -lntp | grep ':80'
```

### 3. 浏览器总是跳到 `https://`

说明服务器上还残留了旧的 `443` 站点或跳转配置。

排查：

```bash
sudo nginx -T | grep -nE 'return 301 https|listen 443|ssl_certificate'
sudo ls -l /etc/nginx/sites-enabled
```

### 4. 想快速回滚到域名模式

把备份文件恢复回去即可：

```bash
cp /projects/we-mp-rss/deploy/.env.prod.bak.YYYY-MM-DD-HHMMSS /projects/we-mp-rss/deploy/.env.prod
sudo cp /etc/nginx/sites-available/we-mp-rss.conf.bak.YYYY-MM-DD-HHMMSS /etc/nginx/sites-available/we-mp-rss.conf
cd /projects/we-mp-rss/deploy
sudo docker compose --env-file .env.prod -f docker-compose.prod.yml up -d --force-recreate app
sudo nginx -t
sudo systemctl reload nginx
```

将文件名中的时间戳替换成你实际备份时生成的值。
