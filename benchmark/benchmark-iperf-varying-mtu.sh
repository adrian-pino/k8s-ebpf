#/bin/bash
################################################
# Aim: Run iperf test varying MTU values [60, 1500]
################################################
NODE_NAME=worker
IPERF_SERVER_IP=$(kubectl -n benchmarking get pod iperf-server-udp -o wide --no-headers | awk '{print $6}')

# Iperf Clients: Kubernetes jobs
echo "----------------------------------------------------------------------------------------"
echo "Creating Kubernetes jobs that run Iperf test varying the payload size"
echo "----------------------------------------------------------------------------------------"
echo ""

# Create namespace
kubectl create ns benchmarking-udp
echo ""

n_iteration=1
for PAYLOAD_SIZE in 1500 1250 1000 750 500 250
do
    echo "Iteration $n_iteration: Payload size: $PAYLOAD_SIZE"
    cat <<- EOF | kubectl create -f -
    apiVersion: batch/v1
    kind: Job
    metadata:
      namespace: benchmarking-udp
      name: iperf-client-mtu-$PAYLOAD_SIZE
    spec:
      template:
        spec:
          containers:
          - name: iperf-client-mtu-$PAYLOAD_SIZE
            image: adrianpino/ubuntu22.04-iperf
            command:
              - "/bin/bash"
              - "-c"
              - "iperf -c $IPERF_SERVER_IP -u -l $PAYLOAD_SIZE -m"
          restartPolicy: Never
          nodeSelector:
            kubernetes.io/hostname: $NODE_NAME
EOF
sleep 20
# TODO: Output the throughput in a file
n_iteration=$((n_iteration+1))
echo""
done

# Delete all the jobs
kubectl -n benchmarking-udp delete job --all

# Delete namespace
kubectl delete ns benchmarking-udp
