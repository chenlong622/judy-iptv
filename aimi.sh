#!/bin/bash

set -e

echo "请选择操作："
echo "1) 使用公网IP，监听8070端口 (HTTP)"
echo "2) 使用自定义域名，监听80/443端口 (HTTPS)"
echo "3) 卸载所有安装内容"
read -p "请输入数字(1、2或3): " mode

if [[ "$mode" != "1" && "$mode" != "2" && "$mode" != "3" ]]; then
    echo "输入错误，退出"
    exit 1
fi

# 卸载功能
if [ "$mode" == "3" ]; then
    echo "开始卸载..."
    
    # 删除Nginx配置
    rm -f /etc/nginx/sites-available/stream_proxy
    rm -f /etc/nginx/sites-enabled/stream_proxy
    
    # 恢复默认配置
    if [ -f /etc/nginx/sites-available/default ]; then
        ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
    fi
    
    # 删除SSL证书目录
    rm -rf /etc/nginx/ssl/
    
    # 关闭防火墙规则
    if command -v ufw &> /dev/null; then
        ufw delete allow 8070/tcp 2>/dev/null || true
        ufw delete allow 80/tcp 2>/dev/null || true
        ufw delete allow 443/tcp 2>/dev/null || true
    fi
    
    # 重启Nginx
    systemctl restart nginx || true
    
    echo "=========================="
    echo "卸载完成！"
    echo "已删除Nginx配置和相关防火墙规则"
    echo "=========================="
    exit 0
fi

apt update
apt install -y nginx curl

conf_path="/etc/nginx/sites-available/stream_proxy"

if [ "$mode" == "2" ]; then
    read -p "请输入你的自定义域名(如: proxy.xxx.com): " mydomain
    if [ -z "$mydomain" ]; then
        echo "域名不能为空，退出"
        exit 1
    fi
    cert_dir="/etc/nginx/ssl/$mydomain"
    mkdir -p $cert_dir
    apt install -y socat
    curl https://get.acme.sh | sh
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    ~/.acme.sh/acme.sh --issue -d $mydomain --webroot /var/www/html
    ~/.acme.sh/acme.sh --install-cert -d $mydomain \
      --key-file $cert_dir/$mydomain.key \
      --fullchain-file $cert_dir/fullchain.cer
    ssl_config="ssl_certificate $cert_dir/fullchain.cer;
    ssl_certificate_key $cert_dir/$mydomain.key;"
fi

