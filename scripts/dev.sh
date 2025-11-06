#!/usr/bin/env bash
#-------------------------------------------------
# 工具包主脚本
# @author yeahoo2000@gmail.com
#-------------------------------------------------

# 检测是否在cygwin环境中
in_cygwin(){
    local os=$(uname)
    [[ "${os:0:3}" == "CYG" ]]; return $?
}
# 检测是否在linux环境中
in_linux(){
    local os=$(uname)
    [[ "${os:0:5}" == "Linux" ]]; return $?
}
cd /data/yscnew.dev

# # 记录开始时间（秒级时间戳）
# local start_time=$(date +%s)

# # 警报标志
# local alert_triggered=false

# # 启动后台监控进程
# local limit_time=600

# # 后台定时器函数
# monitor_time() {
#     local timeout=$1
#     while true; do
#         sleep 60  # 每分钟检查一次
#         local current_time=$(date +%s)
#         local elapsed=$((current_time - start_time))

#         if ((elapsed > timeout)); then
#             if ! $alert_triggered; then
#                 alert_triggered=true
#                 trigger_alert "资源编译超时警报" "已运行超过 $((timeout/60)) 分钟"
#                 curl 'https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=398f5b02-7b2f-4a8c-bdc8-4aba24e80a97' -H 'Content-Type: application/json' -d "
#                 {
#                     \"msgtype\": \"text\",
#                     \"text\": {
#                         \"content\": \"测试编译时间，超过$limit_time秒！\"
#                     }
#                 }"
#             fi
#         fi
#     done
# }

# monitor_time 60 &  # 超时
# echo "测试"
# local monitor_pid=$!

# # 确保在任何情况下都会停止监控进程
# trap "kill $monitor_pid 2>/dev/null" EXIT

./dev.sh make_resources pc

# 检测某个函数是否已经定义
is_fun_exists(){
    declare -F "$1" > /dev/null; return $?
}

# 检测某个命令是否存在
is_command_exists(){
    command -v $1 >/dev/null; return $?
}

# 检测某个screen session是否存在
# 注意此函数不是绝对可靠，有可能会找出名称相似的screen session
is_screen_exists(){
    [[ $(screen -ls | grep "$1" | wc -l ) -gt 0 ]] ; return $?
}

# 判定是否为整数
is_integer(){
    local re='^[0-9]+$'
    [[ $1 =~ $re ]]; return $?
}

# 检查数组中是否存在某个元素
# 参数1：数组
# 参数2: 元素
# 使用示例: in_array elems[@] $elem
in_array(){
    declare -a haystack=("${!1}")
    local needle=${2}
    for v in ${haystack[@]}; do
        if [[ ${v} == ${needle} ]]; then
            return 0
        fi
    done
    return 1
}

# 检查当前运行环境中是否存在tty
has_tty(){
    [[ -t 1 ]]; return $?
}

# 检查是否已经安装UnityEditor
check_unity_editor(){
    if [[ ! -f ${UNITY} ]]; then
        ERR "UnityEditor似乎未安装，请先安装或是编辑cfg.ini文件中的'UNITY'项，指定正确的路径"
        exit 1
    fi
}

