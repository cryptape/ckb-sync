#!/bin/bash

# 0x0000000000000000000000000000000000000000000000000000000000000000
mainnet_assume_valid_target=""
testnet_assume_valid_target=""

kill_main_ckb() {
    PIDS=$(sudo lsof -ti:8114)
    for i in $PIDS; do
        echo "$(TZ='Asia/Shanghai' date "+%Y-%m-%d %H:%M:%S") killed the main ckb $i"
        sudo kill $i
    done
}

kill_test_ckb() {
    PIDS=$(sudo lsof -ti:8115)
    for i in $PIDS; do
        echo "$(TZ='Asia/Shanghai' date "+%Y-%m-%d %H:%M:%S") killed the test ckb $i"
        sudo kill $i
    done
}

kill_main_ckb
kill_test_ckb

sleep 5

ckb_version=$(
    curl -s https://api.github.com/repos/nervosnetwork/ckb/releases |
        jq -r '.[] | select(.tag_name | startswith("v0.203")) |
        {tag_name, published_at} | "\(.published_at) \(.tag_name)"' |
        sort |
        tail -n 1 |
        cut -d " " -f2
)
echo "Latest CKB version: $ckb_version"
tar_name="ckb_${ckb_version}_x86_64-unknown-linux-gnu.tar.gz"

if [ ! -f "$tar_name" ]; then
    wget -q "https://github.com/nervosnetwork/ckb/releases/download/${ckb_version}/${tar_name}"
fi

sudo rm -rf testnet_ckb_*_x86_64-unknown-linux-gnu mainnet_ckb_*_x86_64-unknown-linux-gnu
tar xzf "${tar_name}"
rm -f "${tar_name}"
cp -r "ckb_${ckb_version}_x86_64-unknown-linux-gnu" "mainnet_ckb_${ckb_version}_x86_64-unknown-linux-gnu"
mv "ckb_${ckb_version}_x86_64-unknown-linux-gnu" "testnet_ckb_${ckb_version}_x86_64-unknown-linux-gnu"

start_day=$(TZ='Asia/Shanghai' date "+%Y-%m-%d")
result_log="result_${start_day}.log"

if [ -f "$result_log" ]; then
    # 如果文件存在，则删除文件
    rm -f "$result_log"
    # 打印信息提示已删除
    echo "$result_log已被删除"
fi
./"mainnet_ckb_${ckb_version}_x86_64-unknown-linux-gnu"/ckb --version >"$result_log"

# 修改mainnet ckb.toml
cd "mainnet_ckb_${ckb_version}_x86_64-unknown-linux-gnu" || exit
grep "^listen_address =" ckb.toml
new_listen_address="0.0.0.0:8114"
sed -i "s/^listen_address = .*/listen_address = \"$new_listen_address\"/" ckb.toml
grep "^listen_address =" ckb.toml

config_content="
[metrics.exporter.prometheus]
target = { type = \"prometheus\", listen_address = \"0.0.0.0:8100\" }

# # Experimental: Monitor memory changes.
[memory_tracker]
# # Seconds between checking the process, 0 is disable, default is 0.
interval = 5
"
echo "$config_content" >>ckb.toml
tail -n 8 ckb.toml
cd ..

# 修改testnet ckb.toml
cd "testnet_ckb_${ckb_version}_x86_64-unknown-linux-gnu" || exit
grep "^listen_address =" ckb.toml
new_listen_address="0.0.0.0:8115"
sed -i "s/^listen_address = .*/listen_address = \"$new_listen_address\"/" ckb.toml
grep "^listen_address =" ckb.toml

config_content="
[metrics.exporter.prometheus]
target = { type = \"prometheus\", listen_address = \"0.0.0.0:8102\" }

# # Experimental: Monitor memory changes.
[memory_tracker]
# # Seconds between checking the process, 0 is disable, default is 0.
interval = 5
"
echo "$config_content" >>ckb.toml
tail -n 8 ckb.toml
cd ..

echo "rich-indexer type: Not Enabled" >>"$result_log"

# 启动节点
if [ -z "${mainnet_assume_valid_target}" ]; then
    cd "mainnet_ckb_${ckb_version}_x86_64-unknown-linux-gnu" || exit
    sudo nohup ./ckb run >/dev/null 2>&1 &
    cd ..
    # https://github.com/nervosnetwork/ckb/blob/pkg/v0.203.0/util/constant/src/latest_assume_valid_target.rs
    echo "mainnet assume-valid-target: default" >>"$result_log"
else
    cd "mainnet_ckb_${ckb_version}_x86_64-unknown-linux-gnu" || exit
    sudo nohup ./ckb run --assume-valid-target "$mainnet_assume_valid_target" >/dev/null 2>&1 &
    cd ..
    echo "mainnet assume-valid-target: ${mainnet_assume_valid_target}" >>"$result_log"
fi

if [ -z "${testnet_assume_valid_target}" ]; then
    cd "testnet_ckb_${ckb_version}_x86_64-unknown-linux-gnu" || exit
    sudo nohup ./ckb run >/dev/null 2>&1 &
    cd ..
    echo "testnet assume-valid-target: default" >>"$result_log"
else
    cd "testnet_ckb_${ckb_version}_x86_64-unknown-linux-gnu" || exit
    sudo nohup ./ckb run --assume-valid-target "$testnet_assume_valid_target" >/dev/null 2>&1 &
    cd ..
    echo "testnet assume-valid-target: ${testnet_assume_valid_target}" >>"$result_log"
fi

echo "$(grep -c ^processor /proc/cpuinfo)C$(free -h | grep Mem | awk '{print $2}' | sed 's/Gi//')G    $(lsb_release -d | sed 's/Description:\s*//')    $(lscpu | grep "Model name" | cut -d ':' -f2 | xargs)" >>"$result_log"
sync_start=$(TZ='Asia/Shanghai' date "+%Y-%m-%d %H:%M:%S")
echo "sync_start: ${sync_start}" >>"$result_log"
