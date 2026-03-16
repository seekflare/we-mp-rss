# 将域名从 gpt6.best 切换到 we-rss.xyz

本文档适用于已经在 Ubuntu 云服务器上部署好 `we-mp-rss`，当前使用旧域名 `gpt6.best`，现在要切换到新域名 `we-rss.xyz` 的场景。

如果你后续想从已绑定域名回退到公网 IP 访问，请改看 `docs/domain-to-ip-access.md`。

默认假设：

- 项目路径为 `/projects/we-mp-rss`
- 使用 Docker Compose 部署
- 使用 Nginx 反向代理
- 使用 Certbot 签发 HTTPS 证书
- 只切换根域名 `we-rss.xyz`

如果你还需要 `www.we-rss.xyz`，请在 DNS 和 Certbot 步骤中一起处理。

## 切换前说明

- 不需要迁移数据库，保留 `/projects/we-mp-rss/runtime/data` 即可
- 这次切换的关键点只有三个：
  - `deploy/.env.prod` 里的 `DOMAIN`
  - Nginx 的 `server_name`
  - `we-rss.xyz` 的 HTTPS 证书
- 项目启动时会根据 `RSS_SCHEME` 和 `DOMAIN` 自动生成 `RSS_BASE_URL=${RSS_SCHEME}://${DOMAIN}/`
- 域名模式下建议显式设置 `RSS_SCHEME=https`

## 步骤 1：确认 DNS 已解析到当前服务器

先在域名服务商后台为 `we-rss.xyz` 添加 A 记录，指向当前云服务器公网 IP。

在服务器上执行：

```bash
curl ifconfig.me
getent hosts we-rss.xyz
```

预期结果：

- `curl ifconfig.me` 返回服务器公网 IP
- `getent hosts we-rss.xyz` 返回的 IP 与公网 IP 一致

如果还不一致，先不要继续申请证书。

## 步骤 2：备份现有配置

```bash
cp /projects/we-mp-rss/deploy/.env.prod /projects/we-mp-rss/deploy/.env.prod.bak.$(date +%F-%H%M%S)
sudo cp /etc/nginx/sites-available/we-mp-rss.conf /etc/nginx/sites-available/we-mp-rss.conf.bak.$(date +%F-%H%M%S)
```

如果旧的 Nginx 配置文件还不存在，可以忽略第二条命令报错，或者先执行：

```bash
ls -l /etc/nginx/sites-available/we-mp-rss.conf
```

## 步骤 3：切换项目部署域名

修改 `deploy/.env.prod` 中的 `DOMAIN`，并确认 `RSS_SCHEME=https`：

```bash
sed -i 's/^DOMAIN=.*/DOMAIN=we-rss.xyz/' /projects/we-mp-rss/deploy/.env.prod
if grep -q '^RSS_SCHEME=' /projects/we-mp-rss/deploy/.env.prod; then
  sed -i 's/^RSS_SCHEME=.*/RSS_SCHEME=https/' /projects/we-mp-rss/deploy/.env.prod
else
  printf '\nRSS_SCHEME=https\n' >> /projects/we-mp-rss/deploy/.env.prod
fi
grep '^DOMAIN=' /projects/we-mp-rss/deploy/.env.prod
grep '^RSS_SCHEME=' /projects/we-mp-rss/deploy/.env.prod
```

预期输出：

```bash
DOMAIN=we-rss.xyz
RSS_SCHEME=https
```

## 步骤 4：重建或重启应用容器

如果你只想让新环境变量生效，执行：

```bash
cd /projects/we-mp-rss/deploy
sudo docker compose --env-file .env.prod -f docker-compose.prod.yml up -d --force-recreate app
sudo docker compose --env-file .env.prod -f docker-compose.prod.yml ps
```

如果你想按项目标准流程重新构建部署，执行：

```bash
cd /projects/we-mp-rss
chmod +x deploy/*.sh
./deploy/deploy.sh
```

两种方式任选一种即可。

## 步骤 5：重置并更新 Nginx 站点配置

建议不要直接手改旧的 Certbot 自动生成配置，而是先用仓库模板覆盖，再重新签发新证书。

执行：

```bash
sudo cp /projects/we-mp-rss/deploy/nginx.we-mp-rss.conf /etc/nginx/sites-available/we-mp-rss.conf
sudo sed -i 's/server_name rss.example.com;/server_name we-rss.xyz;/' /etc/nginx/sites-available/we-mp-rss.conf
sudo ln -sf /etc/nginx/sites-available/we-mp-rss.conf /etc/nginx/sites-enabled/we-mp-rss.conf
sudo nginx -t
sudo systemctl enable --now nginx
sudo systemctl reload nginx
```

如果 `sudo nginx -t` 报错，先修复配置再继续。

## 步骤 6：为新域名签发 HTTPS 证书

只绑定根域名时：

```bash
sudo certbot --nginx -d we-rss.xyz
```

