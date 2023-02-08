#/bin/bash
################################################
# Aim: Deploy an iperf server
################################################
NODE_NAME=master

# Iperf Server: Kubernetes pod
echo "Deploying an Iperf server"
echo ""

cat <<EOF | kubectl create -f -
apiVersion: v1
kind: Pod
metadata:
  name: iperf-server
  labels:
    app: "iperf-server"
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
EOF
