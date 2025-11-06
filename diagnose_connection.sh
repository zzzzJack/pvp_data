#!/bin/bash
# 诊断连接问题

echo "==================== 容器状态 ===================="
docker-compose ps

echo ""
echo "==================== 应用容器日志（最近20行） ===================="
docker-compose logs --tail=20 app

echo ""
echo "==================== 检查容器内监听 ===================="
docker-compose exec app netstat -tlnp 2>/dev/null || docker-compose exec app ss -tlnp 2>/dev/null || echo "无法检查容器内监听状态"

echo ""
echo "==================== 容器内访问健康检查 ===================="
docker-compose exec app curl -s http://localhost:8090/api/health 2>&1 || echo "容器内访问失败"

echo ""
echo "==================== 宿主机端口监听 ===================="
netstat -tlnp | grep 8090 || ss -tlnp | grep 8090

echo ""
echo "==================== 测试IPv4连接 ===================="
curl -v -4 http://127.0.0.1:8090/api/health 2>&1 | head -20

echo ""
echo "==================== 测试IPv6连接 ===================="
curl -v -6 http://[::1]:8090/api/health 2>&1 | head -20 || echo "IPv6连接失败"

echo ""
echo "==================== 检查防火墙 ===================="
if command -v firewall-cmd &> /dev/null; then
    firewall-cmd --list-ports
    firewall-cmd --list-all | grep -A 5 "ports:"
fi

