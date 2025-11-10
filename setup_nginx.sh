#!/bin/bash

# ============================================
# Nginx 反向代理配置脚本
# ============================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

APP_PORT=8090
NGINX_PORT=80
SERVER_IP=$(hostname -I | awk '{print $1}')
NGINX_CONF_DIR="/etc/nginx/conf.d"
NGINX_LOG_DIR="/data/nginx/logs"

echo ""
log_info "=========================================="
log_info "  Nginx 反向代理配置工具"
log_info "=========================================="
echo ""

# 检查是否为 root
if [[ $EUID -ne 0 ]]; then
    log_error "此脚本需要 root 权限运行"
    log_info "请使用: sudo $0"
    exit 1
fi

# 检查 nginx 是否安装
if ! command -v nginx &> /dev/null; then
    log_info "Nginx 未安装，开始安装..."
    yum install -y nginx || {
        log_error "Nginx 安装失败"
        exit 1
    }
    log_success "Nginx 安装成功"
else
    log_success "Nginx 已安装: $(nginx -v 2>&1)"
fi

# 创建日志目录
log_info "创建日志目录..."
mkdir -p "$NGINX_LOG_DIR" 2>/dev/null || true

# 生成 nginx 配置
log_info "生成 Nginx 配置文件..."

# 确定配置文件路径
if [[ -d "$NGINX_CONF_DIR" ]]; then
    CONFIG_FILE="${NGINX_CONF_DIR}/pvp_data.conf"
else
    CONFIG_FILE="/etc/nginx/sites-available/pvp_data.conf"
    mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled 2>/dev/null || true
fi

# 备份现有配置（如果存在）
if [[ -f "$CONFIG_FILE" ]]; then
    log_info "备份现有配置..."
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
fi

# 生成配置内容
log_info "写入配置文件: $CONFIG_FILE"
cat > "$CONFIG_FILE" << EOF
server {
    listen ${NGINX_PORT};
    server_name ${SERVER_IP};  # 使用服务器IP或域名

    # 访问日志（JSON 格式）
    access_log ${NGINX_LOG_DIR}/pvp_data_access.log json;
    error_log  ${NGINX_LOG_DIR}/pvp_data_error.log;

    # 客户端最大请求体大小（如果需要上传大文件，可以调整）
    client_max_body_size 100M;

    # 超时设置
    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    proxy_read_timeout 60s;

    location / {
        proxy_pass http://127.0.0.1:${APP_PORT};
        
        # 代理头设置
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        
        # WebSocket 支持（如果需要）
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # 缓冲设置
        proxy_buffering off;
        proxy_request_buffering off;
    }

    # 健康检查端点（可选，直接访问后端）
    location /api/health {
        proxy_pass http://127.0.0.1:${APP_PORT}/api/health;
        proxy_set_header Host \$host;
        access_log off;
    }
}
EOF

log_success "配置文件已创建: $CONFIG_FILE"

# 如果使用 sites-available，创建软链接
if [[ "$CONFIG_FILE" == *"sites-available"* ]]; then
    if [[ ! -f "/etc/nginx/sites-enabled/pvp_data.conf" ]]; then
        ln -sf "$CONFIG_FILE" /etc/nginx/sites-enabled/pvp_data.conf
        log_info "已创建软链接到 sites-enabled"
    fi
fi

# 测试 nginx 配置
log_info "测试 Nginx 配置..."
if nginx -t 2>&1; then
    log_success "Nginx 配置测试通过"
else
    log_error "Nginx 配置测试失败，请检查配置文件"
    exit 1
fi

# 启动或重载 nginx
if systemctl is-active --quiet nginx; then
    log_info "重载 Nginx 配置..."
    systemctl reload nginx
    log_success "Nginx 配置已重载"
else
    log_info "启动 Nginx 服务..."
    systemctl enable nginx
    systemctl start nginx
    log_success "Nginx 服务已启动"
fi

# 配置防火墙（开放 80 端口）
log_info "配置防火墙..."
if command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
    if ! firewall-cmd --query-port=${NGINX_PORT}/tcp 2>/dev/null | grep -q "yes"; then
        firewall-cmd --permanent --add-port=${NGINX_PORT}/tcp 2>&1
        firewall-cmd --reload 2>&1
        log_success "防火墙端口 ${NGINX_PORT} 已开放"
    else
        log_success "防火墙端口 ${NGINX_PORT} 已开放"
    fi
fi

echo ""
log_info "==================== 配置完成 ===================="
log_success "Nginx 反向代理配置完成"
echo ""
log_info "访问地址:"
log_success "  http://${SERVER_IP}:${NGINX_PORT}"
log_success "  http://${SERVER_IP}"
echo ""
log_info "配置文件位置: $CONFIG_FILE"
log_info "日志文件位置:"
log_info "  访问日志: ${NGINX_LOG_DIR}/pvp_data_access.log"
log_info "  错误日志: ${NGINX_LOG_DIR}/pvp_data_error.log"
echo ""
log_info "常用命令:"
log_info "  查看状态: systemctl status nginx"
log_info "  重载配置: systemctl reload nginx"
log_info "  查看日志: tail -f ${NGINX_LOG_DIR}/pvp_data_access.log"
echo ""
log_info "=========================================="

