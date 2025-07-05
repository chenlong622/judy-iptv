#!/bin/bash

set -e

# 检测系统类型
if [ -f /etc/openwrt_release ]; then
    OS_TYPE="openwrt"
elif [ -f /etc/debian_version ]; then
    OS_TYPE="debian"
elif [ -f /etc/redhat-release ]; then
    OS_TYPE="centos"
else
    echo "检测系统中..."
    if command -v opkg &> /dev/null; then
        OS_TYPE="openwrt"
    elif grep -qi "openwrt\|lede" /proc/version &> /dev/null; then
        OS_TYPE="openwrt"
    elif command -v fw_printenv &> /dev/null && grep -qi "router\|wrt" /proc/cmdline &> /dev/null; then
        OS_TYPE="openwrt"
    else
        echo "不支持的系统类型！目前支持Debian/Ubuntu、CentOS和X86软路由系统。"
        exit 1
    fi
fi

if [ "$OS_TYPE" == "openwrt" ]; then
    echo "检测到系统类型: X86软路由系统 (OpenWrt)"
else
    echo "检测到系统类型: $([ "$OS_TYPE" == "debian" ] && echo "Debian/Ubuntu" || echo "CentOS")"
fi

echo "请选择操作："
echo "1) 使用公网IP，自定义HTTP端口"
echo "2) 使用自定义域名，监听80/443端口 (HTTPS)"
echo "3) 卸载所有安装内容"
read -p "请输入数字(1、2或3): " mode

if [[ "$mode" != "1" && "$mode" != "2" && "$mode" != "3" ]]; then
    echo "输入错误，退出"
    exit 1
fi

# 自定义端口变量
CUSTOM_PORT=8070

# 如果选择模式1，则询问用户自定义端口
if [ "$mode" == "1" ]; then
    read -p "请输入要使用的HTTP端口号 [默认: 8070]: " port_input
    if [ ! -z "$port_input" ]; then
        # 验证输入是否为有效端口号
        if [[ "$port_input" =~ ^[0-9]+$ ]] && [ "$port_input" -ge 1 ] && [ "$port_input" -le 65535 ]; then
            CUSTOM_PORT=$port_input
        else
            echo "无效的端口号，使用默认端口8070"
        fi
    fi
    echo "将使用端口: $CUSTOM_PORT"
fi

# 根据系统类型设置路径和命令
if [ "$OS_TYPE" == "debian" ]; then
    PKG_MANAGER="apt"
    NGINX_SITES_AVAILABLE="/etc/nginx/sites-available"
    NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"
    WEBROOT="/var/www/html"
elif [ "$OS_TYPE" == "openwrt" ]; then
    PKG_MANAGER="opkg"
    NGINX_SITES_AVAILABLE="/etc/nginx/conf.d"
    NGINX_SITES_ENABLED="/etc/nginx/conf.d"
    WEBROOT="/www"
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
    elif [ "$OS_TYPE" == "openwrt" ]; then
        rm -f ${NGINX_SITES_AVAILABLE}/stream_proxy.conf
        # 恢复OpenWrt默认Nginx配置
        if [ -f ${NGINX_SITES_AVAILABLE}/default.conf.backup ]; then
            mv ${NGINX_SITES_AVAILABLE}/default.conf.backup ${NGINX_SITES_AVAILABLE}/default.conf
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
    elif [ "$OS_TYPE" == "openwrt" ]; then
        if command -v fw3 &> /dev/null || command -v uci &> /dev/null; then
            # 删除防火墙规则
            uci delete firewall.stream_proxy 2>/dev/null || true
            uci commit firewall
            /etc/init.d/firewall restart
        fi
    else # centos
        if command -v firewall-cmd &> /dev/null && systemctl is-active firewalld &>/dev/null; then
            firewall-cmd --permanent --remove-port=8070/tcp 2>/dev/null || true
            firewall-cmd --permanent --remove-port=80/tcp 2>/dev/null || true
            firewall-cmd --permanent --remove-port=443/tcp 2>/dev/null || true
            firewall-cmd --reload
        fi
    fi
    
    # 卸载软件包
    if [ "$OS_TYPE" == "openwrt" ]; then
        opkg remove nginx nginx-ssl curl socat
        /etc/init.d/nginx stop || true
    else
        # 重启Nginx
        systemctl restart nginx || true
    fi
    
    echo "=========================="
    echo "卸载完成！"
    echo "已删除Nginx配置和相关防火墙规则"
    echo "=========================="
    exit 0
fi

# 安装依赖
if [ "$OS_TYPE" == "debian" ]; then
    apt update
    apt install -y nginx curl dnsutils
