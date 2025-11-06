#!/usr/bin/env bash
#-------------------------------------------------
# 资源库相关开发工具
# @author yeahoo2000@gmail.com
#-------------------------------------------------
if [ "" == "$ROOT" ]; then
    echo -e "\e[91m>>\e[0;0m 此脚本必须通过tools/dev.sh调用才能正常工作"
    exit 1
fi

PLATFORM=( "mac" "pc" "android" "ios" )

# 检查平台参数是否正确
check_platform(){
    if [[ "" == $1 ]]; then
        IFS=$' ' && ERR "请传入平台标识，有效值: ${PLATFORM[*]}"
        exit 1
    fi
    if ! in_array PLATFORM[@] $1; then
        IFS=$' ' && ERR "不支持的平台${1}，有效值: ${PLATFORM[*]}"
        exit 1
    fi
}
function make_error_msg(){
    if [ ! "" == "$BUILDROBOT" ]; then
        curl 'https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=f114c33d-97df-4015-ba18-a29fe64055fd' -H 'Content-Type: application/json' -d "
        {
            \"msgtype\": \"text\",
            \"text\": {
                \"content\": \"开发服${BUILDROBOT}客户端资源编译失败！\"
            }
        }"
    fi
}

DOC[make_resources]="编译资源库"
fun_make_resources(){
    local platform=$1
    local lock_name=make_newres_$platform
    check_platform $platform

    if [[ "pc" == $platform || "mac" == $platform ]]; then
        local res=${ROOT}/resources
    else
        local res=${ROOT}/resources_${platform}
    fi

    if [[ ! -d $res ]]; then
        ERR "因为unity切换平台比较耗时，所以请将resources复制一份到同级目录，并命名为resources_${platform}，这样可以省去平台切换的时间(第一次执行仍然会比较耗时，但之后就会快很多了)"
        lock_release $lock_name
        exit 1
    fi

    lock_check $lock_name "编译GameResources资源文件"
    logfile=/dev/stdout
    if $(in_cygwin); then
        logfile=${ROOT}/release/build_log.text
        INFO "日志保存在 ${logfile} 文件中"
        ${res}/tail_log.sh $logfile &
        PID=$!
    elif $(in_linux); then
        logfile=${ROOT}/release/build_log.text
        INFO "日志保存在 ${logfile} 文件中"
    fi

    INFO "正在编译 ${platform} 平台的资源库，路径: $res ..."
    $UNITY -batchmode -username linwenxuan@shiyue.com -password ysc666@123A -serial SC-GRWF-JSZB-2KGX-RJSF-62A3 -projectPath /resources -executeMethod EditorTools.Patch.AssetPatchMaker.MakePatchCmd -CustomArgs:BuildTarget=${platform} -quit -nographics -logFile ${logfile} || make_error_msg
    lock_release $lock_name
    if [ -n "$PID" ]; then
        kill $PID
    fi

    INFO "编译 ${platform} 平台的资源库完成"
}

DOC[make_resources_add]="编译lua增量"
fun_make_resources_add(){
    local platform=$1
    local lock_name=make_newres_$platform
    check_platform $platform

    if [[ "pc" == $platform || "mac" == $platform ]]; then
        local res=${ROOT}/resources
    else
        local res=${ROOT}/resources_${platform}
    fi

    if [[ ! -d $res ]]; then
        ERR "因为unity切换平台比较耗时，所以请将resources复制一份到同级目录，并命名为resources_${platform}，这样可以省去平台切换的时间(第一次执行仍然会比较耗时，但之后就会快很多了)"
        lock_release $lock_name
        exit 1
    fi

    lock_check $lock_name "编译GameResources lua增量文件"
    logfile=/dev/stdout
    if $(in_cygwin); then
        logfile=${ROOT}/release/build_log.text
        INFO "日志保存在 ${logfile} 文件中"
        ${res}/tail_log.sh $logfile &
        PID=$!
    fi

    INFO "正在编译 ${platform} 平台的资源库，路径: $res ..."
    $UNITY -batchmode -projectPath resources -executeMethod EditorTools.Patch.AssetPatchMaker.MakeLuaAddCmd -CustomArgs:BuildTarget=${platform} -quit -nographics -logFile ${logfile}
    lock_release $lock_name
    if [ -n "$PID" ]; then
        kill $PID
    fi

    INFO "编译 ${platform} 平台的资源库完成"
}

