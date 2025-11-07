#!/bin/bash

kill_main_ckb() {
    PIDS=$(sudo lsof -ti:8114)
    for i in $PIDS; do
        echo "$(TZ='Asia/Shanghai' date "+%Y-%m-%d %H:%M:%S") killed the main ckb $i"
        sudo kill $i
    done
}

kill_test_ckb() {
    PIDS=$(sudo lsof -ti:8124)
    for i in $PIDS; do
        echo "$(TZ='Asia/Shanghai' date "+%Y-%m-%d %H:%M:%S") killed the test ckb $i"
        sudo kill $i
    done
}

kill_main_ckb
kill_test_ckb

cd mainnet_ckb_*_x86_64-unknown-linux-gnu || exit
sudo nohup ./ckb run >/dev/null 2>&1 &
cd ..

sleep 10

cd testnet_ckb_*_x86_64-unknown-linux-gnu || exit
sudo nohup ./ckb run >/dev/null 2>&1 &
cd ..
