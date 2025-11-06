#!/usr/bin/env bash
function do_pull {
  git pull
}
cd /data/yscnew.dev/lua
git pull
cd /data/yscnew.dev/data
git pull
cd /data/yscnew.dev/resources
output=$(do_pull 2> /tmp/pull_error.log)
if [ $? -ne 0 ]; then
  git checkout Assets/Things
  git clean -df Assets/Things
  output=$(do_pull 2> /tmp/pull_error.log)
  if [ $? -ne 0 ]; then
    error=$(cat /tmp/pull_error.log)
    curl 'https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=398f5b02-7b2f-4a8c-bdc8-4aba24e80a97' -H 'Content-Type: application/json' -d "
            {
                \"msgtype\": \"text\",
                \"text\": {
                    \"content\": \"常规服拉资源报错$error！\"
                }
            }"
    exit 1
  fi
fi
cd /data/yscnew.dev

# 执行主编译（带超时监控）
# 记录开始时间
start_time=$(date +%s)
timeout_seconds=600  # 10分钟 = 600秒
monitor_bg_pid=""
monitor_flag_file="/tmp/build_monitor_$$.flag"
alert_flag_file="/tmp/build_alert_$$.flag"

# 监控函数：后台检查执行时间
monitor_timeout() {
    local timeout=$1
    local start=$2
    local flag_file=$3
    local alert_file=$4
    while true; do
        sleep 60  # 每60秒检查一次
        # 检查监控标志文件是否存在，如果不存在说明主进程已结束
        if [ ! -f "$flag_file" ]; then
            break
        fi
        local current_time=$(date +%s)
        local elapsed=$((current_time - start))
        # 检查是否超时且未发送过预警
        if [ $elapsed -gt $timeout ] && [ ! -f "$alert_file" ]; then
            # 创建预警标记文件，防止重复发送
            touch "$alert_file"
            local elapsed_min=$((elapsed / 60))
            curl 'https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=398f5b02-7b2f-4a8c-bdc8-4aba24e80a97' -H 'Content-Type: application/json' -d "{
                \"msgtype\": \"text\",
                \"text\": {
                    \"content\": \"编译超时预警：./dev.sh make_resources pc 已执行超过10分钟（当前已执行${elapsed_min}分钟），请检查编译进程状态！\"
                }
            }" 2>/dev/null
        fi
    done
}

# 创建监控标志文件
touch "$monitor_flag_file"

# 启动监控进程
monitor_timeout $timeout_seconds $start_time "$monitor_flag_file" "$alert_flag_file" &
monitor_bg_pid=$!

# 清理函数：确保监控进程和标志文件被清理
cleanup_monitor() {
    # 删除标志文件，通知监控进程退出
    rm -f "$monitor_flag_file" "$alert_flag_file"
    # 等待监控进程退出
    if [ ! -z "$monitor_bg_pid" ] && kill -0 $monitor_bg_pid 2>/dev/null; then
        kill $monitor_bg_pid 2>/dev/null
        wait $monitor_bg_pid 2>/dev/null
    fi
}

# 设置退出时清理监控进程
trap cleanup_monitor EXIT INT TERM

# 执行编译命令
./dev.sh make_resources pc
compile_exit_code=$?

# 清理监控进程
cleanup_monitor

# 如果编译失败，退出
if [ $compile_exit_code -ne 0 ]; then
    exit $compile_exit_code
fi

echo "所有操作完成"