elif [ "$OS_TYPE" == "openwrt" ]; then
    opkg update
    opkg install nginx curl
    
    # 确保需要的目录存在
    mkdir -p ${NGINX_SITES_AVAILABLE}
    mkdir -p $WEBROOT
    
    # 备份默认配置
    if [ -f ${NGINX_SITES_AVAILABLE}/default.conf ] && [ ! -f ${NGINX_SITES_AVAILABLE}/default.conf.backup ]; then
        cp ${NGINX_SITES_AVAILABLE}/default.conf ${NGINX_SITES_AVAILABLE}/default.conf.backup
    fi
    
    # 启用Nginx服务
    /etc/init.d/nginx enable
    /etc/init.d/nginx start || echo "警告：nginx服务启动失败，将在配置完成后再次尝试启动"
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
    $PKG_MANAGER install -y nginx curl bind-utils
    
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
    if [ "$mode" == "1" ]; then
        # 为模式1创建单独的配置文件，区别于模式2
        conf_path="${NGINX_SITES_AVAILABLE}/aimi-ip$CUSTOM_PORT"
    fi
else # centos 或 openwrt
    conf_path="${NGINX_SITES_AVAILABLE}/stream_proxy.conf"
    if [ "$mode" == "1" ]; then
        # 为模式1创建单独的配置文件，区别于模式2
        conf_path="${NGINX_SITES_AVAILABLE}/aimi-ip$CUSTOM_PORT.conf"
    fi
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
    elif [ "$OS_TYPE" == "openwrt" ]; then
        opkg install socat
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
    echo "    listen $CUSTOM_PORT;" >> $conf_path
    echo "    server_name _;" >> $conf_path
else
    echo "    listen 80;" >> $conf_path
    echo "    server_name $mydomain;" >> $conf_path
fi

# 增强resolver配置，提高DNS解析成功率
echo "    resolver 8.8.8.8 8.8.4.4 1.1.1.1 114.114.114.114 223.5.5.5 valid=60s ipv6=off;" >> $conf_path
echo "    resolver_timeout 10s;" >> $conf_path

if [ "$mode" == "2" ]; then
    cat >> $conf_path << 'EOF2'
    location ^~ /.well-known/acme-challenge/ {
        root /var/www/html;
    }
    location / {
        return 301 https://$host$request_uri;
    }
EOF2

    # 针对CentOS和OpenWrt调整acme-challenge目录
    if [ "$OS_TYPE" == "centos" ] || [ "$OS_TYPE" == "openwrt" ]; then
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
    
    # 添加对 streams/*.m3u8 格式的支持
    location ~ ^/streams/.*\.m3u8$ {
        proxy_pass https://hls-gateway.vpstv.net;
        proxy_set_header Host hls-gateway.vpstv.net;
        proxy_ssl_server_name on;
        proxy_ssl_name hls-gateway.vpstv.net;
        proxy_ssl_verify off;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_buffering off;
        proxy_connect_timeout 60s;
        proxy_read_timeout 60s;
        proxy_send_timeout 60s;
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
        proxy_connect_timeout 60s;
        proxy_read_timeout 60s;
        proxy_send_timeout 60s;
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
        proxy_connect_timeout 60s;
        proxy_read_timeout 60s;
        proxy_send_timeout 60s;
    }
EOF3
fi

echo "}" >> $conf_path

