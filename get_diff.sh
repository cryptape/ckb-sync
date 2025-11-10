#!/bin/bash

# 获取环境变量
current_day=$(TZ='Asia/Shanghai' date "+%Y-%m-%d")

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

# 获取mainnet的最新区块高度
latest_hex_height=$(curl -sS -X POST -H "Content-Type: application/json" -d '{"id": 1, "jsonrpc": "2.0", "method": "get_tip_header", "params": []}' https://mainnet.ckbapp.dev | jq -r '.result.number' | sed 's/^0x//')
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

if [[ "$localhost_height" != "获取失败" && "$indexer_tip" != "获取失败" ]]; then
	echo "$(TZ='Asia/Shanghai' date "+%Y-%m-%d %H:%M:%S") height: ${localhost_height} indexer_tip: ${indexer_tip} mainnet_height: ${latest_height} difference: ${difference} height_sync_rate: ${height_sync_rate} sync_rate: ${sync_rate}" >>"diff_${current_day}.log"
fi

# 获取testnet的最新区块高度
testnet_localhost_hex_height=$(curl -sS -X POST -H "Content-Type: application/json" -d '{"id": 1, "jsonrpc": "2.0", "method": "get_tip_header", "params": []}' http://localhost:8124 | jq -r '.result.number' | sed 's/^0x//')
if [[ $? -ne 0 || -z "$testnet_localhost_hex_height" ]]; then
	testnet_localhost_height="获取失败"
else
	testnet_localhost_height=$((16#$testnet_localhost_hex_height))
fi

testnet_indexer_tip_hex=$(curl -sS -X POST -H "Content-Type: application/json" -d '{"id": 1, "jsonrpc": "2.0", "method": "get_indexer_tip", "params": []}' http://localhost:8124 | jq -r '.result.block_number' | sed 's/^0x//')
if [[ $? -ne 0 || -z "$testnet_indexer_tip_hex" ]]; then
	testnet_indexer_tip="获取失败"
else
	testnet_indexer_tip=$((16#$testnet_indexer_tip_hex))
fi

# 获取mainnet或testnnet的最新区块高度
testnet_latest_hex_height=$(curl -sS -X POST -H "Content-Type: application/json" -d '{"id": 1, "jsonrpc": "2.0", "method": "get_tip_header", "params": []}' https://testnet.ckbapp.dev | jq -r '.result.number' | sed 's/^0x//')
if [[ $? -ne 0 || -z "$testnet_latest_hex_height" ]]; then
	testnet_latest_height="获取失败"
else
	testnet_latest_height=$((16#$testnet_latest_hex_height))
fi

if [[ $testnet_indexer_tip =~ ^[0-9]+$ && $testnet_latest_height =~ ^[0-9]+$ ]]; then
	difference=$(($testnet_latest_height - $testnet_indexer_tip))
	if [[ $difference -lt 0 ]]; then
		difference=$((-$difference))
	fi
	sync_rate=$(echo "scale=10; $testnet_indexer_tip * 100 / $testnet_latest_height" | bc | awk '{printf "%.2f\n", $0}')
	sync_rate="${sync_rate}%"
	height_sync_rate=$(echo "scale=10; $testnet_localhost_height * 100 / $testnet_latest_height" | bc | awk '{printf "%.2f\n", $0}')
	height_sync_rate="${height_sync_rate}%"

else
	difference="无法计算"
	sync_rate="无法计算"
fi

if [[ "$testnet_localhost_height" != "获取失败" && "$testnet_indexer_tip" != "获取失败" ]]; then
	echo "$(TZ='Asia/Shanghai' date "+%Y-%m-%d %H:%M:%S") height: ${testnet_localhost_height} indexer_tip: ${testnet_indexer_tip} testnet_height: ${testnet_latest_height} difference: ${difference} height_sync_rate: ${height_sync_rate} sync_rate: ${sync_rate}" >>diff_${current_day}.log
fi
