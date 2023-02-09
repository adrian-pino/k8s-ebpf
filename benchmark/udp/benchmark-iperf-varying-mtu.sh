#!/bin/bash
################################################
# Aim: Run iperf test varying MTU values [60, 1500]
################################################
# NODE_NAME_IPERF_SERVER=master
# NODE_NAME_IPERF_CLIENT=worker
NODE_NAME_IPERF_SERVER=$(kubectl get nodes --no-headers | grep -i control-plane |awk '{print $1}')
NODE_NAME_IPERF_CLIENT=$(kubectl get nodes --no-headers | grep -i none |awk '{print $1}')
OUTPUT_FILE="./udp-iperf-results-varying-mtu.txt"

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

# 2) Deploy Iperf server
echo "----------------------------------------------------------------------------------------"
echo "Deploying an Iperf server listening for UDP connections"
echo "----------------------------------------------------------------------------------------"
echo ""
kubectl create ns benchmarking
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
    kubernetes.io/hostname: $NODE_NAME_IPERF_CLIENT
EOF
echo ""
sleep 5

# 3) Deploy Iperf Clients: Kubernetes jobs
echo "----------------------------------------------------------------------------------------"
echo "Creating Kubernetes jobs that run Iperf test varying the payload size"
echo "----------------------------------------------------------------------------------------"
echo ""
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
n_iteration=$((n_iteration+1))
echo""
done

# 3) Store logs
kubectl -n benchmarking logs iperf-server-udp >> $OUTPUT_FILE
echo ""
echo "[Throughput values stored in $OUTPUT_FILE"]
echo ""

# 4) Clean environment
# Delete all the jobs
kubectl -n benchmarking-udp delete job --all
kubectl delete ns benchmarking-udp

# Delete iperf server
kubectl -n benchmarking delete pod iperf-server-udp
kubectl delete ns benchmarking

# Delete namespace
# kubectl delete benchmarking-udp
