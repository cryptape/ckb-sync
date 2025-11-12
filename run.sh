#!/bin/bash

if [[ ! -f env.txt ]]; then
    echo "1" > env.txt
    echo "1" >> env.txt
    echo "[info] env.txt not found, created with default values:"
    cat env.txt
fi

mode=$(sed -n '1p' env.txt)
is_exec=$(sed -n '2p' env.txt)

current_time=$(TZ='Asia/Shanghai' date "+%Y-%m-%d %H:%M:%S")

if [[ "$is_exec" == "0" ]]; then
    echo "$current_time No restart for ckb in this test round"
    exit 0
fi

PORT_MAINNET=8114
PORT_TESTNET=8124

kill_main_ckb() {
	PIDS=$(sudo lsof -ti:${PORT_MAINNET})
	for i in $PIDS; do
		echo "$(TZ='Asia/Shanghai' date "+%Y-%m-%d %H:%M:%S") killed the main ckb $i"
		sudo kill $i
	done
}
kill_test_ckb() {
	PIDS=$(sudo lsof -ti:${PORT_TESTNET})
	for i in $PIDS; do
		echo "$(TZ='Asia/Shanghai' date "+%Y-%m-%d %H:%M:%S") killed the test ckb $i"
		sudo kill $i
	done
}

kill_test_ckb
kill_main_ckb

sleep 10

case "$mode" in
  1)
    echo "$current_time Run mode=1 → bash sync.sh main 0"
    bash sync.sh main 0
    ;;
  2)
    echo "$current_time Run mode=2 → bash sync.sh test 0"
    bash sync.sh test 0
    ;;
  3)
    echo "$current_time Run mode=3 → bash sync.sh main 1"
    bash sync.sh main 1
    ;;
  4)
    echo "$current_time Run mode=4 → bash sync.sh test 1"
    bash sync.sh test 1
    ;;
  *)
    echo "$current_time Invalid mode: $mode (should be 1~4)"
    exit 1
    ;;
esac

sed -i '2s/.*/0/' env.txt
echo "[info] Updated env.txt → set is_exec to 0"
