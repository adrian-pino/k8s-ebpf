#/bin/bash
################################################
# Aim: Run iperf test varying MTU values [60, 1500]
################################################
IPERF_SERVER_IP=172.15.1.234
NODE_NAME=worker

# Iperf Clients: Kubernetes jobs
echo "Creating Kubernetes jobs that run Iperf test varying the MTU"
echo ""

# Create namespace 
kubectl create ns benchmarking

n_iteration=1
for i in 1500 1250 1000 750 500 250
do
    echo "Iteration $n_iteration: MTU: $i"
    cat <<- EOF | kubectl create -f -
    apiVersion: batch/v1
    kind: Job
    metadata:
      namespace: benchmarking
      name: iperf-client-mtu-$i
    spec:
      template:
        spec:
          containers:
          - name: iperf-client-mtu-$i
            image: adrianpino/ubuntu22.04-iperf
            command:
              - "/bin/bash"
              - "-c"
              - "iperf -c $IPERF_SERVER_IP -M $i -m"
          restartPolicy: Never
          nodeSelector:
            kubernetes.io/hostname: $NODE_NAME
EOF
sleep 20
n_iteration=$((n_iteration+1))
echo""
done

# Delete all the jobs
kubectl -n benchmarking delete job --all

# Delete namespace
kubectl delete ns benchmarking
