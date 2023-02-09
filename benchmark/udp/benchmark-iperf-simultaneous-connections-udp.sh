#!/bin/bash
################################################
# Aim: Run iperf test varying number of simultaneous connections [1, 10] (UDP)
################################################
# NODE_NAME_IPERF_SERVER=master
# NODE_NAME_IPERF_CLIENT=worker
NODE_NAME_IPERF_SERVER=$(kubectl get nodes --no-headers | grep -i control-plane |awk '{print $1}')
NODE_NAME_IPERF_CLIENT=$(kubectl get nodes --no-headers | grep -i none |awk '{print $1}')
OUTPUT_FILE="./udp-iperf-results-varying-number-simultaneous-connections.txt"

# 1) Deploy Iperf server
echo "----------------------------------------------------------------------------------------"
echo "Deploying an Iperf server listening for UDP connections"
echo "----------------------------------------------------------------------------------------"
echo ""
kubectl create ns benchmarking
sleep 2
cat <<EOF | kubectl create -f -
apiVersion: v1
kind: Pod
metadata:
  namespace: benchmarking
  name: iperf-server-udp
  labels:
    app: "iperf-server-udp"
spec:
  containers:
    - name: iperf-server
      image: adrianpino/ubuntu22.04-iperf
      command:
        - "/bin/bash"
        - "-c"
        - "iperf -s -u"
  nodeSelector:
    kubernetes.io/hostname: $NODE_NAME_IPERF_SERVER
EOF
echo ""
sleep 5

IPERF_SERVER_IP=$(kubectl -n benchmarking get pod iperf-server-udp -o wide --no-headers | awk '{print $6}')

# 2) Deploy Iperf Clients: Kubernetes jobs
echo "----------------------------------------------------------------------------------------"
echo "Creating Kubernetes jobs that run iperf test varying number of simultaneous connections (UDP mode)"
echo "----------------------------------------------------------------------------------------"
echo ""

for i in {1..10}
do
    echo "Iteration $i: Simultaneous connections: $i"
    kubectl create ns benchmarking-udp-$i
    # TODO: Create netpol
    cat <<- EOF | kubectl create -f -
    apiVersion: batch/v1
    kind: Job
    metadata:
      namespace: benchmarking-udp-$i
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
              - "iperf -c $IPERF_SERVER_IP -u -l 1472 -b 40G"
          restartPolicy: Never
          nodeSelector:
            kubernetes.io/hostname: $NODE_NAME_IPERF_CLIENT
EOF
# Sleep a bit so the current iteration is not affected by the next one. The average time of an iperf test is around 17sec.
sleep 20
done

# 3) Store logs
kubectl -n benchmarking logs iperf-server-udp >> $OUTPUT_FILE
echo ""
echo "[Throughput values stored in $OUTPUT_FILE"]
echo ""

# 4) Clean environment
# Delete jobs and namespace
for i in {1..10}
do
  # Delete all the jobs
  kubectl -n benchmarking-udp-$i delete job iperf-client-$i-simultaneous
  # Delete ns
  kubectl delete ns benchmarking-udp-$i
done

# Delete iperf server
kubectl -n benchmarking delete pod iperf-server-udp
kubectl delete ns benchmarking
