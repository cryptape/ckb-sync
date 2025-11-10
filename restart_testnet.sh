#!/bin/bash

PORT=8124

kill_test_ckb() {
	PIDS=$(sudo lsof -ti:${PORT})
	for i in $PIDS; do
		echo "$(TZ='Asia/Shanghai' date "+%Y-%m-%d %H:%M:%S") killed the test ckb $i"
		sudo kill $i
	done
}

kill_test_ckb

cd testnet_ckb_*_x86_64-unknown-linux-gnu || exit
setsid -f ./ckb run >/dev/null 2>&1 &
