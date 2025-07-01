#!/bin/bash

set -e

echo "[1/7] 获取公网 IP..."
PUBLIC_IP=$(curl -s https://api.ipify.org)
if [[ -z "$PUBLIC_IP" ]]; then
    echo "❌ 获取公网 IP 失败。"
    exit 1
fi
echo "🌐 公网 IP 为: $PUBLIC_IP"

echo "[2/7] 安装 NGINX..."
sudo apt update
sudo apt install -y nginx

echo "[3/7] 备份默认配置..."
sudo cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak

echo "[4/7] 写入自定义 nginx 配置..."
sudo tee /etc/nginx/nginx.conf > /dev/null <<EOF
worker_processes 4;

error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;

events {
    worker_connections 512;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    server_tokens off;
    client_body_timeout 12;
    client_header_timeout 12;

    keepalive_timeout 65;
    keepalive_requests 512;

    resolver 8.8.8.8 8.8.4.4 valid=300s ipv6=off;
    resolver_timeout 5s;

    server {
        listen 8000;
        sub_filter_types *;
        sub_filter_once off;

        location ^~ /streams/ {
            proxy_pass https://hls-gateway.vpstv.net/streams/;
            proxy_set_header Accept-Encoding "";
            proxy_set_header Host hls-gateway.vpstv.net;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_http_version 1.1;
            proxy_set_header Connection "";
            proxy_next_upstream_timeout 5s;
            proxy_socket_keepalive on;
            proxy_cache off;
            proxy_set_header Range $http_range;
            proxy_set_header If-Range $http_if_range;
            proxy_ssl_server_name on;
            proxy_ssl_protocols TLSv1.2 TLSv1.3;
            proxy_ssl_verify off;
            proxy_connect_timeout 30s;
            proxy_read_timeout 30s;
            proxy_send_timeout 30s;

            sub_filter "https://cs8.vpstv.net" "http://$PUBLIC_IP:8000";
            sub_filter "https://cs4.vpstv.net/key" "http://$PUBLIC_IP:8000/key4";
            sub_filter "https://cs4.vpstv.net/hls" "http://$PUBLIC_IP:8000/hls4";
            sub_filter "https://cs1.vpstv.net" "http://$PUBLIC_IP:8000";
            sub_filter "https://cs2.vpstv.net" "http://$PUBLIC_IP:8000";
            sub_filter "https://cs3.vpstv.net" "http://$PUBLIC_IP:8000";
            sub_filter "https://cs5.vpstv.net" "http://$PUBLIC_IP:8000";
            sub_filter "https://cs6.vpstv.net" "http://$PUBLIC_IP:8000";
            sub_filter "https://cs7.vpstv.net" "http://$PUBLIC_IP:8000";
            sub_filter "https://cs9.vpstv.net" "http://$PUBLIC_IP:8000";
            sub_filter "https://cs10.vpstv.net" "http://$PUBLIC_IP:8000";
        }

        location ^~ /key/ {
            proxy_pass https://cs8.vpstv.net/key/;
            proxy_set_header Host cs8.vpstv.net;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_http_version 1.1;
            proxy_set_header Connection "";
            proxy_cache off;
            proxy_buffering off;
            proxy_ssl_server_name on;
            proxy_ssl_protocols TLSv1.2 TLSv1.3;
            proxy_ssl_verify off;
            proxy_connect_timeout 30s;
            proxy_read_timeout 30s;
            proxy_send_timeout 30s;
        }

        location ^~ /key4/ {
            proxy_pass https://cs4.vpstv.net/key/;
            proxy_set_header Host cs4.vpstv.net;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_http_version 1.1;
            proxy_set_header Connection "";
            proxy_cache off;
            proxy_buffering off;
            proxy_ssl_server_name on;
            proxy_ssl_protocols TLSv1.2 TLSv1.3;
            proxy_ssl_verify off;
            proxy_connect_timeout 30s;
            proxy_read_timeout 30s;
            proxy_send_timeout 30s;
        }

        location ^~ /hls/ {
            proxy_pass https://cs8.vpstv.net/hls/;
            proxy_set_header Host cs8.vpstv.net;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_http_version 1.1;
            proxy_set_header Connection "";
            proxy_cache off;
            proxy_buffering off;
            proxy_ssl_server_name on;
            proxy_ssl_protocols TLSv1.2 TLSv1.3;
            proxy_ssl_verify off;
            proxy_connect_timeout 30s;
            proxy_read_timeout 30s;
            proxy_send_timeout 30s;
        }

        location ^~ /hls4/ {
            proxy_pass https://cs4.vpstv.net/hls/;
            proxy_set_header Host cs4.vpstv.net;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_http_version 1.1;
            proxy_set_header Connection "";
            proxy_cache off;
            proxy_buffering off;
            proxy_ssl_server_name on;
            proxy_ssl_protocols TLSv1.2 TLSv1.3;
            proxy_ssl_verify off;
            proxy_connect_timeout 30s;
            proxy_read_timeout 30s;
            proxy_send_timeout 30s;
        }
    }
}
EOF

echo "[5/7] 测试 nginx 配置..."
sudo nginx -t

echo "[6/7] 重启 nginx 服务..."
sudo systemctl restart nginx
sudo systemctl enable nginx

echo "[7/7] 开放 8000 端口（如适用）..."
if command -v ufw &> /dev/null; then
    sudo ufw allow 8000
    sudo ufw reload
fi

echo "✅ NGINX 部署完成！现在你可以通过 http://$PUBLIC_IP:8000 访问直播转发服务"
