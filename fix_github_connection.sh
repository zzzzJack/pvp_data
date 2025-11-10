#!/bin/bash

# ============================================
# GitHub 连接问题诊断和修复脚本
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

# 诊断网络连接
diagnose_connection() {
    log_info "==================== 网络诊断 ===================="
    
    # 1. 测试 DNS 解析
    log_info "1. 测试 DNS 解析..."
    if nslookup github.com > /dev/null 2>&1; then
        local github_ip=$(nslookup github.com | grep -A 1 "Name:" | tail -1 | awk '{print $2}' | head -1)
        log_success "DNS 解析成功: github.com -> $github_ip"
    else
        log_error "DNS 解析失败: 无法解析 github.com"
        return 1
    fi
    
    # 2. 测试网络连通性
    log_info "2. 测试网络连通性..."
    if ping -c 3 -W 2 github.com > /dev/null 2>&1; then
        log_success "网络连通性正常"
    else
        log_warning "网络连通性测试失败（可能禁用了 ping）"
    fi
    
    # 3. 测试 HTTPS 连接
    log_info "3. 测试 HTTPS 连接 (443端口)..."
    if timeout 10 bash -c "echo > /dev/tcp/github.com/443" 2>/dev/null; then
        log_success "HTTPS 端口 (443) 可达"
    else
        log_error "HTTPS 端口 (443) 不可达"
        return 1
    fi
    
    # 4. 测试 GitHub API
    log_info "4. 测试 GitHub API 连接..."
    if curl -sfL --connect-timeout 10 --max-time 30 "https://api.github.com" > /dev/null 2>&1; then
        log_success "GitHub API 连接正常"
    else
        log_warning "GitHub API 连接失败"
    fi
    
    echo ""
}

# 方案1: 配置 GitHub 镜像源（推荐）
setup_github_mirror() {
    log_info "==================== 方案1: 配置 GitHub 镜像源 ===================="
    
    # 测试可用的镜像源
    local mirrors=(
        "ghproxy:https://ghproxy.com/https://github.com"
        "ghps:https://ghps.cc/https://github.com"
        "fastgit:https://hub.fastgit.xyz"
        "gitclone:https://gitclone.com/github.com"
    )
    
    local mirror_available=false
    local selected_mirror=""
    
    for mirror_info in "${mirrors[@]}"; do
        local mirror_name=$(echo "$mirror_info" | cut -d: -f1)
        local mirror_url=$(echo "$mirror_info" | cut -d: -f2)
        
        log_info "测试镜像源 [$mirror_name]..."
        if curl -sfL --connect-timeout 5 --max-time 10 "$mirror_url" > /dev/null 2>&1; then
            selected_mirror="$mirror_url"
            mirror_available=true
            log_success "镜像源 [$mirror_name] 可用: $mirror_url"
            break
        else
            log_warning "镜像源 [$mirror_name] 不可用"
        fi
    done
    
    if [[ "$mirror_available" == "true" ]]; then
        log_info "使用镜像源克隆仓库..."
        local repo_url="https://github.com/zzzzJack/pvp_data.git"
        local mirror_repo_url="${selected_mirror}/zzzzJack/pvp_data.git"
        
        log_info "原始地址: $repo_url"
        log_info "镜像地址: $mirror_repo_url"
        
        if git clone "$mirror_repo_url" pvp_data 2>&1; then
            log_success "使用镜像源克隆成功！"
            return 0
        else
            log_warning "镜像源克隆失败，尝试其他方案..."
            return 1
        fi
    else
        log_warning "所有镜像源都不可用"
        return 1
    fi
}