DOC[make_resources_data]="编译资源数据"
fun_make_resources_data(){
    local platform=$1
    local lock_name=make_resdata_$platform
    check_platform $platform

    if [[ "pc" == $platform || "mac" == $platform ]]; then
        local res=${ROOT}/resources
    else
        local res=${ROOT}/resources_${platform}
    fi

    if [[ ! -d $res ]]; then
        ERR "因为unity切换平台比较耗时，所以请将resources复制一份到同级目录，并命名为resources_${platform}，这样可以省去平台切换的时间(第一次执行仍然会比较耗时，但之后就会快很多了)"
        lock_release $lock_name
        exit 1
    fi

    lock_check $lock_name "编译GameResources资源文件"
    # logfile=/dev/stdout
    # if $(in_cygwin); then
        logfile=${ROOT}/release/build_log.text
        INFO "日志保存在 ${logfile} 文件中"
        # ${res}/tail_log.sh $logfile &
        # PID=$!
    # fi

    INFO "正在编译 ${platform} 平台的资源库，路径: $res ..."
    $UNITY -batchmode -username linwenxuan@shiyue.com -password ysc666@123A -serial SC-GRWF-JSZB-2KGX-RJSF-62A3 -projectPath /resources -executeMethod EditorTools.Patch.AssetPatchMaker.MakePatchDataOnlyCmd -CustomArgs:BuildTarget=${platform} -quit -nographics -logFile ${logfile}
    lock_release $lock_name
    if [ -n "$PID" ]; then
        kill $PID
    fi

    INFO "编译 ${platform} 平台的资源数据完成"
}

DOC[split_resources]="分解资源"
fun_split_resources(){
    local platform=$1
    local lock_name=make_newres_$platform
    check_platform $platform

    if [[ "pc" == $platform || "mac" == $platform ]]; then
        local res=${ROOT}/resources
    else
        local res=${ROOT}/resources_${platform}
    fi

    if [[ ! -d $res ]]; then
        ERR "因为unity切换平台比较耗时，所以请将resources复制一份到同级目录，并命名为resources_${platform}，这样可以省去平台切换的时间(第一次执行仍然会比较耗时，但之后就会快很多了)"
        lock_release $lock_name
        exit 1
    fi

    lock_check $lock_name "拆分GameResources资源文件"
    logfile=/dev/stdout
    if $(in_cygwin); then
        logfile=${ROOT}/release/build_log.text
        INFO "日志保存在 ${logfile} 文件中"
    fi

    INFO "正在拆分 ${platform} 平台的资源库，路径: $res ..."
    $UNITY -batchmode -username linwenxuan@shiyue.com -password ysc666@123A -serial SC-GRWF-JSZB-2KGX-RJSF-62A3 -projectPath resources -executeMethod SubpackageTool.SplitFileCmd -CustomArgs:BuildTarget=${platform} -quit -nographics -logFile ${logfile}
    lock_release $lock_name

    INFO "拆分 ${platform} 平台的资源库完成"
}

