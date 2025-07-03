#!/bin/bash

set -e

# 检测系统类型
if [ -f /etc/debian_version ]; then
    OS_TYPE="debian"
elif [ -f /etc/redhat-release ]; then
    OS_TYPE="centos"
else
    echo "不支持的系统类型！目前支持Debian/Ubuntu和CentOS系统。"
    exit 1
fi

echo "检测到系统类型: $([ "$OS_TYPE" == "debian" ] && echo "Debian/Ubuntu" || echo "CentOS")"
echo "请选择操作："
echo "1) 使用公网IP，监听8070端口 (HTTP)"
echo "2) 使用自定义域名，监听80/443端口 (HTTPS)"
echo "3) 卸载所有安装内容"
read -p "请输入数字(1、2或3): " mode

if [[ "$mode" != "1" && "$mode" != "2" && "$mode" != "3" ]]; then
    echo "输入错误，退出"
    exit 1
fi

# 根据系统类型设置路径和命令
if [ "$OS_TYPE" == "debian" ]; then
    PKG_MANAGER="apt"
    NGINX_SITES_AVAILABLE="/etc/nginx/sites-available"
    NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"
    WEBROOT="/var/www/html"
else # centos
    PKG_MANAGER="$(command -v dnf >/dev/null 2>&1 && echo 'dnf' || echo 'yum')"
    NGINX_SITES_AVAILABLE="/etc/nginx/conf.d"
    NGINX_SITES_ENABLED="/etc/nginx/conf.d"
    WEBROOT="/usr/share/nginx/html"
fi

# 卸载功能
if [ "$mode" == "3" ]; then
    echo "开始卸载..."
    
    # 删除Nginx配置
    if [ "$OS_TYPE" == "debian" ]; then
        rm -f ${NGINX_SITES_AVAILABLE}/stream_proxy
        rm -f ${NGINX_SITES_ENABLED}/stream_proxy
        
        # 恢复默认配置
        if [ -f ${NGINX_SITES_AVAILABLE}/default ]; then
            ln -sf ${NGINX_SITES_AVAILABLE}/default ${NGINX_SITES_ENABLED}/default
        fi
    else # centos
        rm -f ${NGINX_SITES_AVAILABLE}/stream_proxy.conf
    fi
    
    # 删除SSL证书目录
    rm -rf /etc/nginx/ssl/
    
    # 关闭防火墙规则
    if [ "$OS_TYPE" == "debian" ]; then
        if command -v ufw &> /dev/null; then
            ufw delete allow 8070/tcp 2>/dev/null || true
            ufw delete allow 80/tcp 2>/dev/null || true
            ufw delete allow 443/tcp 2>/dev/null || true
        fi
    else # centos
        if command -v firewall-cmd &> /dev/null && systemctl is-active firewalld &>/dev/null; then
            firewall-cmd --permanent --remove-port=8070/tcp 2>/dev/null || true
            firewall-cmd --permanent --remove-port=80/tcp 2>/dev/null || true
            firewall-cmd --permanent --remove-port=443/tcp 2>/dev/null || true
            firewall-cmd --reload
        fi
    fi
    
    # 重启Nginx
    systemctl restart nginx || true
    
    echo "=========================="
    echo "卸载完成！"
    echo "已删除Nginx配置和相关防火墙规则"
    echo "=========================="
    exit 0
fi

# 安装依赖
if [ "$OS_TYPE" == "debian" ]; then
    apt update
    apt install -y nginx curl
else # centos
    # 安装EPEL仓库
    $PKG_MANAGER install -y epel-release
    
    # 为CentOS安装Nginx官方仓库
    if [ ! -f /etc/yum.repos.d/nginx.repo ]; then
        echo "[nginx-stable]" > /etc/yum.repos.d/nginx.repo
        echo "name=nginx stable repo" >> /etc/yum.repos.d/nginx.repo
        echo "baseurl=http://nginx.org/packages/centos/\$releasever/\$basearch/" >> /etc/yum.repos.d/nginx.repo
        echo "gpgcheck=1" >> /etc/yum.repos.d/nginx.repo
        echo "enabled=1" >> /etc/yum.repos.d/nginx.repo
        echo "gpgkey=https://nginx.org/keys/nginx_signing.key" >> /etc/yum.repos.d/nginx.repo
        echo "module_hotfixes=true" >> /etc/yum.repos.d/nginx.repo
    fi
    
    # 清理并更新缓存
    $PKG_MANAGER clean all
    $PKG_MANAGER makecache
    
    # 安装Nginx和curl
    $PKG_MANAGER update
    $PKG_MANAGER install -y nginx curl
    
    # 确保nginx目录存在
    mkdir -p ${NGINX_SITES_AVAILABLE}
    mkdir -p $WEBROOT
    
    # 启用并启动nginx服务
    systemctl enable nginx
    systemctl start nginx || echo "警告：nginx服务启动失败，将在配置完成后再次尝试启动"