# 方案2: 配置 hosts 文件
setup_github_hosts() {
    log_info "==================== 方案2: 配置 GitHub Hosts ===================="
    
    # 获取最新的 GitHub IP 地址
    log_info "获取 GitHub IP 地址..."
    
    # 常见的 GitHub IP（需要定期更新）
    local github_ips=(
        "140.82.112.3"
        "140.82.112.4"
        "140.82.113.3"
        "140.82.113.4"
        "20.205.243.166"
    )
    
    # 测试哪个 IP 可用
    local available_ip=""
    for ip in "${github_ips[@]}"; do
        log_info "测试 IP: $ip"
        if timeout 5 bash -c "echo > /dev/tcp/$ip/443" 2>/dev/null; then
            available_ip="$ip"
            log_success "IP $ip 可用"
            break
        fi
    done
    
    if [[ -n "$available_ip" ]]; then
        log_info "配置 hosts 文件..."
        # 备份 hosts 文件
        cp /etc/hosts /etc/hosts.bak.$(date +%Y%m%d_%H%M%S) 2>/dev/null || true
        
        # 移除旧的 GitHub 条目
        sed -i '/github.com/d' /etc/hosts 2>/dev/null || true
        
        # 添加新的 GitHub 条目
        echo "$available_ip github.com" >> /etc/hosts
        echo "$available_ip api.github.com" >> /etc/hosts
        echo "$available_ip raw.githubusercontent.com" >> /etc/hosts
        
        log_success "Hosts 配置完成"
        log_info "已添加以下映射:"
        grep "github.com" /etc/hosts | tail -3
        
        # 刷新 DNS 缓存
        if command -v systemd-resolve &> /dev/null; then
            systemd-resolve --flush-caches 2>/dev/null || true
        fi
        
        return 0
    else
        log_warning "未找到可用的 GitHub IP"
        return 1
    fi
}

# 方案3: 使用 SSH 方式（如果配置了 SSH key）
try_ssh_clone() {
    log_info "==================== 方案3: 尝试 SSH 方式 ===================="
    
    if [[ -f ~/.ssh/id_rsa ]] || [[ -f ~/.ssh/id_ed25519 ]]; then
        log_info "检测到 SSH 密钥，尝试使用 SSH 方式克隆..."
        
        local ssh_url="git@github.com:zzzzJack/pvp_data.git"
        
        # 测试 SSH 连接
        if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
            log_success "SSH 认证成功"
            if git clone "$ssh_url" pvp_data 2>&1; then
                log_success "使用 SSH 方式克隆成功！"
                return 0
            fi
        else
            log_warning "SSH 认证失败，请先配置 SSH key"
            log_info "配置 SSH key 教程: https://docs.github.com/en/authentication/connecting-to-github-with-ssh"
        fi
    else
        log_warning "未检测到 SSH 密钥"
    fi
    
    return 1
}

