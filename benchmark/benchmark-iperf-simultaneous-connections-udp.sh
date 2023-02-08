#/bin/bash
################################################
# Aim: Run iperf test varying number of simultaneous connections [1, 10]
################################################
NODE_NAME=worker
OUTPUT_FILE="./udp-throughput-values.txt"
IPERF_SERVER_IP=$(kubectl -n benchmarking get pod iperf-server-udp -o wide --no-headers | awk '{print $6}')

# Iperf Clients: Kubernetes jobs
echo "----------------------------------------------------------------------------------------"
echo "Creating Kubernetes jobs that run iperf test varying number of simultaneous connections (UDP mode)"
echo "----------------------------------------------------------------------------------------"
echo ""

n_iteration=1
for i in 1 2 3 4 5 6 7 8 9 10
do
    echo "Iteration $n_iteration: Simultaneous connections: $i"
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
            kubernetes.io/hostname: $NODE_NAME
EOF
# Sleep a bit so the current iteration is not affected by the next one. The average time of an iperf test is around 17sec.
sleep 20
# Store the value (throughput) of this iteration on a file
POD_NAMES=$(kubectl -n benchmarking-udp-$i get pod --no-headers |awk '{print $1}')
for pod in $POD_NAMES
do
  echo "Nº of connections: $i" >> $OUTPUT_FILE
  echo $(kubectl -n benchmarking-udp-$i logs $pod | grep -i Bandwidth -A1 | grep -i 1 | awk '{print $7 " " $8}') >> $OUTPUT_FILE
done
n_iteration=$((n_iteration+1))
echo""
done

# Delete jobs and namespace
for i in 1 2 3 4 5 6 7 8 9 10
do
  # Delete all the jobs
  kubectl -n benchmarking-udp-$i delete job iperf-client-$i-simultaneous
  # Delete ns
  kubectl delete ns benchmarking-udp-$i
done