# 获取sql语句执行结果中的第一行
# 返回的结果存放在$row变量中
# 用法示例:
# eval "$(mysql_get_row select * from mysql.user)"
# for k in ${!row[@]}; do
#     echo $k = ${row[$k]}
# done
mysql_get_row(){
    #set names utf8;
    local sql="$@ limit 1 "
    local lines=( $(mysql -h$OMS_DB_HOST -P$OMS_DB_PORT -u$OMS_DB_USER -p$OMS_DB_PASS -ss -D${OMS_DB_NAME} -e"$sql\G") )
    lines=( ${lines[*]//\**/} ) # 删除分隔符
    lines=( ${lines[*]//:\ /\'\]=\"} ) # 替换等号
    lines=( ${lines[*]/#/tmp\[\'} ) # 替换变量名
    lines=( ${lines[*]/%/\"} ) # 增加尾部双引号
    declare -A tmp row
    eval "$(echo "${lines[*]}")" # 转成关联数组
    # 去除多余空格
    for k in ${!tmp[@]}; do
        row[${k/#* /}]=${tmp[$k]}
    done
    declare -p row
}

# 输出一条普通信息
INFO(){
    echo -e "\e[92m=>\e[0;0m ${1}"
}

# 输出一条错误信息
ERR(){
    >&2 echo -e "\e[91m>>\e[0;0m ${1}"
}

# ini文件解析
ini_parser(){
    IFS=$'\n' && local ini=( $(<$1) )           # convert to line-array
    ini=( ${ini[*]//;*/} )                      # remove comments
    ini=( ${ini[*]/#[/\}$'\n'ini_section_} )    # set section prefix
    ini=( ${ini[*]/%]/ \(} )                    # convert text2function (1)
    ini=( ${ini[*]/=/=\( } )                    # convert item to array
    ini=( ${ini[*]/%/ \)} )                     # close array parenthesis
    ini=( ${ini[*]/%\( \)/\(\) \{} )            # convert text2function (2)
    ini=( ${ini[*]/%\} \)/\}} )                 # remove extra parenthesis
    ini[0]=''                                   # remove first element
    ini[${#ini[*]} + 1]='}'                     # add the last brace
    eval "$(echo "${ini[*]}")"                  # eval the result
}

# 获取脚本文件所在绝对路径(自动跟踪符号链接)
get_real_path(){
    local source="${BASH_SOURCE[0]}"
    while [ -h "$source" ]; do
        local dir="$( cd -P "$( dirname "$source" )" && pwd )"
        source="$( readlink "$source" )"
        [[ $source != /* ]] && source="$dir/$source"
    done
    echo "$( cd -P "$( dirname "$source" )/.." && pwd )"
}

# 检查锁
lock_check(){
    local task=$1
    local msg=$2
    lock=/tmp/unity_running_${task}.lock
    if [ -f $lock ]; then
        taskname=$(<$lock)
        ERR "Unity正在执行\"$taskname\"任务，需等待该任务完成..."
        exit 1
    fi
    touch $lock # 加锁
    echo $msg > $lock
}

# 解锁
lock_release(){
    local task=$1
    lock=/tmp/unity_running_${task}.lock
    rm -f $lock
}

# 调用函数
_CALL_FUNCTION(){
    local fname="fun"
    for arg in $@; do
        fname="${fname}_${arg}"
        shift
        if is_fun_exists ${fname}; then
            ${fname} $@
            exit 0
        fi
    done
    ERR "无效的指令，请使用以下指令"
    while [ ${#DOC[@]} -ne 0 ]; do
        mink=''
        for k in ${!DOC[@]}; do
            if [ "$mink" = "" ] || [[ "$mink" > "$k" ]]; then
                mink=$k
            fi
        done
        >&2 echo -e -n "\e[95m${mink}\e[0;0m"
        eval "printf ' %.0s' {1..$((26 - ${#mink}))}"
        >&2 echo -e "${DOC[$mink]}"
        unset DOC[$mink]
    done
}

# 输出命令行补全信息
fun_completion(){
    echo $(declare -p DOC)
}

# --- 执行入口 -----------------------------------------------------
ROOT=$(get_real_path)
declare -A DOC

ZONE_BASE=${ROOT}/zone # 默认服务器节点安装位置，cfg.ini中的配置会覆盖此项
# 检测并加载配置文件
if [ -f $ROOT/cfg.ini ]; then
    ini_parser "${ROOT}/cfg.ini"
    ini_section_default # 选择使用default段的配置内容
fi

# 载入子仓库中的工具脚本
scripts=( "tools/lang/gen_lang.sh" "tools/tools.sh" "tools/gen_map/gen_map.sh" "Xgame/xgame.sh" "Xtools/xtools.sh" "tools_core/gen_data/gen_data.sh" "server_core/server_core.sh" "client/cli.sh" "client/cli_apk.sh" "client/cli_subpack.sh" "client/cli_other.sh" "res.sh" "server/srv.sh" "android_api/androidapi.sh"  "map_editor/editor.sh" "tools/gen_battle/main.sh" "tools/jsx/gen_jsx.sh" "tools/gen_ai/gen_ai.sh" "tools/gen_ai/copy_ai.sh" "tools/lang/gen_lang.sh")
for f in ${scripts[@]}; do
    if [ ! -f ${ROOT}/${f} ]; then
        continue
    fi
    source ${ROOT}/${f}
done

# 根据参数调用相应命令
_CALL_FUNCTION $@
