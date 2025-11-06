#!/bin/bash
# 快速修复Docker DNS配置脚本

set -e

echo "正在修复Docker DNS配置..."

# 备份原配置
if [[ -f /etc/docker/daemon.json ]]; then
    cp /etc/docker/daemon.json /etc/docker/daemon.json.bak.$(date +%Y%m%d_%H%M%S)
    echo "已备份原配置"
fi

# 使用Python更新配置
python3 << 'PYEOF'
import json
import sys

try:
    with open('/etc/docker/daemon.json', 'r') as f:
        config = json.load(f)
except Exception as e:
    config = {}

# 添加DNS配置
if 'dns' not in config:
    config['dns'] = ['8.8.8.8', '114.114.114.114', '223.5.5.5']
    print("已添加DNS配置")
else:
    dns_list = config['dns'] if isinstance(config['dns'], list) else [config['dns']]
    required_dns = ['8.8.8.8', '114.114.114.114', '223.5.5.5']
    added = False
    for dns in required_dns:
        if dns not in dns_list:
            dns_list.append(dns)
            added = True
    if added:
        config['dns'] = dns_list
        print("已更新DNS配置")
    else:
        print("DNS配置已存在")

# 写入配置
with open('/etc/docker/daemon.json', 'w') as f:
    json.dump(config, f, indent=2, ensure_ascii=False)

print("配置已保存到 /etc/docker/daemon.json")
PYEOF

# 重启Docker
echo "正在重启Docker服务..."
systemctl restart docker

# 等待Docker启动
echo "等待Docker服务启动..."
sleep 5

# 验证Docker
if docker info > /dev/null 2>&1; then
    echo "✓ Docker服务运行正常"
    echo ""
    echo "当前配置:"
    cat /etc/docker/daemon.json
    echo ""
    echo "✓ DNS配置已修复，可以重新运行部署脚本"
else
    echo "✗ Docker服务启动失败，请检查日志: journalctl -u docker"
    exit 1
fi