DOC[split_resources_ios]="分解资源"
fun_split_resources_ios(){
    local platform=ios
    local lock_name=make_newres_$platform
    check_platform $platform

    if [[ "pc" == $platform || "mac" == $platform ]]; then
        local res=${ROOT}/resources
    else
        local res=${ROOT}/resources_${platform}
    fi

    if [[ ! -d $res ]]; then
        ERR "因为unity切换平台比较耗时，所以请将resources复制一份到同级目录，并命名为resources_${platform}，这样可以省去平台切换的时间(第一次执行仍然会比较耗时，但之后就会快很多了)"
        lock_release $lock_name
        exit 1
    fi

    lock_check $lock_name "拆分GameResources资源文件"
    logfile=/dev/stdout
    if $(in_cygwin); then
        logfile=${ROOT}/release/build_log.text
        INFO "日志保存在 ${logfile} 文件中"
    fi

    INFO "正在拆分 ${platform} 平台的资源库，路径: $res ..."
    $UNITY -batchmode -username linwenxuan@shiyue.com -password ysc666@123A -serial SC-GRWF-JSZB-2KGX-RJSF-62A3 -projectPath resources -executeMethod SubpackageBuilderIOS.SplitFile -CustomArgs:BuildTarget=${platform} -quit -nographics -logFile ${logfile}
    lock_release $lock_name

    INFO "拆分 ${platform} 平台的资源库完成"
}

DOC[rsync_effect]="同步特效资源库"
fun_rsync_effect(){
    local id=$1
    local lock_name=effect_lock
    local res=${ROOT}/resources
    # local res=${ROOT}/resources_mac
    local mapeditor=${ROOT}/../ysczg.dev_full/resources
    lock_check $lock_name "同步资源文件中"
    logfile=/dev/stdout
    if $(in_cygwin); then
        logfile=${ROOT}/release/rsync_log.text
        INFO "日志保存在 ${logfile} 文件中"
        ${res}/tail_log.sh $logfile &
        PID=$!
    fi

    INFO "正在同步特效资源库，路径: $res ..."
    $UNITY -batchmode -projectPath $mapeditor -executeMethod ExportResources.ExportTargetEffect -CustomArgs:effectid=${id} -quit -nographics -logFile ${logfile}
    $UNITY -batchmode -projectPath resources -importPackage ${mapeditor}/effect.unitypackage -quit -nographics -logFile ${logfile}
    lock_release $lock_name
    if [ -n "$PID" ]; then
        kill $PID
    fi

    INFO "同步特效资源库完成"
}

DOC[rsync_map]="同步地图资源库"
fun_rsync_map(){
    local id=$1
    local lock_name=map_lock
    local res=${ROOT}/resources
    # local res=${ROOT}/resources_mac
    local mapeditor=${ROOT}/../ysczg.dev_full/resources
    lock_check $lock_name "同步资源文件中"
    logfile=/dev/stdout
    if $(in_cygwin); then
        logfile=${ROOT}/release/rsync_log.text
        INFO "日志保存在 ${logfile} 文件中"
        ${res}/tail_log.sh $logfile &
        PID=$!
    fi

    INFO "正在同步地图资源库，路径: $res ..."
    $UNITY -batchmode -projectPath $mapeditor -executeMethod ExportResources.ExportTargetMap -CustomArgs:mapname=${id} -quit -nographics -logFile ${logfile}
    $UNITY -batchmode -projectPath resources -importPackage ${mapeditor}/map.unitypackage -quit -nographics -logFile ${logfile}
    # $UNITY -batchmode -projectPath resources -executeMethod LinerToGamme.GrassDataLinerToGamme -CustomArgs:mapname=${id} -quit -nographics -logFile ${logfile}
    lock_release $lock_name
    if [ -n "$PID" ]; then
        kill $PID
    fi

    INFO "同步地图资源库完成"
}

DOC[clean_release]="清空release下已经编译的资源文件"
fun_clean_release(){
    read -p "[93m=> 清空后需要比较长的重新编译时间，是否继续？[0;0m[y/n]" choice
    if [[ $choice != y ]]; then
        exit 0
    fi
    rm -rf ${ROOT}/release/pc
    rm -rf ${ROOT}/release/android
    rm -rf ${ROOT}/release/ios
    INFO "已清空release目录"
}
