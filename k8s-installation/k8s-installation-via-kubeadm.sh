#!/bin/bash
#####################################################################################
# Script to install Kubernetes via kubeadm using containerd as the container runtime.
#####################################################################################
# If INSTALL_CILIUM_BPF=true, CNI Cilium in eBPF mode will be installed as well.

# VARIABLES
K8S_VERSION=1.26.0-00
MASTER_NODE_IP=10.10.0.11 # RINA Testbed inside NUC
# MASTER_NODE_IP=172.28.5.38 # OpenStack VM
POD_CIDR=172.15.0.0/16
INSTALL_CILIUM_BPF=false

# Differenciate between Master and Worker node.
while true; do
    read -p "Is this a master node? " yn
    case $yn in
        [Yy]* ) IS_MASTER=true; break;;
        [Nn]* ) IS_MASTER=false; break;;
        * ) echo "Please answer yes or no.";;
    esac
done

###############################
# CRI Installation: Containerd
###############################
# Load overlay & br_netfilter modules
sudo modprobe overlay
sudo modprobe br_netfilter
cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

# Configure systctl to persist
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

# Apply sysctl parameters
sudo sysctl --system

# Install containerd
# sudo apt-get update && sudo apt-get install -y containerd=1.3.3
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
sudo apt update
sudo apt install containerd.io

## Set the cgroup driver for runc to systemd
# Create the containerd configuration file (containerd by default takes the config looking
# at /etc/containerd/config.toml)
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/' /etc/containerd/config.toml
# sudo rm /etc/containerd/config.toml

# Restart containerd with the new configuration
sudo systemctl restart containerd

# disable swap
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

###############################
# Kubernetes installation
###############################
# Update the apt package index and install packages needed to use the Kubernetes apt repository
sudo apt-get update && sudo apt-get install -y apt-transport-https curl

# Download the Google Cloud public signing key
sudo curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
# Add the Kubernetes apt repository
echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list

# install kubelet, kubeadm and kubectl, and pin their version
sudo apt-get update
sudo apt-get install -y kubelet=$K8S_VERSION kubeadm=$K8S_VERSION kubectl=$K8S_VERSION
sudo apt-mark hold kubelet kubeadm kubectl

if $IS_MASTER; then
    # Initialize the cluster
    if $INSTALL_CILIUM_BPF; then
      # To use Cilium in eBPF mode, we install k8s without the kube-proxy
      sudo kubeadm init --apiserver-advertise-address=$MASTER_NODE_IP --pod-network-cidr=$POD_CIDR --skip-phases=addon/kube-proxy
    else
      # Default; install kube-proxy
      sudo kubeadm init --apiserver-advertise-address=$MASTER_NODE_IP --pod-network-cidr=$POD_CIDR
    fi

    # Once kubeadm has bootstraped the K8s cluster, set proper access to the cluster from the CP/master node
    mkdir -p "$HOME"/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config

    # Untaint master nodes
    kubectl taint nodes --all node-role.kubernetes.io/control-plane-
else
    echo "Do no forget to join the worker to the cluster!"
fi

# Note: I experienced an issue while trying to deploy a K8s cluster with nodes containing more than a NIC. In my case even
# specifying the interface (via kubeadm init --apiserver-advertise-address <>), pods where using the IP from a differnt interface, causing
# in some scenarios that the networking between master and worker was broken even though they are up & running.
# I believe that some CNIs such as Calico patch this issue somehow, but Cilium (v1.12.6) is not able to sorte it out automatically.

# Solution: Specify the worker's node IP manually in KUBELET.
if ! $IS_MASTER; then
    read -p "Has the device more than one NIC? (yes/no) " yn
    case $yn in
        [Yy]* )
            echo "Specify the IP of the worker node (In case of more than one, the one connected to the node network)";
            read WORKER_IP;
            echo 'Environment="KUBELET_EXTRA_ARGS=--node-ip='$WORKER_IP'"' | sudo tee -a /etc/systemd/system/kubelet.service.d/10-kubeadm.conf;
            sudo systemctl daemon-reload
            sudo systemctl restart kubelet
            break;;
        [Nn]* ) IS_MASTER=false; break;;
        * ) echo "Please answer yes or no.";;
    esac
fi

###########################
# CNI installation: Cilium
###########################
if ($IS_MASTER && $INSTALL_CILIUM_BPF); then
  # Download Helm
  curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
  chmod 700 get_helm.sh
  ./get_helm.sh

  # Install Cilium with eBPF mode (BPF HostPath and masquerading enabled)
  #
  # With this mode we avoid routing traffic via host stack (iptables). Instead
  # BPF takes care of the routing, which is significantly more efficient.
  # This implies that traffic will also bypass netfilter in the host namespace.

  helm repo add cilium https://helm.cilium.io/
  helm install cilium cilium/cilium \
      --namespace kube-system \
      --set ipam.mode=cluster-pool \
      --set ipam.operator.clusterPoolIPv4PodCIDRList=$POD_CIDR \
      --set kubeProxyReplacement=strict \
      --set bpf.masquerade=true \
      --set k8sServiceHost=$MASTER_NODE_IP \
      --set k8sServicePort=6443

  # Note: Here are listed the requirements to satisfy to run Cilium in such mode:
  # Requirements:
  # - Kernel >= 5.10
  # - Direct-routing configuration or tunneling
  # - eBPF-based kube-proxy replacement
  # - eBPF-based masquerading
  #
  # If any of the above requirements is not satisfied, Legacy Host Path will be configured.
fi
