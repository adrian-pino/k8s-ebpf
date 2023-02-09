#!/bin/bash
################################################
# Aim: Run iperf test varying number of simultaneous connections [1, 10] (TCP)
################################################
# NODE_NAME_IPERF_SERVER=master
# NODE_NAME_IPERF_CLIENT=worker
# OUTPUT_FILE="./throughput-iperf-tcp-simultaneous.txt"

NODE_NAME_IPERF_SERVER=$(kubectl get nodes --no-headers | grep -i control-plane |awk '{print $1}')
NODE_NAME_IPERF_CLIENT=$(kubectl get nodes --no-headers | grep -i none |awk '{print $1}')

TIME=$(date | awk '{print $4}')
TIME_FORMATTED=${TIME//:/}
OUTPUT_FILE=$(echo throughput-iperf-tcp-simultaneous-$TIME_FORMATTED.txt)

# 1) Deploy Iperf server
echo "----------------------------------------------------------------------------------------"
echo "Deploying an Iperf server listening for TCP connections"
echo "----------------------------------------------------------------------------------------"
echo ""
kubectl create ns benchmarking
sleep 2
cat <<EOF | kubectl create -f -
apiVersion: v1
kind: Pod
metadata:
  namespace: benchmarking
  name: iperf-server-tcp
  labels:
    app: "iperf-server-tcp"
spec:
  containers:
    - name: iperf-server
      image: adrianpino/ubuntu22.04-iperf
      command:
        - "/bin/bash"
        - "-c"
        - "iperf -s"
  nodeSelector:
    kubernetes.io/hostname: $NODE_NAME_IPERF_SERVER
EOF
echo ""
sleep 5

IPERF_SERVER_IP=$(kubectl -n benchmarking get pod iperf-server-tcp -o wide --no-headers | awk '{print $6}')

# 2) Deploy Iperf Clients: Kubernetes jobs
echo "----------------------------------------------------------------------------------------"
echo "Creating Kubernetes jobs that run iperf test varying number of simultaneous connections (TCP mode)"
echo "----------------------------------------------------------------------------------------"
echo ""

for i in {1..10}
do
    echo "Iteration $i: Simultaneous connections: $i"
    kubectl create ns benchmarking-tcp-$i
    # TODO: Create netpol
    cat <<- EOF | kubectl create -f -
    apiVersion: batch/v1
    kind: Job
    metadata:
      namespace: benchmarking-tcp-$i
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
            kubernetes.io/hostname: $NODE_NAME_IPERF_CLIENT
EOF
# Sleep a bit so the current iteration is not affected by the next one. The average time of an iperf test is around 17sec.
sleep 20
# Store the results in a file
POD_NAMES=$(kubectl -n benchmarking-tcp-$i get pod --no-headers |awk '{print $1}')
for pod in $POD_NAMES
do
echo $i $(kubectl -n benchmarking-tcp-$i logs $pod | grep -i Bandwidth -A1 | grep -i 1 | awk '{print $7 " " $8}') >> $OUTPUT_FILE
done
done

# 3) Store logs
# Note: In the TCP tests we could obtain the results in a much clear way from the client itself
#       This means that the values are extracted from the different Kubernetes jobs (not the server)
# kubectl -n benchmarking logs iperf-server-tcp >> $OUTPUT_FILE
echo ""
echo "[Throughput values stored in $OUTPUT_FILE]"
echo ""

# 4) Clean environment
for i in {1..10}
do
  # Delete all the jobs
  kubectl -n benchmarking-tcp-$i delete job iperf-client-$i-simultaneous
  # Delete ns
  kubectl delete ns benchmarking-tcp-$i
done

# Delete iperf server
kubectl -n benchmarking delete pod iperf-server-tcp
kubectl delete ns benchmarking