# 方案4: 配置 Git 代理（如果有代理）
setup_git_proxy() {
    log_info "==================== 方案4: 配置 Git 代理 ===================="
    
    read -p "您是否有可用的 HTTP/HTTPS 代理? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        read -p "请输入代理地址 (格式: http://proxy.example.com:8080): " proxy_url
        
        if [[ -n "$proxy_url" ]]; then
            log_info "配置 Git 代理: $proxy_url"
            git config --global http.proxy "$proxy_url"
            git config --global https.proxy "$proxy_url"
            
            log_success "Git 代理配置完成"
            
            # 测试连接
            if git clone "https://github.com/zzzzJack/pvp_data.git" pvp_data 2>&1; then
                log_success "使用代理克隆成功！"
                return 0
            else
                log_warning "使用代理克隆失败"
                # 取消代理配置
                git config --global --unset http.proxy
                git config --global --unset https.proxy
                return 1
            fi
        fi
    fi
    
    return 1
}

# 方案5: 修复 git pull 卡住问题
fix_git_pull_hanging() {
    log_info "==================== 方案5: 修复 git pull 卡住问题 ===================="
    
    # 1. 检查当前 Git 配置
    log_info "1. 检查当前 Git 配置..."
    local has_proxy=false
    local proxy_config=""
    
    if git config --global --get http.proxy > /dev/null 2>&1; then
        proxy_config=$(git config --global --get http.proxy)
        log_warning "检测到 Git HTTP 代理配置: $proxy_config"
        has_proxy=true
    fi
    
    if git config --global --get https.proxy > /dev/null 2>&1; then
        proxy_config=$(git config --global --get https.proxy)
        log_warning "检测到 Git HTTPS 代理配置: $proxy_config"
        has_proxy=true
    fi
    
    # 2. 测试代理是否可用（如果配置了）
    if [[ "$has_proxy" == "true" ]]; then
        log_info "2. 测试代理连接..."
        if [[ -n "$proxy_config" ]]; then
            local proxy_host=$(echo "$proxy_config" | sed -E 's|https?://([^:/]+).*|\1|')
            local proxy_port=$(echo "$proxy_config" | sed -E 's|.*:([0-9]+).*|\1|')
            
            if timeout 5 bash -c "echo > /dev/tcp/$proxy_host/${proxy_port:-8080}" 2>/dev/null; then
                log_success "代理服务器可达"
            else
                log_warning "代理服务器不可达，将清除代理配置"
                git config --global --unset http.proxy 2>/dev/null || true
                git config --global --unset https.proxy 2>/dev/null || true
                log_success "已清除无效的代理配置"
            fi
        fi
    fi
    
    # 3. 配置 Git 超时和缓冲区设置
    log_info "3. 配置 Git 超时和缓冲区设置..."
    
    # 设置 HTTP 超时（30秒）
    git config --global http.lowSpeedLimit 1000
    git config --global http.lowSpeedTime 30
    git config --global http.postBuffer 524288000  # 500MB
    
    # 设置连接超时
    git config --global http.sslVerify true
    git config --global http.version HTTP/1.1
    
    log_success "Git 超时和缓冲区配置完成"
    log_info "   - 低速限制: 1000 bytes/s"
    log_info "   - 超时时间: 30秒"
    log_info "   - 缓冲区: 500MB"
    
    # 4. 测试 git pull（带超时）
    log_info "4. 测试 git pull 连接..."
    
    # 检查是否在 git 仓库中
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log_warning "当前目录不是 Git 仓库，跳过 pull 测试"
        return 0
    fi
    
    # 获取远程仓库 URL
    local remote_url=$(git config --get remote.origin.url 2>/dev/null || echo "")
    if [[ -z "$remote_url" ]]; then
        log_warning "未找到远程仓库配置，跳过 pull 测试"
        return 0
    fi
    
    log_info "远程仓库: $remote_url"
    
    # 使用 timeout 命令测试 git fetch（模拟 pull）
    log_info "执行测试连接（超时 60 秒）..."
    if timeout 60 git fetch --dry-run origin 2>&1 | head -20; then
        log_success "Git 连接测试成功！"
        log_info ""
        log_info "现在可以尝试执行: git pull"
        return 0
    else
        local exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            log_error "Git 连接超时（60秒），可能网络较慢或连接有问题"
        else
            log_warning "Git 连接测试失败，但配置已优化"
        fi
        
        # 提供详细诊断建议
        log_info ""
        log_info "==================== 诊断建议 ===================="
        log_info "1. 尝试使用详细模式查看具体错误:"
        log_info "   GIT_CURL_VERBOSE=1 GIT_TRACE=1 git pull"
        log_info ""
        log_info "2. 尝试使用 SSH 方式（如果已配置 SSH key）:"
        log_info "   git remote set-url origin git@github.com:zzzzJack/pvp_data.git"
        log_info "   git pull"
        log_info ""
        log_info "3. 检查防火墙和网络设置"
        log_info ""
        
        return 1
    fi
}

# 主函数
main() {
    echo ""
    log_info "=========================================="
    log_info "  GitHub 连接问题诊断和修复工具"
    log_info "=========================================="
    echo ""
    
    # 诊断连接
    if ! diagnose_connection; then
        log_warning "网络诊断发现问题，将尝试修复方案..."
    fi
    
    echo ""
    log_info "==================== 尝试修复方案 ===================="
    echo ""
    
    # 按优先级尝试各种方案
    if setup_github_mirror; then
        log_success "问题已解决！"
        exit 0
    fi
    
    if setup_github_hosts; then
        log_info "Hosts 已配置，请重新尝试克隆:"
        log_info "  git clone https://github.com/zzzzJack/pvp_data.git"
        exit 0
    fi
    
    if try_ssh_clone; then
        log_success "问题已解决！"
        exit 0
    fi
    
    if setup_git_proxy; then
        log_success "问题已解决！"
        exit 0
    fi
    
    # 修复 git pull 卡住问题
    if fix_git_pull_hanging; then
        log_success "Git pull 配置已优化！"
        log_info "请尝试执行: git pull"
        exit 0
    fi
    
    echo ""
    log_error "所有方案都失败了"
    log_info "==================== 手动解决方案 ===================="
    log_info "1. 使用 Gitee 镜像（如果有）:"
    log_info "   git clone https://gitee.com/zzzzJack/pvp_data.git"
    echo ""
    log_info "2. 下载 ZIP 包:"
    log_info "   wget https://github.com/zzzzJack/pvp_data/archive/refs/heads/main.zip"
    log_info "   unzip main.zip"
    echo ""
    log_info "3. 配置系统代理（如果有）:"
    log_info "   export http_proxy=http://proxy.example.com:8080"
    log_info "   export https_proxy=http://proxy.example.com:8080"
    echo ""
    log_info "4. 联系网络管理员检查防火墙设置"
    echo ""
}

# 执行主函数
main "$@"

