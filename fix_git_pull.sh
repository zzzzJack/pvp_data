#!/bin/bash

# ============================================
# 快速修复 git pull 卡住问题
# ============================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
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

echo ""
log_info "=========================================="
log_info "  快速修复 git pull 卡住问题"
log_info "=========================================="
echo ""

# 1. 检查是否在 git 仓库中
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    log_error "当前目录不是 Git 仓库"
    exit 1
fi

# 2. 检查并清理无效的代理配置
log_info "==================== 步骤 1: 检查 Git 配置 ===================="

local has_proxy=false
local proxy_config=""

if git config --global --get http.proxy > /dev/null 2>&1; then
    proxy_config=$(git config --global --get http.proxy)
    log_warning "检测到 Git HTTP 代理: $proxy_config"
    has_proxy=true
fi

if git config --global --get https.proxy > /dev/null 2>&1; then
    proxy_config=$(git config --global --get https.proxy)
    log_warning "检测到 Git HTTPS 代理: $proxy_config"
    has_proxy=true
fi

# 测试代理是否可用
if [[ "$has_proxy" == "true" ]] && [[ -n "$proxy_config" ]]; then
    log_info "测试代理连接..."
    local proxy_host=$(echo "$proxy_config" | sed -E 's|https?://([^:/]+).*|\1|')
    local proxy_port=$(echo "$proxy_config" | sed -E 's|.*:([0-9]+).*|\1|')
    
    if timeout 5 bash -c "echo > /dev/tcp/$proxy_host/${proxy_port:-8080}" 2>/dev/null; then
        log_success "代理服务器可达"
    else
        log_warning "代理服务器不可达，清除代理配置..."
        git config --global --unset http.proxy 2>/dev/null || true
        git config --global --unset https.proxy 2>/dev/null || true
        log_success "已清除无效的代理配置"
    fi
else
    log_success "未检测到代理配置"
fi

# 3. 配置 Git 超时和缓冲区
log_info ""
log_info "==================== 步骤 2: 优化 Git 配置 ===================="

# 设置 HTTP 超时和缓冲区
git config --global http.lowSpeedLimit 1000
git config --global http.lowSpeedTime 30
git config --global http.postBuffer 524288000  # 500MB
git config --global http.sslVerify true
git config --global http.version HTTP/1.1

log_success "Git 配置已优化:"
log_info "   - 低速限制: 1000 bytes/s"
log_info "   - 超时时间: 30秒"
log_info "   - 缓冲区: 500MB"
log_info "   - HTTP 版本: HTTP/1.1"

# 4. 测试连接
log_info ""
log_info "==================== 步骤 3: 测试连接 ===================="

local remote_url=$(git config --get remote.origin.url 2>/dev/null || echo "")
if [[ -z "$remote_url" ]]; then
    log_warning "未找到远程仓库配置"
    exit 1
fi

log_info "远程仓库: $remote_url"
log_info "执行连接测试（超时 60 秒）..."

# 使用 timeout 测试连接
if timeout 60 git ls-remote --heads origin 2>&1 | head -5; then
    log_success ""
    log_success "连接测试成功！"
    log_info ""
    log_info "现在可以尝试执行: git pull"
    log_info ""
    log_info "如果仍然卡住，可以尝试:"
    log_info "  1. 使用详细模式查看具体错误:"
    log_info "     GIT_CURL_VERBOSE=1 GIT_TRACE=1 git pull"
    log_info ""
    log_info "  2. 使用 SSH 方式（如果已配置 SSH key）:"
    log_info "     git remote set-url origin git@github.com:zzzzJack/pvp_data.git"
    log_info "     git pull"
    exit 0
else
    local exit_code=$?
    log_error ""
    if [[ $exit_code -eq 124 ]]; then
        log_error "连接超时（60秒）"
    else
        log_error "连接测试失败"
    fi
    
    log_info ""
    log_info "建议的解决方案:"
    log_info "1. 检查网络连接和防火墙设置"
    log_info "2. 使用详细模式查看错误:"
    log_info "   GIT_CURL_VERBOSE=1 GIT_TRACE=1 timeout 60 git ls-remote origin"
    log_info "3. 尝试使用 SSH 方式"
    log_info "4. 检查 hosts 文件配置: cat /etc/hosts | grep github"
    exit 1
fi

