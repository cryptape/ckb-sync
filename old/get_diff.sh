#!/bin/bash

# 获取环境变量
env=$(sed -n '1p' env.txt)
start_day=$(sed -n '2p' env.txt)
exec_type=$(sed -n '4p' env.txt)

localhost_hex_height=$(curl -sS -X POST -H "Content-Type: application/json" -d '{"id": 1, "jsonrpc": "2.0", "method": "get_tip_header", "params": []}' http://localhost:8114 | jq -r '.result.number' | sed 's/^0x//')
if [[ $? -ne 0 || -z "$localhost_hex_height" ]]; then
    localhost_height="获取失败"
else
    localhost_height=$((16#$localhost_hex_height))
fi

indexer_tip_hex=$(curl -sS -X POST -H "Content-Type: application/json" -d '{"id": 1, "jsonrpc": "2.0", "method": "get_indexer_tip", "params": []}' http://localhost:8114 | jq -r '.result.block_number' | sed 's/^0x//')
if [[ $? -ne 0 || -z "$indexer_tip_hex" ]]; then
    indexer_tip="获取失败"
else
    indexer_tip=$((16#$indexer_tip_hex))
fi

# 获取mainnet或testnnet的最新区块高度
latest_hex_height=$(curl -sS -X POST -H "Content-Type: application/json" -d '{"id": 1, "jsonrpc": "2.0", "method": "get_tip_header", "params": []}' https://${env}.ckbapp.dev | jq -r '.result.number' | sed 's/^0x//')
if [[ $? -ne 0 || -z "$latest_hex_height" ]]; then
    latest_height="获取失败"
else
    latest_height=$((16#$latest_hex_height))
fi

# 计算本地indexer_tip和最新区块高度差值或指出无法计算
if [[ $indexer_tip =~ ^[0-9]+$ && $latest_height =~ ^[0-9]+$ ]]; then
    difference=$(($latest_height - $indexer_tip))
    if [[ $difference -lt 0 ]]; then
        difference=$((-$difference)) # 转换为绝对值
    fi
    sync_rate=$(echo "scale=10; $indexer_tip * 100 / $latest_height" | bc | awk '{printf "%.2f\n", $0}')
    sync_rate="${sync_rate}%"
    height_sync_rate=$(echo "scale=10; $localhost_height * 100 / $latest_height" | bc | awk '{printf "%.2f\n", $0}')
    height_sync_rate="${height_sync_rate}%"

else
    difference="无法计算"
    sync_rate="无法计算"
fi

echo "$(TZ='Asia/Shanghai' date "+%Y-%m-%d %H:%M:%S") height: ${localhost_height} indexer_tip: ${indexer_tip} ${env}_height: ${latest_height} difference: ${difference} height_sync_rate: ${height_sync_rate} sync_rate: ${sync_rate}" >>diff_${start_day}.log

if [ "$exec_type" -eq 5 ] || [ "$exec_type" -eq 6 ]; then
    result_log="without_restart_result_${start_day}.log"
else
    result_log="result_${start_day}.log"
fi

# 检查sync_end是否存在，并且差值小于总高度的1%
if ! grep -q "sync_end" "$result_log" && [[ $difference =~ ^[0-9]+$ ]] && [[ $difference -lt 13000 ]]; then
    sync_end=$(TZ='Asia/Shanghai' date "+%Y-%m-%d %H:%M:%S")
    echo "sync_end: ${sync_end}（当前高度：$localhost_height,当前indexer_tip: $indexer_tip)" >>$result_log

    # 从日志文件中读取开始时间
    sync_start=$(grep 'sync_start' "$result_log" | cut -d' ' -f2-)

    # 将时间转换为秒
    start_sec=$(date -d "$sync_start" +%s)
    end_sec=$(date -d "$sync_end" +%s)

    # 计算时间差
    diff_sec=$((end_sec - start_sec))

    # 转换为天、小时、分钟和秒
    days=$((diff_sec / 86400))
    hours=$(((diff_sec % 86400) / 3600))
    minutes=$(((diff_sec % 3600) / 60))
    seconds=$((diff_sec % 60))

    echo "同步到最新indexer高度耗时: ${days}天 ${hours}小时 ${minutes}分钟 ${seconds}秒" >>"$result_log"

    if [ "$exec_type" = "1" ] || [ "$exec_type" = "2" ]; then
        head -n 3 "$result_log" >"tmp_$result_log"
        echo "" >>"tmp_$result_log"
        echo "indexer已同步到最新高度, 3小时后会kill掉ckb进程, 请及时查询。" >>"tmp_$result_log"
        python3 sendMsg.py "tmp_$result_log"
        rm -f "tmp_$result_log"
    fi

fi

killckb() {
    PIDS=$(sudo lsof -ti:8114)
    for i in $PIDS; do
        echo "$(TZ='Asia/Shanghai' date "+%Y-%m-%d %H:%M:%S") killed the ckb $i"
        sudo kill $i
    done
}

#toggle_env() {
#    local first_line=$(sed -n '1p' env.txt)
#    local fourth_line=$(sed -n '4p' env.txt)
#
#    # 根据第四行的值来更改第一行和第四行
#    if [ "$fourth_line" = "1" ]; then
#        sed -i "4s/.*/2/" env.txt
#        sed -i "1s/.*/mainnet/" env.txt
#    elif [ "$fourth_line" = "2" ]; then
#        sed -i "4s/.*/3/" env.txt
#        sed -i "1s/.*/mainnet/" env.txt
#    elif [ "$fourth_line" = "3" ]; then
#        sed -i "4s/.*/4/" env.txt
#        sed -i "1s/.*/testnet/" env.txt
#    elif [ "$fourth_line" = "4" ]; then
#        sed -i "4s/.*/1/" env.txt
#        sed -i "1s/.*/mainnet/" env.txt
#    else
#        echo "第四行不是1、2、3或4, 未做任何更改"
#    fi
#
#    # 无论如何都将第三行设置为1
#    sed -i "3s/.*/1/" env.txt
#}

toggle_env() {
    local fourth_line=$(sed -n '4p' env.txt)

    # 根据第四行的值来更改第一行和第四行
    if [ "$fourth_line" -eq 3 ]; then
        sed -i "4s/.*/4/" env.txt
        sed -i "1s/.*/testnet/" env.txt
    elif [ "$fourth_line" -eq 4 ]; then
        sed -i "4s/.*/5/" env.txt
        sed -i "1s/.*/mainnet/" env.txt
    elif [ "$fourth_line" -eq 5 ]; then
        sed -i "4s/.*/6/" env.txt
        sed -i "1s/.*/testnet/" env.txt
    elif [ "$fourth_line" -eq 6 ]; then
        sed -i "4s/.*/3/" env.txt
        sed -i "1s/.*/mainnet/" env.txt
    else
        echo "第四行不是3、4、5或6, 未做任何更改"
    fi

    # 无论如何都将第三行设置为1
    sed -i "3s/.*/1/" env.txt
}

# 检查是否存在sync_end且不存在kill_time
if grep -q "sync_end" "$result_log" && ! grep -q "kill_time" "$result_log"; then
    # 获取sync_end的Unix时间戳
    sync_end_time_str=$(grep 'sync_end' "$result_log" | awk -F'sync_end: |（当前高度' '{print $2}')
    sync_end_timestamp_utc=$(date -u -d "$sync_end_time_str" +%s)
    # 调整时区差异（减去8小时）
    sync_end_timestamp=$((sync_end_timestamp_utc - 8 * 3600))

    # 获取当前时间
    current_timestamp=$(TZ='Asia/Shanghai' date +%s)
    # 计算时间差（单位：秒）
    time_diff=$((current_timestamp - sync_end_timestamp))

    #    current_time=$(TZ='Asia/Shanghai' date "+%Y-%m-%d %H:%M:%S")
    #    echo "${current_time} current_timestamp: ${current_timestamp} sync_end_timestamp: ${sync_end_timestamp} time_diff: ${time_diff}"

    #获取同步开始时间戳
    sync_start_time=$(grep 'sync_start:' "$result_log" | cut -d' ' -f2-)
    sync_start_timestamp_utc=$(date -u -d "$sync_start_time" +%s)
    # 调整时区差异（减去8小时）
    sync_start_timestamp=$(((sync_start_timestamp_utc - 8 * 3600) * 1000))

    if [[ $time_diff -ge 10800 ]]; then
        # 调用killckb函数并记录kill_time
        killckb
        echo "kill_time: $(TZ='Asia/Shanghai' date "+%Y-%m-%d %H:%M:%S")（当前高度：$localhost_height,当前indexer_tip: $indexer_tip)" >>"$result_log"
        NODE_IP=$(curl ifconfig.me)
        echo "详见: https://grafana-monitor.nervos.tech/d/pThsj6xVz/test?orgId=1&var-url=$NODE_IP:8100&from=${sync_start_timestamp}&to=${current_timestamp}000" >>"$result_log"
        if [[ "$result_log" == without_restart_result* ]]; then
            python3 sendMsg.py "$result_log" .without_restart_env
        else
            python3 sendMsg.py "$result_log"
        fi
        toggle_env

        # replay逻辑
        if [ "${env}" = "mainnet" ]; then
            replay_height=15905888
        elif [ "${env}" = "testnet" ]; then
            replay_height=16861888
        else
            echo "Unknown environment: ${env}"
            exit 1
        fi

        ckb_version=$(sed -n '1p' "$result_log" | grep -oP 'ckb \K[^ ]+(?=\s*\()')
        #        if [[ "$ckb_version" == *"rc"* && ! "$ckb_version" =~ rc1$ ]]; then
        #            echo "$ckb_version contains 'rc' but does not end with 'rc1'. Exiting..." >>diff_${start_day}.log
        #            exit 0
        #        fi
        if [[ "$ckb_version" == *"rc"* || "$ckb_version" == *"pre"* ]]; then
            echo "$ckb_version contains 'rc' or 'pre'. Exiting..." >> "diff_${start_day}.log"
            exit 0
        fi

        sleep 60
        log_file="block_verifier_${ckb_version}_${env}.log"
        if [ ! -f "$log_file" ]; then
            sudo rm -rf ./replay
            mkdir replay
            cd "${env}"_ckb_*_x86_64-unknown-linux-gnu || exit
            nohup sudo ./ckb replay --tmp-target ../replay --profile 1 ${replay_height} | grep block_verifier >"../$log_file" 2>&1 &
            cd ..
        fi
    fi
fi
