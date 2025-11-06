#!/bin/bash
# 检查容器内的环境变量

echo "==================== 检查应用容器环境变量 ===================="
docker-compose exec app env | grep POSTGRES

echo ""
echo "==================== 检查数据库连接字符串 ===================="
docker-compose exec app python -c "
import os
from backend.app.database import DATABASE_URL, DB_NAME, DB_USER, DB_HOST, DB_PORT
print(f'DB_NAME: {DB_NAME}')
print(f'DB_USER: {DB_USER}')
print(f'DB_HOST: {DB_HOST}')
print(f'DB_PORT: {DB_PORT}')
print(f'DATABASE_URL: {DATABASE_URL}')
"

echo ""
echo "==================== 测试数据库连接 ===================="
docker-compose exec app python -c "
from backend.app.database import engine
try:
    with engine.connect() as conn:
        print('✓ 数据库连接成功')
except Exception as e:
    print(f'✗ 数据库连接失败: {e}')
"

