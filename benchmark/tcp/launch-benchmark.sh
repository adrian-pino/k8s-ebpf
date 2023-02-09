#!/bin/bash
read -p "Please introduce the number of iterations: " number_iterations
for i in $(seq 1 $number_iterations)
do
        echo "=============================================================="
        echo "[TCP Benchmarking started. Iteration $i/$number_iterations ongoing]"
        echo "=============================================================="
        ./benchmark-iperf-simultaneous-connections-tcp.sh
done