如果还需要 `www.we-rss.xyz`：

```bash
sudo certbot --nginx -d we-rss.xyz -d www.we-rss.xyz
```

Certbot 询问是否将 HTTP 自动跳转到 HTTPS 时，建议选择重定向。

## 步骤 7：验证新域名是否已生效

```bash
curl -I http://we-rss.xyz
curl -I https://we-rss.xyz
curl https://we-rss.xyz/api/openapi.json
cd /projects/we-mp-rss/deploy
sudo docker compose --env-file .env.prod -f docker-compose.prod.yml logs --tail=100 app
```

预期结果：

- `http://we-rss.xyz` 返回 `301` 或 `308` 跳转到 `https://we-rss.xyz`
- `https://we-rss.xyz` 返回 `200`
- `https://we-rss.xyz/api/openapi.json` 能返回接口描述
- 应用日志没有明显启动异常

## 步骤 8：检查 RSS 绝对地址是否已经切换

项目内部会根据 `RSS_SCHEME` 和 `DOMAIN` 自动生成：

```bash
RSS_BASE_URL=https://we-rss.xyz/
```

你可以用以下方式确认：

```bash
cd /projects/we-mp-rss/deploy
sudo docker compose --env-file .env.prod -f docker-compose.prod.yml exec app env | grep RSS_BASE_URL
```

预期输出：

```bash
RSS_BASE_URL=https://we-rss.xyz
```

然后在浏览器打开页面，手动确认站内生成的 RSS 链接或导出链接已经变成 `https://we-rss.xyz/...`。

## 步骤 9：处理旧域名 gpt6.best

确认新域名完全正常之后，再处理旧域名。

### 方案 A：旧域名直接停用

删除 `gpt6.best` 的 DNS 解析，必要时清理旧证书：

```bash
sudo certbot certificates
sudo certbot delete --cert-name gpt6.best
```

### 方案 B：旧域名 301 跳转到新域名

如果你希望访问 `gpt6.best` 的请求自动跳到 `we-rss.xyz`，新建一个独立 Nginx 站点：

```bash
sudo tee /etc/nginx/sites-available/gpt6.best-redirect.conf >/dev/null <<'EOF'
server {
  listen 80;
  server_name gpt6.best www.gpt6.best;

  location / {
    return 301 https://we-rss.xyz$request_uri;
  }
}
EOF
sudo ln -sf /etc/nginx/sites-available/gpt6.best-redirect.conf /etc/nginx/sites-enabled/gpt6.best-redirect.conf
sudo nginx -t
sudo systemctl reload nginx
sudo certbot --nginx -d gpt6.best -d www.gpt6.best
```

如果旧域名已经没有 DNS 解析，就不要做这个跳转方案。

## 常见问题

### 1. Certbot 申请证书失败

优先检查：

- `we-rss.xyz` 是否已经解析到当前服务器
- 云安全组和本机防火墙是否放行 `80/443`
- Nginx 是否已成功启动

排查命令：

```bash
sudo systemctl status nginx --no-pager
sudo nginx -t
ss -lntp | grep -E ':80|:443'
```

### 2. 页面能打开，但 RSS 链接还是旧域名

通常是因为只改了 Nginx，没有改 `deploy/.env.prod` 的 `DOMAIN` / `RSS_SCHEME`。

重新执行：

```bash
sed -i 's/^DOMAIN=.*/DOMAIN=we-rss.xyz/' /projects/we-mp-rss/deploy/.env.prod
if grep -q '^RSS_SCHEME=' /projects/we-mp-rss/deploy/.env.prod; then
  sed -i 's/^RSS_SCHEME=.*/RSS_SCHEME=https/' /projects/we-mp-rss/deploy/.env.prod
else
  printf '\nRSS_SCHEME=https\n' >> /projects/we-mp-rss/deploy/.env.prod
fi
cd /projects/we-mp-rss/deploy
sudo docker compose --env-file .env.prod -f docker-compose.prod.yml up -d --force-recreate app
```

### 3. 容器启动失败

查看日志：

```bash
cd /projects/we-mp-rss/deploy
sudo docker compose --env-file .env.prod -f docker-compose.prod.yml logs -f app
```

### 4. 想快速回滚到旧域名

可以把备份文件恢复回去：

```bash
cp /projects/we-mp-rss/deploy/.env.prod.bak.YYYY-MM-DD-HHMMSS /projects/we-mp-rss/deploy/.env.prod
sudo cp /etc/nginx/sites-available/we-mp-rss.conf.bak.YYYY-MM-DD-HHMMSS /etc/nginx/sites-available/we-mp-rss.conf
cd /projects/we-mp-rss/deploy
sudo docker compose --env-file .env.prod -f docker-compose.prod.yml up -d --force-recreate app
sudo nginx -t
sudo systemctl reload nginx
```

将文件名中的时间戳替换成你实际备份时生成的值。
