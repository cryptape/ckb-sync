#!/bin/bash

PORT=8124

# 获取环境变量
env=$(sed -n '1p' env.txt)
start_day=$(sed -n '2p' env.txt)

# 获取localhost_hex_number
localhost_hex_height=$(curl -sS -X POST -H "Content-Type: application/json" -d '{"id": 1, "jsonrpc": "2.0", "method": "get_tip_header", "params": []}' http://localhost:${PORT} | jq -r '.result.number' | sed 's/^0x//')
if [[ $? -ne 0 || -z "$localhost_hex_height" ]]; then
    localhost_height="获取失败"
else
    localhost_height=$((16#$localhost_hex_height))
fi

indexer_tip_hex=$(curl -sS -X POST -H "Content-Type: application/json" -d '{"id": 1, "jsonrpc": "2.0", "method": "get_indexer_tip", "params": []}' http://localhost:${PORT} | jq -r '.result.block_number' | sed 's/^0x//')
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

# 计算本地和最新区块高度差值或指出无法计算
if [[ $localhost_height =~ ^[0-9]+$ && $latest_height =~ ^[0-9]+$ ]]; then
    difference=$(($latest_height - $localhost_height))
    if [[ $difference -lt 0 ]]; then
        difference=$((-$difference)) # 转换为绝对值
    fi
    sync_rate=$(echo "scale=10; $localhost_height * 100 / $latest_height" | bc | awk '{printf "%.2f\n", $0}')
    sync_rate="${sync_rate}%"
else
    difference="无法计算"
    sync_rate="无法计算"
fi

echo "$(TZ='Asia/Shanghai' date "+%Y-%m-%d %H:%M:%S") indexer_tip: ${indexer_tip} height: ${localhost_height} ${env}_height: ${latest_height} difference: ${difference}" sync_rate: ${sync_rate} >>diff_${start_day}.log

# 检查sync_end是否存在，并且差值小于总高度的1%
if ! grep -q "sync_end" result_${start_day}.log && [[ $difference =~ ^[0-9]+$ ]] && [[ $difference -lt 12000 ]]; then
    sync_end=$(TZ='Asia/Shanghai' date "+%Y-%m-%d %H:%M:%S")
    echo "sync_end: ${sync_end}（当前高度: $localhost_height, 当前indexer_tip: $indexer_tip)" >>result_${start_day}.log

    # 从日志文件中读取开始时间
    sync_start=$(grep 'sync_start' result_${start_day}.log | cut -d' ' -f2-)

    # 将时间转换为秒
    start_sec=$(date -j -f "%Y-%m-%d %H:%M:%S" "$sync_start" "+%s")
    end_sec=$(date -j -f "%Y-%m-%d %H:%M:%S" "$sync_end" "+%s")

    # 计算时间差
    diff_sec=$((end_sec - start_sec))

    # 转换为天、小时、分钟和秒
    days=$((diff_sec / 86400))
    hours=$(((diff_sec % 86400) / 3600))
    minutes=$(((diff_sec % 3600) / 60))
    seconds=$((diff_sec % 60))

    echo "同步到最新高度耗时: ${days}天 ${hours}小时 ${minutes}分钟 ${seconds}秒" >>result_${start_day}.log
fi

killckb() {
    PID=$(lsof -i :$PORT | grep 'ckb' | awk '{print $2}')
    if [ -z "$PID" ]; then
        echo "No ckb process to kill"
    else
        kill $PID
        if [ $? -eq 0 ]; then
            echo "Killed ckb PID: $PID"
        else
            echo "Failed to kill ckb PID: $PID"
        fi
    fi
}

# 检查是否存在sync_end且不存在kill_time
if grep -q "sync_end" result_${start_day}.log && ! grep -q "kill_time" result_${start_day}.log; then
    # 获取sync_end的Unix时间戳
    sync_end_time=$(grep 'sync_end' result_${start_day}.log | awk -F'sync_end: |（当前高度' '{print $2}')
    sync_end_timestamp_utc=$(date -u -j -f "%Y-%m-%d %H:%M:%S" "$sync_end_time" +%s)
    # 调整时区差异（减去8小时）
    sync_end_timestamp=$((sync_end_timestamp_utc - 8 * 3600))

    # 获取当前时间
    current_timestamp=$(TZ='Asia/Shanghai' date +%s)
    # 计算时间差（单位：秒）
    time_diff=$((current_timestamp - sync_end_timestamp))

    #获取同步开始时间戳
    sync_start_time=$(grep 'sync_start:' result_${start_day}.log | cut -d' ' -f2-)
    sync_start_timestamp_utc=$(date -u -j -f "%Y-%m-%d %H:%M:%S" "$sync_start_time" +%s)
    # 调整时区差异（减去8小时）
    sync_start_timestamp=$(((sync_start_timestamp_utc - 8 * 3600) * 1000))

    # 检查时间差是否超过4小时 (4小时 = 14400秒)
    if [[ $time_diff -ge 14400 ]]; then
        killckb
        echo "kill_time: $(TZ='Asia/Shanghai' date "+%Y-%m-%d %H:%M:%S")（当前高度: $localhost_height, 当前indexer_tip: $indexer_tip)" >>result_${start_day}.log
        source .env
        echo "详见: https://grafana-monitor.nervos.tech/d/cb7211b5-f4f4-4b5e-b1f9-bbf71a355818/test-scz?orgId=1&from=${sync_start_timestamp}&to=${current_timestamp}000" >>result_${start_day}.log

        python3 -m venv myenv
        source myenv/bin/activate
        pip install discord python-dotenv
        python3 sendMsg.py result_${start_day}.log
        deactivate
    fi
fi
