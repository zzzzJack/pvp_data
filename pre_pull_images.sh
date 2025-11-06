#!/bin/bash
# 预先拉取Docker镜像脚本

set -e

echo "正在预先拉取Docker镜像..."

# 拉取Python基础镜像
echo "拉取 python:3.11-slim 镜像..."
docker pull python:3.11-slim

# 拉取PostgreSQL镜像
echo "拉取 postgres:15 镜像..."
docker pull postgres:15

echo "✓ 所有基础镜像已拉取完成"
echo ""
echo "现在可以运行部署脚本: sudo bash deploy.sh"