# HTTPS 服务器配置 (模式2)
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
    
    # 添加对 streams/*.m3u8 格式的支持
    location ~ ^/streams/.*\.m3u8$ {
        proxy_pass https://hls-gateway.vpstv.net;
        proxy_set_header Host hls-gateway.vpstv.net;
        proxy_ssl_server_name on;
        proxy_ssl_name hls-gateway.vpstv.net;
        proxy_ssl_verify off;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_buffering off;
        proxy_connect_timeout 60s;
        proxy_read_timeout 60s;
        proxy_send_timeout 60s;
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
    # 为模式1创建符号链接
    if [ "$mode" == "1" ]; then
        ln -sf $conf_path ${NGINX_SITES_ENABLED}/aimi-ip$CUSTOM_PORT
        # 确保删除可能冲突的默认配置
        rm -f ${NGINX_SITES_ENABLED}/default
        rm -f ${NGINX_SITES_ENABLED}/stream_proxy
    else
        ln -sf $conf_path ${NGINX_SITES_ENABLED}/stream_proxy
        rm -f ${NGINX_SITES_ENABLED}/default
    fi
elif [ "$OS_TYPE" == "openwrt" ]; then
    # OpenWrt没有额外的符号链接需求
    # 但可能需要删除默认配置
    if [ -f /etc/nginx/conf.d/default.conf ]; then
        mv /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf.bak
    fi
else # centos
    # CentOS下可能需要备份默认配置
    if [ -f /etc/nginx/conf.d/default.conf ]; then
        mv /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf.bak
    fi
fi

# 创建用于测试连接的简单页面
echo "<html><body><h1>反向代理测试页面</h1><p>如果您看到此页面，说明Nginx服务器已成功安装并运行</p></body></html>" > $WEBROOT/index.html

# 安装其他可能需要的包
if [ "$OS_TYPE" == "debian" ]; then
    apt install -y ca-certificates openssl
elif [ "$OS_TYPE" == "openwrt" ]; then
    opkg install ca-certificates openssl-util libustream-openssl
else # centos
    $PKG_MANAGER install -y ca-certificates openssl
fi

# 预先测试DNS解析
echo "测试DNS解析..."
if command -v dig &> /dev/null; then
    echo "使用dig测试DNS解析:"
    dig +short hls-gateway.vpstv.net
    dig +short cs1.vpstv.net
    dig +short cs2.vpstv.net
elif command -v nslookup &> /dev/null; then
    echo "使用nslookup测试DNS解析:"
    nslookup hls-gateway.vpstv.net
    nslookup cs1.vpstv.net
    nslookup cs2.vpstv.net
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
            ufw allow $CUSTOM_PORT/tcp
        else
            ufw allow 80/tcp
            ufw allow 443/tcp
        fi
    fi
elif [ "$OS_TYPE" == "openwrt" ]; then
    # OpenWrt防火墙配置
    if command -v uci &> /dev/null; then
        echo "配置OpenWrt防火墙规则..."
        if [ "$mode" == "1" ]; then
            # 删除可能存在的旧规则
            uci delete firewall.stream_proxy 2>/dev/null || true
            
            # 添加新规则
            uci set firewall.stream_proxy=rule
            uci set firewall.stream_proxy.name='Stream Proxy'
            uci set firewall.stream_proxy.target='ACCEPT'
            uci set firewall.stream_proxy.src='wan'
            uci set firewall.stream_proxy.proto='tcp'
            uci set firewall.stream_proxy.dest_port="$CUSTOM_PORT"
            uci commit firewall
            /etc/init.d/firewall restart
        else
            # 删除可能存在的旧规则
            uci delete firewall.stream_proxy_http 2>/dev/null || true
            uci delete firewall.stream_proxy_https 2>/dev/null || true
            
            # 添加新规则 - HTTP
            uci set firewall.stream_proxy_http=rule
            uci set firewall.stream_proxy_http.name='Stream Proxy HTTP'
            uci set firewall.stream_proxy_http.target='ACCEPT'
            uci set firewall.stream_proxy_http.src='wan'
            uci set firewall.stream_proxy_http.proto='tcp'
            uci set firewall.stream_proxy_http.dest_port='80'
            
            # 添加新规则 - HTTPS
            uci set firewall.stream_proxy_https=rule
            uci set firewall.stream_proxy_https.name='Stream Proxy HTTPS'
            uci set firewall.stream_proxy_https.target='ACCEPT'
            uci set firewall.stream_proxy_https.src='wan'
            uci set firewall.stream_proxy_https.proto='tcp'
            uci set firewall.stream_proxy_https.dest_port='443'
            
            uci commit firewall
            /etc/init.d/firewall restart
        fi
    fi
else # centos
    if command -v firewall-cmd &> /dev/null && systemctl is-active firewalld &>/dev/null; then
        if [ "$mode" == "1" ]; then
            firewall-cmd --permanent --add-port=$CUSTOM_PORT/tcp
        else
            firewall-cmd --permanent --add-port=80/tcp
            firewall-cmd --permanent --add-port=443/tcp
        fi
        firewall-cmd --reload
    fi
fi

# 检查配置并重启服务
echo "检查Nginx配置..."
if [ "$OS_TYPE" == "openwrt" ]; then
    nginx -t && /etc/init.d/nginx restart || {
        echo "Nginx配置测试失败，请检查错误并手动修复..."
        echo "尝试继续启动..."
        /etc/init.d/nginx restart
    }
else
    nginx -t && {
        systemctl restart nginx || {
            echo "Nginx配置测试通过但启动失败，尝试修复..."
            sleep 2
            systemctl restart nginx
        }
    } || {
        echo "Nginx配置测试失败，请检查错误并手动修复..."
    }
fi

# 获取公网IP
IP=$(curl -s ifconfig.me || curl -s ipinfo.io/ip || curl -s ip.sb)

echo "=========================="
if [ "$OS_TYPE" == "openwrt" ]; then
    echo "系统类型: X86软路由系统 (OpenWrt)"
else
    echo "系统类型: $([ "$OS_TYPE" == "debian" ] && echo "Debian/Ubuntu" || echo "CentOS")"
fi

if [ "$mode" == "1" ]; then
    echo "HTTP 部署完成！"
    echo "主入口：http://$IP:$CUSTOM_PORT/"
else
    echo "HTTPS 部署完成！"
    if [ ! -z "$mydomain" ]; then
        echo "请确保您的域名 $mydomain 已正确解析到此服务器IP: $IP"
        echo "访问地址: https://$mydomain/"
    fi
fi
echo "交流群:https://t.me/IPTV_9999999 "
echo "作者： ！㋡ 三岁抬頭當王者🎖ᴴᴰ "
echo "=========================="