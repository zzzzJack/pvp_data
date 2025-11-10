#!/bin/bash

# ============================================
# 服务状态检查和诊断脚本
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

PORT=8090
SERVICE_NAME="pvp-data"

echo ""
log_info "=========================================="
log_info "  服务状态检查和诊断"
log_info "=========================================="
echo ""

# 1. 检查 systemd 服务状态
log_info "==================== 1. Systemd 服务状态 ===================="
if systemctl list-unit-files | grep -q "${SERVICE_NAME}.service"; then
    systemctl status ${SERVICE_NAME} --no-pager -l | head -20
    echo ""
    
    if systemctl is-active --quiet ${SERVICE_NAME}; then
        log_success "服务正在运行"
    else
        log_error "服务未运行"
        log_info "启动服务: systemctl start ${SERVICE_NAME}"
    fi
else
    log_warning "systemd 服务未创建"
    log_info "创建服务: bash deploy_native.sh（选择创建 systemd 服务）"
fi

echo ""

# 2. 检查端口监听
log_info "==================== 2. 端口监听状态 ===================="
if netstat -tuln 2>/dev/null | grep -q ":${PORT} " || ss -tuln 2>/dev/null | grep -q ":${PORT} "; then
    log_success "端口 ${PORT} 正在监听"
    log_info "监听详情:"
    netstat -tuln 2>/dev/null | grep ":${PORT} " || ss -tuln 2>/dev/null | grep ":${PORT} "
else
    log_error "端口 ${PORT} 未在监听"
    log_info "可能原因: 服务未启动或启动失败"
fi

echo ""

# 3. 检查防火墙
log_info "==================== 3. 防火墙配置 ===================="
if command -v firewall-cmd &> /dev/null; then
    if systemctl is-active --quiet firewalld; then
        log_info "firewalld 状态: 运行中"
        if firewall-cmd --query-port=${PORT}/tcp 2>/dev/null | grep -q "yes"; then
            log_success "端口 ${PORT} 已在防火墙中开放"
        else
            log_warning "端口 ${PORT} 未在防火墙中开放"
            log_info "开放端口: firewall-cmd --permanent --add-port=${PORT}/tcp && firewall-cmd --reload"
        fi
        log_info "当前开放的端口:"
        firewall-cmd --list-ports 2>/dev/null || echo "无"
    else
        log_info "firewalld 未运行"
    fi
else
    log_info "未检测到 firewalld"
fi

# 检查 iptables
if command -v iptables &> /dev/null; then
    log_info "检查 iptables 规则..."
    if iptables -L INPUT -n 2>/dev/null | grep -q ":${PORT}"; then
        log_success "端口 ${PORT} 已在 iptables 中配置"
    else
        log_warning "iptables 中未找到端口 ${PORT} 的规则"
    fi
fi

echo ""

# 4. 测试本地连接
log_info "==================== 4. 本地连接测试 ===================="
if curl -sf http://localhost:${PORT}/api/health > /dev/null 2>&1; then
    log_success "本地连接测试成功"
    log_info "健康检查响应:"
    curl -s http://localhost:${PORT}/api/health | head -5
else
    log_error "本地连接测试失败"
    log_info "尝试详细连接:"
    curl -v http://localhost:${PORT}/api/health 2>&1 | head -20
fi

echo ""

# 5. 检查服务日志
log_info "==================== 5. 服务日志（最近20行） ===================="
if systemctl list-unit-files | grep -q "${SERVICE_NAME}.service"; then
    journalctl -u ${SERVICE_NAME} -n 20 --no-pager 2>/dev/null || log_warning "无法获取日志"
else
    log_info "服务未创建，无法查看日志"
fi

echo ""

# 6. 网络接口信息
log_info "==================== 6. 网络接口信息 ===================="
local_ip=$(hostname -I | awk '{print $1}')
log_info "服务器 IP 地址: ${local_ip}"
log_info "访问地址: http://${local_ip}:${PORT}"

echo ""

# 7. 诊断建议
log_info "==================== 7. 诊断建议 ===================="
if ! systemctl is-active --quiet ${SERVICE_NAME} 2>/dev/null; then
    log_warning "服务未运行，请先启动服务:"
    log_info "  systemctl start ${SERVICE_NAME}"
    echo ""
fi

if ! (netstat -tuln 2>/dev/null | grep -q ":${PORT} " || ss -tuln 2>/dev/null | grep -q ":${PORT} "); then
    log_warning "端口未监听，可能原因:"
    log_info "  1. 服务未启动"
    log_info "  2. 服务启动失败（查看日志: journalctl -u ${SERVICE_NAME} -f）"
    log_info "  3. 端口被其他程序占用"
    echo ""
fi

if command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
    if ! firewall-cmd --query-port=${PORT}/tcp 2>/dev/null | grep -q "yes"; then
        log_warning "防火墙未开放端口，执行以下命令:"
        log_info "  firewall-cmd --permanent --add-port=${PORT}/tcp"
        log_info "  firewall-cmd --reload"
        echo ""
    fi
fi

log_info "如果仍然无法访问，请检查:"
log_info "  1. 云服务器安全组是否开放了端口 ${PORT}"
log_info "  2. 服务是否正常启动: systemctl status ${SERVICE_NAME}"
log_info "  3. 查看详细日志: journalctl -u ${SERVICE_NAME} -f"

echo ""
log_info "=========================================="

