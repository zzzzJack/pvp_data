#!/bin/bash

# ============================================
# PVP数据看板系统 - 一键部署脚本 (CentOS)
# ============================================

set -e  # 遇到错误立即退出

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

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        log_info "请使用: sudo $0"
        exit 1
    fi
}

# 检查系统版本
check_centos() {
    if [[ -f /etc/redhat-release ]]; then
        local version=$(cat /etc/redhat-release)
        log_info "检测到系统: $version"
    else
        log_warning "未检测到CentOS/RHEL系统，继续执行..."
    fi
}

# 安装Docker
install_docker() {
    if command -v docker &> /dev/null; then
        local version=$(docker --version)
        log_success "Docker已安装: $version"
        return 0
    fi

    log_info "开始安装Docker..."
    
    # 卸载旧版本
    yum remove -y docker docker-client docker-client-latest \
        docker-common docker-latest docker-latest-logrotate \
        docker-logrotate docker-engine 2>/dev/null || true

    # 安装必要的工具
    yum install -y yum-utils device-mapper-persistent-data lvm2

    # 添加Docker仓库
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

    # 安装Docker
    yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    # 启动Docker服务
    systemctl start docker
    systemctl enable docker

    # 验证安装
    if docker --version &> /dev/null; then
        log_success "Docker安装成功: $(docker --version)"
    else
        log_error "Docker安装失败"
        exit 1
    fi
}

# 安装Docker Compose (standalone)
install_docker_compose() {
    if command -v docker-compose &> /dev/null; then
        local version=$(docker-compose --version)
        log_success "Docker Compose已安装: $version"
        return 0
    fi

    log_info "开始安装Docker Compose..."
    
    # 下载Docker Compose
    local compose_version="v2.24.0"
    local compose_url="https://github.com/docker/compose/releases/download/${compose_version}/docker-compose-linux-x86_64"
    
    curl -L "$compose_url" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    
    # 创建软链接（如果需要）
    if [[ ! -f /usr/bin/docker-compose ]]; then
        ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
    fi

    # 验证安装
    if docker-compose --version &> /dev/null; then
        log_success "Docker Compose安装成功: $(docker-compose --version)"
    else
        log_error "Docker Compose安装失败"
        exit 1
    fi
}

# 检查端口占用
check_ports() {
    local ports=(8090 5432)
    local conflicts=()

    for port in "${ports[@]}"; do
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            conflicts+=($port)
        fi
    done

    if [[ ${#conflicts[@]} -gt 0 ]]; then
        log_warning "以下端口已被占用: ${conflicts[*]}"
        read -p "是否继续部署? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# 检查必要的文件
check_files() {
    local required_files=("Dockerfile" "docker-compose.yml" "requirements.txt")
    local missing_files=()

    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            missing_files+=($file)
        fi
    done

    if [[ ${#missing_files[@]} -gt 0 ]]; then
        log_error "缺少必要文件: ${missing_files[*]}"
        log_error "请确保在项目根目录运行此脚本"
        exit 1
    fi

    log_success "所有必要文件检查通过"
}

# 创建必要的目录
create_directories() {
    log_info "创建必要的目录..."
    mkdir -p data_logs
    log_success "目录创建完成"
}

# 停止旧容器
stop_old_containers() {
    log_info "停止旧容器..."
    docker-compose down 2>/dev/null || true
    log_success "旧容器已停止"
}

# 构建和启动服务
deploy_services() {
    log_info "开始构建和启动服务..."
    
    # 构建镜像
    log_info "构建Docker镜像..."
    docker-compose build --no-cache
    
    # 启动服务
    log_info "启动服务..."
    docker-compose up -d
    
    # 等待服务就绪
    log_info "等待服务启动..."
    sleep 10
    
    # 检查服务状态
    local max_retries=30
    local retry_count=0
    
    while [[ $retry_count -lt $max_retries ]]; do
        if docker-compose ps | grep -q "Up"; then
            if curl -sf http://localhost:8090/api/health > /dev/null 2>&1; then
                log_success "服务启动成功！"
                return 0
            fi
        fi
        retry_count=$((retry_count + 1))
        sleep 2
        log_info "等待服务就绪... ($retry_count/$max_retries)"
    done
    
    log_warning "服务可能未完全启动，请检查日志"
    return 1
}

# 显示服务状态
show_status() {
    echo ""
    log_info "==================== 服务状态 ===================="
    docker-compose ps
    echo ""
    
    log_info "==================== 服务信息 ===================="
    log_success "应用访问地址: http://$(hostname -I | awk '{print $1}'):8090"
    log_success "本地访问地址: http://localhost:8090"
    log_success "健康检查: http://localhost:8090/api/health"
    echo ""
    
    log_info "==================== 常用命令 ===================="
    echo "查看日志: docker-compose logs -f"
    echo "停止服务: docker-compose down"
    echo "重启服务: docker-compose restart"
    echo "查看状态: docker-compose ps"
    echo "================================================"
}

# 主函数
main() {
    echo ""
    log_info "=========================================="
    log_info "  PVP数据看板系统 - 一键部署脚本"
    log_info "=========================================="
    echo ""

    # 执行检查
    check_root
    check_centos
    check_files
    check_ports
    create_directories

    # 安装依赖
    install_docker
    install_docker_compose

    # 部署服务
    stop_old_containers
    deploy_services

    # 显示状态
    show_status

    log_success "部署完成！"
}

# 执行主函数
main "$@"

