#!/bin/bash

set -e

echo "============================"
echo "🌐 请选择部署方式："
echo "1) 使用公网IP，监听8070端口 (HTTP)"
echo "2) 使用自定义域名，监听80/443端口 (HTTPS)"
echo "============================"
read -p "请输入选项 [1 或 2]: " MODE

if [[ "$MODE" == "1" ]]; then
    echo "[模式1] 使用公网IP + 8070端口"

    PUBLIC_IP=$(curl -s https://api.ipify.org)
    if [[ -z "$PUBLIC_IP" ]]; then
        echo "❌ 获取公网IP失败。"
        exit 1
    fi
    echo "✅ 获取到公网IP: $PUBLIC_IP"

    # 安装 nginx
    sudo apt update
    sudo apt install -y nginx

    # 配置nginx
    NGINX_CONF="/etc/nginx/sites-available/aimi-ip8070"
    sudo tee $NGINX_CONF > /dev/null <<EOF
server {
    listen 8070;
    server_name $PUBLIC_IP;
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

        sub_filter "https://cs8.vpstv.net" "http://$PUBLIC_IP:8070";
        sub_filter "https://cs4.vpstv.net/key" "http://$PUBLIC_IP:8070/key4";
        sub_filter "https://cs4.vpstv.net/hls" "http://$PUBLIC_IP:8070/hls4";
        sub_filter "https://cs1.vpstv.net" "http://$PUBLIC_IP:8070";
        sub_filter "https://cs2.vpstv.net" "http://$PUBLIC_IP:8070";
        sub_filter "https://cs3.vpstv.net" "http://$PUBLIC_IP:8070";
        sub_filter "https://cs5.vpstv.net" "http://$PUBLIC_IP:8070";
        sub_filter "https://cs6.vpstv.net" "http://$PUBLIC_IP:8070";
        sub_filter "https://cs7.vpstv.net" "http://$PUBLIC_IP:8070";
        sub_filter "https://cs9.vpstv.net" "http://$PUBLIC_IP:8070";
        sub_filter "https://cs10.vpstv.net" "http://$PUBLIC_IP:8070";
        sub_filter "https://cs1.vpstv.net/key" "http://$PUBLIC_IP:8070/key1";
        sub_filter "https://cs1.vpstv.net/hls" "http://$PUBLIC_IP:8070/hls1";
        sub_filter "https://cs2.vpstv.net/key" "http://$PUBLIC_IP:8070/key2";
        sub_filter "https://cs2.vpstv.net/hls" "http://$PUBLIC_IP:8070/hls2";
        sub_filter "https://cs3.vpstv.net/key" "http://$PUBLIC_IP:8070/key3";
        sub_filter "https://cs3.vpstv.net/hls" "http://$PUBLIC_IP:8070/hls3";
        sub_filter "https://cs4.vpstv.net/key" "http://$PUBLIC_IP:8070/key4";
        sub_filter "https://cs4.vpstv.net/hls" "http://$PUBLIC_IP:8070/hls4";
        sub_filter "https://cs5.vpstv.net/key" "http://$PUBLIC_IP:8070/key5";
        sub_filter "https://cs5.vpstv.net/hls" "http://$PUBLIC_IP:8070/hls5";
        sub_filter "https://cs6.vpstv.net/key" "http://$PUBLIC_IP:8070/key6";
        sub_filter "https://cs6.vpstv.net/hls" "http://$PUBLIC_IP:8070/hls6";
        sub_filter "https://cs7.vpstv.net/key" "http://$PUBLIC_IP:8070/key7";
        sub_filter "https://cs7.vpstv.net/hls" "http://$PUBLIC_IP:8070/hls7";
        # cs8是默认情况
        sub_filter "https://cs9.vpstv.net/key" "http://$PUBLIC_IP:8070/key9";
        sub_filter "https://cs9.vpstv.net/hls" "http://$PUBLIC_IP:8070/hls9";
        sub_filter "https://cs10.vpstv.net/key" "http://$PUBLIC_IP:8070/key10";
        sub_filter "https://cs10.vpstv.net/hls" "http://$PUBLIC_IP:8070/hls10";
    }
    # 替换原有的location块为完整的cs1到cs10配置
    location ^~ /key/ { proxy_pass https://cs8.vpstv.net/key/; }
    location ^~ /key1/ { proxy_pass https://cs1.vpstv.net/key/; }
    location ^~ /key2/ { proxy_pass https://cs2.vpstv.net/key/; }
    location ^~ /key3/ { proxy_pass https://cs3.vpstv.net/key/; }
    location ^~ /key4/ { proxy_pass https://cs4.vpstv.net/key/; }
    location ^~ /key5/ { proxy_pass https://cs5.vpstv.net/key/; }
    location ^~ /key6/ { proxy_pass https://cs6.vpstv.net/key/; }
    location ^~ /key7/ { proxy_pass https://cs7.vpstv.net/key/; }
    location ^~ /key9/ { proxy_pass https://cs9.vpstv.net/key/; }
    location ^~ /key10/ { proxy_pass https://cs10.vpstv.net/key/; }
    
    location ^~ /hls/ { proxy_pass https://cs8.vpstv.net/hls/; }
    location ^~ /hls1/ { proxy_pass https://cs1.vpstv.net/hls/; }
    location ^~ /hls2/ { proxy_pass https://cs2.vpstv.net/hls/; }
    location ^~ /hls3/ { proxy_pass https://cs3.vpstv.net/hls/; }
    location ^~ /hls4/ { proxy_pass https://cs4.vpstv.net/hls/; }
    location ^~ /hls5/ { proxy_pass https://cs5.vpstv.net/hls/; }
    location ^~ /hls6/ { proxy_pass https://cs6.vpstv.net/hls/; }
    location ^~ /hls7/ { proxy_pass https://cs7.vpstv.net/hls/; }
    location ^~ /hls9/ { proxy_pass https://cs9.vpstv.net/hls/; }
    location ^~ /hls10/ { proxy_pass https://cs10.vpstv.net/hls/; }
}
EOF

    sudo ln -sf $NGINX_CONF /etc/nginx/sites-enabled/aimi-ip8070
    sudo nginx -t
    sudo systemctl reload nginx

    if command -v ufw &> /dev/null; then
        sudo ufw allow 8070
        sudo ufw reload
    fi

    echo "✅ 部署完成！现在可通过 http://$PUBLIC_IP:8070 访问。"

elif [[ "$MODE" == "2" ]]; then
    echo "[模式2] 使用自定义域名 + 80/443端口"

    read -p "请输入你的域名（如 stream.example.com）: " DOMAIN

    if [[ -z "$DOMAIN" ]]; then
        echo "❌ 域名不能为空"
        exit 1
    fi

    PUBLIC_IP=$(curl -s https://api.ipify.org)
    echo "🌐 当前公网IP: $PUBLIC_IP"
    echo "⚠️ 请确保你的域名 [$DOMAIN] 已解析到此 IP"
    read -p "继续部署并自动申请HTTPS？[y/n]: " CONFIRM
    if [[ "$CONFIRM" != "y" ]]; then
        echo "❌ 用户取消操作。"
        exit 0
    fi

    sudo apt update
    sudo apt install -y nginx python3-certbot-nginx

    NGINX_CONF="/etc/nginx/sites-available/aimi-$DOMAIN"
    sudo tee $NGINX_CONF > /dev/null <<EOF
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
        sub_filter "https://cs1.vpstv.net" "https://$DOMAIN";
        sub_filter "https://cs2.vpstv.net" "https://$DOMAIN";
        sub_filter "https://cs3.vpstv.net" "https://$DOMAIN";
        sub_filter "https://cs5.vpstv.net" "https://$DOMAIN";
        sub_filter "https://cs6.vpstv.net" "https://$DOMAIN";
        sub_filter "https://cs7.vpstv.net" "https://$DOMAIN";
        sub_filter "https://cs9.vpstv.net" "https://$DOMAIN";
        sub_filter "https://cs10.vpstv.net" "https://$DOMAIN";
        # 为HTTPS模式添加同样的替换规则
        sub_filter "https://cs1.vpstv.net/key" "https://$DOMAIN/key1";
        sub_filter "https://cs1.vpstv.net/hls" "https://$DOMAIN/hls1";
        sub_filter "https://cs2.vpstv.net/key" "https://$DOMAIN/key2";
        sub_filter "https://cs2.vpstv.net/hls" "https://$DOMAIN/hls2";
        sub_filter "https://cs3.vpstv.net/key" "https://$DOMAIN/key3";
        sub_filter "https://cs3.vpstv.net/hls" "https://$DOMAIN/hls3";
        sub_filter "https://cs4.vpstv.net/key" "https://$DOMAIN/key4";
        sub_filter "https://cs4.vpstv.net/hls" "https://$DOMAIN/hls4";
        sub_filter "https://cs5.vpstv.net/key" "https://$DOMAIN/key5";
        sub_filter "https://cs5.vpstv.net/hls" "https://$DOMAIN/hls5";
        sub_filter "https://cs6.vpstv.net/key" "https://$DOMAIN/key6";
        sub_filter "https://cs6.vpstv.net/hls" "https://$DOMAIN/hls6";
        sub_filter "https://cs7.vpstv.net/key" "https://$DOMAIN/key7";
        sub_filter "https://cs7.vpstv.net/hls" "https://$DOMAIN/hls7";
        # cs8是默认情况
        sub_filter "https://cs9.vpstv.net/key" "https://$DOMAIN/key9";
        sub_filter "https://cs9.vpstv.net/hls" "https://$DOMAIN/hls9";
        sub_filter "https://cs10.vpstv.net/key" "https://$DOMAIN/key10";
        sub_filter "https://cs10.vpstv.net/hls" "https://$DOMAIN/hls10";
    }
    # 替换原有的location块为完整的cs1到cs10配置
    location ^~ /key/ { proxy_pass https://cs8.vpstv.net/key/; }
    location ^~ /key1/ { proxy_pass https://cs1.vpstv.net/key/; }
    location ^~ /key2/ { proxy_pass https://cs2.vpstv.net/key/; }
    location ^~ /key3/ { proxy_pass https://cs3.vpstv.net/key/; }
    location ^~ /key4/ { proxy_pass https://cs4.vpstv.net/key/; }
    location ^~ /key5/ { proxy_pass https://cs5.vpstv.net/key/; }
    location ^~ /key6/ { proxy_pass https://cs6.vpstv.net/key/; }
    location ^~ /key7/ { proxy_pass https://cs7.vpstv.net/key/; }
    location ^~ /key9/ { proxy_pass https://cs9.vpstv.net/key/; }
    location ^~ /key10/ { proxy_pass https://cs10.vpstv.net/key/; }
    
    location ^~ /hls/ { proxy_pass https://cs8.vpstv.net/hls/; }
    location ^~ /hls1/ { proxy_pass https://cs1.vpstv.net/hls/; }
    location ^~ /hls2/ { proxy_pass https://cs2.vpstv.net/hls/; }
    location ^~ /hls3/ { proxy_pass https://cs3.vpstv.net/hls/; }
    location ^~ /hls4/ { proxy_pass https://cs4.vpstv.net/hls/; }
    location ^~ /hls5/ { proxy_pass https://cs5.vpstv.net/hls/; }
    location ^~ /hls6/ { proxy_pass https://cs6.vpstv.net/hls/; }
    location ^~ /hls7/ { proxy_pass https://cs7.vpstv.net/hls/; }
    location ^~ /hls9/ { proxy_pass https://cs9.vpstv.net/hls/; }
    location ^~ /hls10/ { proxy_pass https://cs10.vpstv.net/hls/; }
}
EOF

    sudo ln -sf $NGINX_CONF /etc/nginx/sites-enabled/aimi-$DOMAIN
    sudo nginx -t
    sudo systemctl reload nginx

    sudo certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m admin@$DOMAIN || {
        echo "❌ 证书申请失败"
        exit 1
    }

    echo "✅ 部署完成！现在可通过 https://$DOMAIN 访问。"
else
    echo "❌ 无效选项"
    exit 1
fi