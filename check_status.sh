#!/bin/bash
# 快速检查服务状态的脚本

echo "==================== 容器状态 ===================="
docker-compose ps

echo ""
echo "==================== 应用容器日志 ===================="
docker-compose logs --tail=50 app

echo ""
echo "==================== 数据库容器日志 ===================="
docker-compose logs --tail=20 postgres

echo ""
echo "==================== 测试健康检查 ===================="
curl -v http://localhost:8090/api/health 2>&1 || echo "健康检查失败"

echo ""
echo "==================== 网络连接测试 ===================="
docker-compose exec -T app python -c "import urllib.request; print(urllib.request.urlopen('http://localhost:8090/api/health').read().decode())" 2>&1 || echo "容器内健康检查失败"