# 使用变量替换方法，避免在heredoc中使用转义符
cat > $conf_path << 'EOFNGINX'
server {
EOFNGINX

if [ "$mode" == "1" ]; then
    echo "    listen 8070;" >> $conf_path
    echo "    server_name _;" >> $conf_path
else
    echo "    listen 80;" >> $conf_path
    echo "    server_name $mydomain;" >> $conf_path
fi

echo "    resolver 8.8.8.8 1.1.1.1 valid=10s;" >> $conf_path

if [ "$mode" == "2" ]; then
    cat >> $conf_path << 'EOF2'
    location ^~ /.well-known/acme-challenge/ {
        root /var/www/html;
    }
    location / {
        return 301 https://$host$request_uri;
    }
EOF2
else
    cat >> $conf_path << 'EOF3'
    # m3u8 自动 sub_filter
    location ~ \.m3u8$ {
        proxy_pass https://hls-gateway.vpstv.net;
        proxy_set_header Host hls-gateway.vpstv.net;
        proxy_ssl_server_name on;
        proxy_ssl_name hls-gateway.vpstv.net;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_buffering off;
        sub_filter_once off;
        sub_filter_types application/vnd.apple.mpegurl text/plain;
        sub_filter "https://cs1.vpstv.net/" "/cs1.vpstv.net/";
        sub_filter "https://cs2.vpstv.net/" "/cs2.vpstv.net/";
        sub_filter "https://cs3.vpstv.net/" "/cs3.vpstv.net/";
        sub_filter "https://cs4.vpstv.net/" "/cs4.vpstv.net/";
        sub_filter "https://cs5.vpstv.net/" "/cs5.vpstv.net/";
        sub_filter "https://cs6.vpstv.net/" "/cs6.vpstv.net/";
        sub_filter "https://cs7.vpstv.net/" "/cs7.vpstv.net/";
        sub_filter "https://cs8.vpstv.net/" "/cs8.vpstv.net/";
        sub_filter "https://cs9.vpstv.net/" "/cs9.vpstv.net/";
        sub_filter "https://cs10.vpstv.net/" "/cs10.vpstv.net/";
    }
    # ts/key 动态反代，支持 cs1~cs10
    location ~ ^/(cs(10|[1-9])\.vpstv\.net)/(.*) {
        set $upstream $1;
        proxy_pass https://$upstream/$3;
        proxy_set_header Host $upstream;
        proxy_ssl_server_name on;
        proxy_ssl_name $upstream;
        proxy_ssl_verify off;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_buffering off;
    }
    # 兜底：主域名其他资源
    location / {
        proxy_pass https://hls-gateway.vpstv.net;
        proxy_set_header Host hls-gateway.vpstv.net;
        proxy_ssl_server_name on;
        proxy_ssl_name hls-gateway.vpstv.net;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_buffering off;
    }
EOF3
fi

echo "}" >> $conf_path

# HTTPS 服务器配置
if [ "$mode" == "2" ]; then
    cat >> $conf_path << 'HTTPSSERVER'
server {
    listen 443 ssl http2;
HTTPSSERVER

    echo "    server_name $mydomain;" >> $conf_path
    echo "    resolver 8.8.8.8 1.1.1.1 valid=10s;" >> $conf_path
    echo "    $ssl_config" >> $conf_path

    cat >> $conf_path << 'HTTPSCONFIG'
    # m3u8 自动 sub_filter
    location ~ \.m3u8$ {
        proxy_pass https://hls-gateway.vpstv.net;
        proxy_set_header Host hls-gateway.vpstv.net;
        proxy_ssl_server_name on;
        proxy_ssl_name hls-gateway.vpstv.net;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_buffering off;
        sub_filter_once off;
        sub_filter_types application/vnd.apple.mpegurl text/plain;
        sub_filter "https://cs1.vpstv.net/" "/cs1.vpstv.net/";
        sub_filter "https://cs2.vpstv.net/" "/cs2.vpstv.net/";
        sub_filter "https://cs3.vpstv.net/" "/cs3.vpstv.net/";
        sub_filter "https://cs4.vpstv.net/" "/cs4.vpstv.net/";
        sub_filter "https://cs5.vpstv.net/" "/cs5.vpstv.net/";
        sub_filter "https://cs6.vpstv.net/" "/cs6.vpstv.net/";
        sub_filter "https://cs7.vpstv.net/" "/cs7.vpstv.net/";
        sub_filter "https://cs8.vpstv.net/" "/cs8.vpstv.net/";
        sub_filter "https://cs9.vpstv.net/" "/cs9.vpstv.net/";
        sub_filter "https://cs10.vpstv.net/" "/cs10.vpstv.net/";
    }
    # ts/key 动态反代，支持 cs1~cs10
    location ~ ^/(cs(10|[1-9])\.vpstv\.net)/(.*) {
        set $upstream $1;
        proxy_pass https://$upstream/$3;
        proxy_set_header Host $upstream;
        proxy_ssl_server_name on;
        proxy_ssl_name $upstream;
        proxy_ssl_verify off;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_buffering off;
    }
    # 兜底：主域名其他资源
    location / {
        proxy_pass https://hls-gateway.vpstv.net;
        proxy_set_header Host hls-gateway.vpstv.net;
        proxy_ssl_server_name on;
        proxy_ssl_name hls-gateway.vpstv.net;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_buffering off;
    }
}
HTTPSCONFIG
fi

ln -sf $conf_path /etc/nginx/sites-enabled/stream_proxy
rm -f /etc/nginx/sites-enabled/default

# 添加防火墙规则(如果有UFW)
if command -v ufw &> /dev/null; then
    if [ "$mode" == "1" ]; then
        ufw allow 8070/tcp
    else
        ufw allow 80/tcp
        ufw allow 443/tcp
    fi
fi

nginx -t && systemctl restart nginx

IP=$(curl -s ifconfig.me || curl -s ipinfo.io/ip)

echo "=========================="
if [ "$mode" == "1" ]; then
    echo "HTTP 部署完成！"
    echo "主入口：http://$IP:8070/"
else
    echo "HTTPS 部署完成！"
fi
echo "交流群:https://t.me/IPTV_9999999 "
echo "作者： ！㋡ 三岁抬頭當王者🎖ᴴᴰ "
echo "=========================="