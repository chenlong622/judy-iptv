#!/bin/bash

set -e

# ===== 用户输入域名 =====
read -p "请输入你的域名（例如：stream.example.com）: " DOMAIN
if [[ -z "$DOMAIN" ]]; then
    echo "❌ 域名不能为空"
    exit 1
fi

# ===== 公网 IP 检查 =====
PUBLIC_IP=$(curl -s https://api.ipify.org)
echo "🌐 当前公网 IP: $PUBLIC_IP"
echo "⚠️ 请确保你的域名 [$DOMAIN] 已正确解析到此 IP"

read -p "是否继续部署？[y/n]: " CONFIRM
if [[ "$CONFIRM" != "y" ]]; then
    echo "❌ 用户取消操作。"
    exit 0
fi

# ===== 安装 NGINX 和 Certbot =====
echo "[1/6] 安装 NGINX 和 Certbot..."
sudo apt update
sudo apt install -y nginx python3-certbot-nginx

# ===== 配置 NGINX HTTP 站点用于申请证书 =====
echo "[2/6] 创建临时 HTTP 配置..."
sudo tee /etc/nginx/sites-available/$DOMAIN > /dev/null <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        return 301 https://\$host\$request_uri;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/$DOMAIN
sudo nginx -t && sudo systemctl reload nginx

# ===== 使用 Certbot 自动申请并配置 HTTPS =====
echo "[3/6] 使用 Certbot 申请 Let’s Encrypt 证书..."
sudo certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m admin@$DOMAIN || {
    echo "❌ 证书申请失败"
    exit 1
}

# ===== 生成 NGINX 配置（启用代理和替换）=====
echo "[4/6] 写入 HTTPS 配置..."
sudo tee /etc/nginx/sites-available/$DOMAIN > /dev/null <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;

    sub_filter_types *;
    sub_filter_once off;

    location ^~ /streams/ {
        proxy_pass https://hls-gateway.vpstv.net/streams/;
        proxy_set_header Accept-Encoding "";
        proxy_set_header Host hls-gateway.vpstv.net;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_cache off;

        proxy_ssl_server_name on;
        proxy_ssl_protocols TLSv1.2 TLSv1.3;
        proxy_ssl_verify off;

        sub_filter "https://cs8.vpstv.net" "https://$DOMAIN";
        sub_filter "https://cs4.vpstv.net/key" "https://$DOMAIN/key4";
        sub_filter "https://cs4.vpstv.net/hls" "https://$DOMAIN/hls4";
    }

    location ^~ /key/ {
        proxy_pass https://cs8.vpstv.net/key/;
        proxy_set_header Host cs8.vpstv.net;
    }

    location ^~ /key4/ {
        proxy_pass https://cs4.vpstv.net/key/;
        proxy_set_header Host cs4.vpstv.net;
    }

    location ^~ /hls/ {
        proxy_pass https://cs8.vpstv.net/hls/;
        proxy_set_header Host cs8.vpstv.net;
    }

    location ^~ /hls4/ {
        proxy_pass https://cs4.vpstv.net/hls/;
        proxy_set_header Host cs4.vpstv.net;
    }
}
EOF

# ===== 启用并重启 NGINX =====
echo "[5/6] 启用站点并重启 NGINX..."
sudo ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/$DOMAIN
sudo nginx -t && sudo systemctl reload nginx

# ===== 自动续期测试 =====
echo "[6/6] 测试证书续期..."
sudo certbot renew --dry-run

echo "✅ 部署完成！你现在可以通过 https://$DOMAIN 访问服务。"
