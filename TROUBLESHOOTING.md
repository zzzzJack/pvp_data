# 故障排查指南

## DNS解析失败问题

### 问题描述

构建Docker镜像时出现以下错误：
```
Temporary failure resolving 'mirrors.aliyun.com'
```

### 原因分析

1. 服务器DNS配置不正确
2. 服务器无法访问外网
3. Docker daemon的DNS配置未设置

### 解决方案

#### 方案1：自动配置（推荐）

运行部署脚本，脚本会自动检测并配置DNS：

```bash
sudo ./deploy.sh
```

脚本会自动：
- 配置系统DNS（/etc/resolv.conf）
- 配置Docker daemon DNS（/etc/docker/daemon.json）
- 重启Docker服务

#### 方案2：手动配置DNS

**步骤1：配置系统DNS**

编辑 `/etc/resolv.conf`：

```bash
sudo vi /etc/resolv.conf
```

添加以下内容：
```
nameserver 8.8.8.8
nameserver 114.114.114.114
nameserver 223.5.5.5
```

**步骤2：配置Docker daemon DNS**

创建或编辑 `/etc/docker/daemon.json`：

```bash
sudo mkdir -p /etc/docker
sudo vi /etc/docker/daemon.json
```

添加以下内容：
```json
{
  "dns": ["8.8.8.8", "114.114.114.114", "223.5.5.5"]
}
```

**步骤3：重启Docker服务**

```bash
sudo systemctl restart docker
```

**步骤4：验证DNS**

```bash
# 测试系统DNS
nslookup mirrors.aliyun.com

# 测试Docker容器DNS
docker run --rm alpine nslookup mirrors.aliyun.com
```

#### 方案3：使用代理（如果服务器在内网）

如果服务器在内网需要通过代理访问外网：

**配置Docker代理**

编辑 `/etc/docker/daemon.json`：

```json
{
  "dns": ["8.8.8.8", "114.114.114.114"],
  "proxies": {
    "http-proxy": "http://proxy.example.com:8080",
    "https-proxy": "http://proxy.example.com:8080",
    "no-proxy": "localhost,127.0.0.1"
  }
}
```

重启Docker：
```bash
sudo systemctl restart docker
```

#### 方案4：使用离线构建（完全无法访问外网）

如果服务器完全无法访问外网，需要：

1. **在有网络的机器上构建镜像并导出**

```bash
# 在有网络的机器上
docker build -t pvp-app:latest .
docker save pvp-app:latest -o pvp-app.tar

# 将 pvp-app.tar 传输到目标服务器
```

2. **在目标服务器上导入镜像**

```bash
docker load -i pvp-app.tar
```

3. **修改docker-compose.yml使用本地镜像**

```yaml
app:
  image: pvp-app:latest  # 使用本地镜像而不是build
  # 注释掉build部分
  # build:
  #   context: .
  #   dockerfile: Dockerfile
```

### 验证网络连接

运行以下命令检查网络连接：

```bash
# 检查DNS解析
nslookup mirrors.aliyun.com
nslookup pypi.tuna.tsinghua.edu.cn

# 检查网络连通性
ping -c 3 8.8.8.8
ping -c 3 mirrors.aliyun.com

# 检查Docker网络
docker run --rm alpine ping -c 3 8.8.8.8
```

### 常见DNS服务器

- **Google DNS**: 8.8.8.8, 8.8.4.4
- **阿里DNS**: 223.5.5.5, 223.6.6.6
- **114 DNS**: 114.114.114.114, 114.114.115.115
- **腾讯DNS**: 119.29.29.29

### 其他问题

#### 防火墙阻止

如果DNS配置正确但仍无法连接，检查防火墙：

```bash
# CentOS 7
sudo firewall-cmd --list-all
sudo firewall-cmd --permanent --add-service=dns
sudo firewall-cmd --reload
```

#### SELinux问题

如果SELinux阻止Docker，临时禁用测试：

```bash
sudo setenforce 0
# 测试完成后，配置SELinux允许Docker
```

## 端口占用问题

### 检查端口占用

```bash
# 检查8090端口
netstat -tuln | grep 8090
lsof -i:8090

# 检查5432端口
netstat -tuln | grep 5432
```

### 释放端口

```bash
# 停止占用端口的服务
sudo systemctl stop <service-name>

# 或者修改docker-compose.yml使用其他端口
```

## 构建超时问题

### 增加构建超时时间

在 `docker-compose.yml` 中：

```yaml
app:
  build:
    context: .
    dockerfile: Dockerfile
    # 添加构建参数
    args:
      BUILDKIT_INLINE_CACHE: 1
```

或者使用环境变量：

```bash
export DOCKER_BUILDKIT=1
export COMPOSE_DOCKER_CLI_BUILD=1
docker-compose build
```

## 镜像拉取失败

### 使用国内镜像加速器

配置Docker镜像加速器，编辑 `/etc/docker/daemon.json`：

```json
{
  "registry-mirrors": [
    "https://docker.mirrors.ustc.edu.cn",
    "https://hub-mirror.c.163.com",
    "https://mirror.baidubce.com"
  ],
  "dns": ["8.8.8.8", "114.114.114.114"]
}
```

重启Docker：
```bash
sudo systemctl restart docker
```

## 获取帮助

如果以上方案都无法解决问题，请提供以下信息：

1. 系统版本：`cat /etc/redhat-release`
2. Docker版本：`docker --version`
3. 网络测试结果：`ping -c 3 8.8.8.8`
4. DNS测试结果：`nslookup mirrors.aliyun.com`
5. 完整的错误日志

