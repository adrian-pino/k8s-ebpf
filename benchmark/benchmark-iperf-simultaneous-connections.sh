#/bin/bash
################################################
# Aim: Run iperf test varying number of simultaneous connections [1, 10]
################################################
IPERF_SERVER_IP=172.15.1.234
NODE_NAME=worker

# Iperf Clients: Kubernetes jobs
echo "Creating Kubernetes jobs that run iperf test varying number of simultaneous connections"
echo ""

n_iteration=1
for i in 1 2 3 4 5 6 7 8 9 10
do
    echo "Iteration $n_iteration: Simultaneous connections: $i"
    cat <<- EOF | kubectl create -f -
    apiVersion: batch/v1
    kind: Job
    metadata:
      namespace: benchmarking-$i
      name: iperf-client-$i-simultaneous
    spec:
      parallelism: $i
      completions: $i
      template:
        spec:
          containers:
          - name: iperf-client-$i-simultaneous
            image: adrianpino/ubuntu22.04-iperf
            command:
              - "/bin/bash"
              - "-c"
              - "iperf -c $IPERF_SERVER_IP"
          restartPolicy: Never
          nodeSelector:
            kubernetes.io/hostname: $NODE_NAME
EOF
sleep 20
n_iteration=$((n_iteration+1))
echo""
done

# Delete jobs and namespace
for i in 1 2 3 4 5 6 7 8 9 10
do
  # Delete all the jobs
  kubectl -n benchmarking-$i
  # Delete ns
  kubectl delete ns benchmarking-$i
done
