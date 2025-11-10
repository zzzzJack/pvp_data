#!/bin/bash

# ============================================
# 快速修复防火墙和端口访问问题
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

echo ""
log_info "=========================================="
log_info "  防火墙和端口访问修复工具"
log_info "=========================================="
echo ""

# 1. 检查端口监听
log_info "==================== 1. 检查端口监听 ===================="
if netstat -tuln 2>/dev/null | grep -q ":${PORT} " || ss -tuln 2>/dev/null | grep -q ":${PORT} "; then
    log_success "端口 ${PORT} 正在监听"
    netstat -tuln 2>/dev/null | grep ":${PORT} " || ss -tuln 2>/dev/null | grep ":${PORT} "
else
    log_error "端口 ${PORT} 未在监听"
    log_info "请先启动服务: systemctl start pvp-data"
    exit 1
fi

echo ""

# 2. 配置 firewalld
log_info "==================== 2. 配置防火墙 (firewalld) ===================="
if command -v firewall-cmd &> /dev/null; then
    if systemctl is-active --quiet firewalld; then
        log_info "firewalld 正在运行"
        
        # 检查端口是否已开放
        if firewall-cmd --query-port=${PORT}/tcp 2>/dev/null | grep -q "yes"; then
            log_success "端口 ${PORT} 已在防火墙中开放"
        else
            log_info "开放端口 ${PORT}/tcp..."
            if firewall-cmd --permanent --add-port=${PORT}/tcp 2>&1; then
                firewall-cmd --reload 2>&1
                if firewall-cmd --query-port=${PORT}/tcp 2>/dev/null | grep -q "yes"; then
                    log_success "端口 ${PORT} 已成功开放"
                else
                    log_error "端口开放失败"
                fi
            else
                log_error "无法添加防火墙规则"
            fi
        fi
        
        log_info "当前开放的端口:"
        firewall-cmd --list-ports 2>/dev/null || echo "无"
    else
        log_info "firewalld 未运行，跳过配置"
    fi
else
    log_info "未检测到 firewalld"
fi

echo ""

# 3. 配置 iptables（如果没有 firewalld）
log_info "==================== 3. 配置 iptables ===================="
if command -v iptables &> /dev/null && ! systemctl is-active --quiet firewalld 2>/dev/null; then
    log_info "检查 iptables 规则..."
    if iptables -L INPUT -n 2>/dev/null | grep -q ":${PORT}"; then
        log_success "端口 ${PORT} 已在 iptables 中配置"
    else
        log_info "添加 iptables 规则..."
        if iptables -I INPUT -p tcp --dport ${PORT} -j ACCEPT 2>&1; then
            log_success "iptables 规则已添加"
            # 尝试保存规则
            if command -v service &> /dev/null; then
                service iptables save 2>/dev/null || true
            fi
        else
            log_warning "iptables 规则添加失败（可能需要 root 权限）"
        fi
    fi
else
    log_info "跳过 iptables 配置（已使用 firewalld 或未安装 iptables）"
fi

echo ""

# 4. 测试本地连接
log_info "==================== 4. 测试本地连接 ===================="
if curl -sf http://localhost:${PORT}/api/health > /dev/null 2>&1; then
    log_success "本地连接测试成功"
    log_info "健康检查响应:"
    curl -s http://localhost:${PORT}/api/health
    echo ""
else
    log_error "本地连接测试失败"
    log_info "可能原因:"
    log_info "  1. 服务未正常启动"
    log_info "  2. 应用启动失败"
    log_info "查看日志: journalctl -u pvp-data -n 50"
fi

echo ""

# 5. 显示访问信息
log_info "==================== 5. 访问信息 ===================="
local_ip=$(hostname -I | awk '{print $1}')
log_info "服务器 IP 地址: ${local_ip}"
log_success "本地访问: http://localhost:${PORT}"
log_success "远程访问: http://${local_ip}:${PORT}"
log_success "健康检查: http://${local_ip}:${PORT}/api/health"

echo ""

# 6. 重要提示
log_info "==================== 6. 重要提示 ===================="
log_warning "如果仍然无法从外部访问，请检查:"
log_info "1. 云服务器安全组规则（最重要）:"
log_info "   - 登录云服务器控制台"
log_info "   - 找到安全组设置"
log_info "   - 添加入站规则: 端口 ${PORT}, 协议 TCP, 源地址 0.0.0.0/0"
log_info ""
log_info "2. 检查服务状态:"
log_info "   systemctl status pvp-data"
log_info ""
log_info "3. 查看服务日志:"
log_info "   journalctl -u pvp-data -f"

echo ""
log_info "=========================================="

