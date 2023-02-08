#/bin/bash
################################################
# Aim: Deploy an iperf server
################################################
NODE_NAME=master

# Iperf Server: Kubernetes pod
echo "----------------------------------------------------------------------------------------"
echo "Deploying 2 Iperf servers, one listening TCP connections and the other listening UDP ones."
echo "----------------------------------------------------------------------------------------"
echo ""

kubectl create ns benchmarking

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
    kubernetes.io/hostname: $NODE_NAME
---
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
    kubernetes.io/hostname: $NODE_NAME
EOF
