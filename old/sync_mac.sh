#!/bin/bash

PACKAGE_DIR="../ckbVersion"
PORT=8124
# 0x0000000000000000000000000000000000000000000000000000000000000000
assume_valid_target=""

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

if [ ! -f "env.txt" ]; then
    echo "env.txt，使用默认环境'mainnet'"
    echo "mainnet" >env.txt
    echo "2024-01-01" >>env.txt
fi

ckb_version=$(
    curl -s https://api.github.com/repos/nervosnetwork/ckb/releases |
        jq --arg vp "$version_prefix" -r '.[] | select(.tag_name | startswith($vp)) |
        {tag_name, published_at} | "\(.published_at) \(.tag_name)"' |
        sort |
        tail -n 1 |
        cut -d " " -f2
)
echo "Latest CKB version: $ckb_version"

# 从env中选取testnet或mainnet，以及写入当前日期到env.txt
env=$(sed -n '1p' env.txt)
day=$(TZ='Asia/Shanghai' date "+%Y-%m-%d")
start_day=$day
sed -i "" "2s/.*/$start_day/" env.txt

#拉取、解压ckb tar包
tar_name="ckb_${ckb_version}_aarch64-apple-darwin.zip"

if [ ! -f "$tar_name" ]; then
    wget -q "https://github.com/nervosnetwork/ckb/releases/download/${ckb_version}/${tar_name}"
fi

rm -rf ckb_*_aarch64-apple-darwin
unzip ${tar_name}
rm -f ${tar_name}

# 如果第一个参数不为空，则替换ckb二进制文件
if [ -n "$1" ]; then
    echo "替换ckb二进制文件为$1版本"
    cp -f ${PACKAGE_DIR}/$1/ckb ckb_${ckb_version}_aarch64-apple-darwin/ckb
fi
cd ckb_${ckb_version}_aarch64-apple-darwin

killckb

# 初始化节点
if [ -f "../result_${start_day}.log" ]; then
    # 如果文件存在，则删除文件
    rm -f ../result_${start_day}.log
    # 打印信息提示已删除
    echo "result_${start_day}.log已被删除"
fi
./ckb --version >../result_${start_day}.log
./ckb init --chain ${env}
echo "------------------------------------------------------------"
grep 'spec =' ckb.toml
grep 'spec =' ckb.toml | cut -d'/' -f2 | cut -d'.' -f1 >>../result_${start_day}.log

# 修改ckb.toml
grep "^listen_address =" ckb.toml
new_listen_address="0.0.0.0:${PORT}"
sed -i "" "s/^listen_address = .*/listen_address = \"$new_listen_address\"/" ckb.toml
grep "^listen_address =" ckb.toml

grep "^listen_addresses =" ckb.toml
sed -i "" "s|^listen_addresses = \[\"/ip4/0.0.0.0/tcp/[0-9]*\"\]|listen_addresses = [\"/ip4/0.0.0.0/tcp/$((PORT + 1))\"]|" ckb.toml
grep "^listen_addresses =" ckb.toml

grep "^modules =" ckb.toml
new_module="\"Indexer\""
sed -i "" "/^modules = .*/s/\]/, $new_module\]/" ckb.toml
grep "^modules =" ckb.toml

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

if [ -z "${assume_valid_target}" ]; then
    nohup ./ckb run >/dev/null 2>&1 &
    echo "assume-valid-target: [default](https://github.com/nervosnetwork/ckb/blob/develop/util/constant/src/default_assume_valid_target.rs)" >>../result_${start_day}.log
else
    nohup ./ckb run --assume-valid-target "$assume_valid_target" >/dev/null 2>&1 &
    echo "assume-valid-target: ${assume_valid_target}" >>../result_${start_day}.log
fi
echo "$(sysctl -n hw.ncpu)C$(($(sysctl -n hw.memsize) / 1024 / 1024 / 1024))G  macOS $(sw_vers -productVersion)  $(sysctl -n machdep.cpu.brand_string)" >>../result_${start_day}.log
sync_start=$(TZ='Asia/Shanghai' date "+%Y-%m-%d %H:%M:%S")
echo "sync_start: ${sync_start}" >>../result_${start_day}.log
