#!/bin/bash

# 定义函数
killckb() {
    PROCESS=$(ps -ef | grep "ckb run" | grep -v grep | awk '{print $2}' | sed -n '2,10p')
    for i in $PROCESS; do
        echo "killed the ckb $i"
        sudo kill $i
    done
}

if [ ! -f "env.txt" ]; then
    echo "env.txt，使用默认环境'mainnet'"
    echo "mainnet" >env.txt
    echo "2024-01-01" >>env.txt
fi

if [ $# -eq 0 ]; then
    echo "请输入CKB版本号，如：bash sync_without_restart.sh 116"
    exit 1
else
    if [[ "$1" == "async" ]]; then
        version_prefix="v0.116.1" # 当第一个参数是async时，设置默认版本号
    else
        version_prefix="v0.$1"
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
fi

# 从env中选取testnet或mainnet，以及写入当前日期到env.txt
env=$(sed -n '1p' env.txt)
day=$(TZ='Asia/Shanghai' date "+%Y-%m-%d")
start_day=$day
sed -i "2s/.*/$start_day/" env.txt

#拉取、解压ckb tar包
tar_name="ckb_${ckb_version}_x86_64-unknown-linux-gnu.tar.gz"

if [ ! -f "$tar_name" ]; then
    wget -q "https://github.com/nervosnetwork/ckb/releases/download/${ckb_version}/${tar_name}"
fi

sudo rm -rf ckb_*_x86_64-unknown-linux-gnu
tar xzvf ${tar_name}
rm -f ${tar_name}
# 如果第一个参数是async，则替换ckb二进制文件
if [[ "$1" == "async" ]]; then
    echo "替换ckb二进制文件为async版本"
    sudo cp -f ckb-async-download/ckb ckb_${ckb_version}_x86_64-unknown-linux-gnu/ckb
fi
cd ckb_${ckb_version}_x86_64-unknown-linux-gnu

killckb

# 初始化节点
if [ -f "../result_${start_day}.log" ]; then
    # 如果文件存在，则删除文件
    rm -f ../result_${start_day}.log
    # 打印信息提示已删除
    echo "result_${start_day}.log已被删除"
fi
./ckb --version >../result_${start_day}.log
sudo ./ckb init --chain ${env} --force
echo "------------------------------------------------------------"
grep 'spec =' ckb.toml
grep 'spec =' ckb.toml | cut -d'/' -f2 | cut -d'.' -f1 >>../result_${start_day}.log

# 修改ckb.toml
grep "^listen_address =" ckb.toml
new_listen_address="0.0.0.0:8114"
sed -i "s/^listen_address = .*/listen_address = \"$new_listen_address\"/" ckb.toml
grep "^listen_address =" ckb.toml

grep "^modules =" ckb.toml
new_module="\"Indexer\""
sed -i "/^modules = .*/s/\]/, $new_module\]/" ckb.toml
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

if [ $# -eq 2 ] && [ "$2" == "rich" ]; then
    echo "Running with --rich-indexer"
    sudo nohup ./ckb run --rich-indexer >/dev/null 2>&1 &
else
    grep "^modules =" ckb.toml
    # new_module="\"Indexer\""
    # sed -i "/^modules = .*/s/\]/, $new_module\]/" ckb.toml
    # grep "^modules =" ckb.toml

    # 启动节点
    sudo nohup ./ckb run >/dev/null 2>&1 &
fi
echo "$(grep -c ^processor /proc/cpuinfo)C$(free -h | grep Mem | awk '{print $2}' | sed 's/Gi//')G" >>../result_${start_day}.log
echo "$(lsb_release -d | sed 's/Description:\s*//')" >>../result_${start_day}.log
sync_start=$(TZ='Asia/Shanghai' date "+%Y-%m-%d %H:%M:%S")
echo "sync_start: ${sync_start}" >>../result_${start_day}.log