fi

# 设置配置文件路径
if [ "$OS_TYPE" == "debian" ]; then
    conf_path="${NGINX_SITES_AVAILABLE}/stream_proxy"
else # centos
    conf_path="${NGINX_SITES_AVAILABLE}/stream_proxy.conf"
fi

if [ "$mode" == "2" ]; then
    read -p "请输入你的自定义域名(如: proxy.xxx.com): " mydomain
    if [ -z "$mydomain" ]; then
        echo "域名不能为空，退出"
        exit 1
    fi
    cert_dir="/etc/nginx/ssl/$mydomain"
    mkdir -p $cert_dir
    
    if [ "$OS_TYPE" == "debian" ]; then
        apt install -y socat
    else # centos
        $PKG_MANAGER install -y socat
    fi
    
    curl https://get.acme.sh | sh
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    ~/.acme.sh/acme.sh --issue -d $mydomain --webroot $WEBROOT
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

    # 针对CentOS调整acme-challenge目录
    if [ "$OS_TYPE" == "centos" ]; then
        sed -i "s|root /var/www/html;|root $WEBROOT;|" $conf_path
    fi
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

# 根据系统类型处理nginx配置
if [ "$OS_TYPE" == "debian" ]; then
    ln -sf $conf_path ${NGINX_SITES_ENABLED}/stream_proxy
    rm -f ${NGINX_SITES_ENABLED}/default
else # centos
    # CentOS下可能需要备份默认配置
    if [ -f /etc/nginx/conf.d/default.conf ]; then
        mv /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf.bak
    fi
fi

# SELinux处理（CentOS特有）
if [ "$OS_TYPE" == "centos" ] && command -v sestatus &>/dev/null && sestatus | grep -q "enabled"; then
    echo "检测到SELinux已启用，设置适当的SELinux策略..."
    $PKG_MANAGER install -y policycoreutils-python-utils || $PKG_MANAGER install -y policycoreutils-python
    setsebool -P httpd_can_network_connect 1
    restorecon -Rv /etc/nginx/
fi

# 添加防火墙规则
if [ "$OS_TYPE" == "debian" ]; then
    if command -v ufw &> /dev/null; then
        if [ "$mode" == "1" ]; then
            ufw allow 8070/tcp
        else
            ufw allow 80/tcp
            ufw allow 443/tcp
        fi
    fi
else # centos
    if command -v firewall-cmd &> /dev/null && systemctl is-active firewalld &>/dev/null; then
        if [ "$mode" == "1" ]; then
            firewall-cmd --permanent --add-port=8070/tcp
        else
            firewall-cmd --permanent --add-port=80/tcp
            firewall-cmd --permanent --add-port=443/tcp
        fi
        firewall-cmd --reload
    fi
fi

# 检查配置并重启服务
nginx -t
systemctl restart nginx || {
    echo "Nginx启动失败，请检查错误日志："
    journalctl -xe --unit=nginx
}

IP=$(curl -s ifconfig.me || curl -s ipinfo.io/ip)

echo "=========================="
echo "系统类型: $([ "$OS_TYPE" == "debian" ] && echo "Debian/Ubuntu" || echo "CentOS")"
if [ "$mode" == "1" ]; then
    echo "HTTP 部署完成！"
    echo "主入口：http://$IP:8070/"
else
    echo "HTTPS 部署完成！"
fi
echo "交流群:https://t.me/IPTV_9999999 "
echo "作者： ！㋡ 三岁抬頭當王者🎖ᴴᴰ "
echo "=========================="
