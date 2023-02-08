#!/bin/bash
###########################################################################
# Cilium eBPF Installation and Tunning commands
###########################################################################
# Goal: Use K8s-based eBPF networking removing the need of iptables and kubeProxyReplacement

# Pre-requisite: install kubeadm without kube-kubeProxyReplacement
# kubeadm init --apiserver-advertise-address=$MASTER_IP --pod-network-cidr=$POD_CIDR --skip-phases=addon/kube-proxy

# If we need to create extra tokens
# kubeadm token create --print-join-command

# Download Helm
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

# Install Cilium
helm repo add cilium https://helm.cilium.io/

######################################################################
# Config 1: Cilium with eBPF mode (BPF HostPath and masquerading enabled)
######################################################################
# With this mode we avoid routing traffic via host stack (iptables). Instead
# BPF takes care of the routing, which is significantly more efficient.
# This has the implication that traffic will also bypass netfilter in the host namespace.

helm install cilium cilium/cilium \
    --namespace kube-system \
    --set ipam.mode=cluster-pool \
    --set ipam.operator.clusterPoolIPv4PodCIDRList=$POD_CIDR \
    --set kubeProxyReplacement=strict \
    --set bpf.masquerade=true \
    --set k8sServiceHost=$MASTER_IP \
    --set k8sServicePort=6443

# Issues:
# With this configuration we should have Cilium working with BPF-Host-routing & BPF-masquerading.
# However, from cilium status I could notice [Host Routing: Legacy] instead of [Host Routing: BPF]

# Note: Here are listed the requirements to satisfy to run Cilium in such mode:
# Requirements:
# - Kernel >= 5.10
# - Direct-routing configuration or tunneling
# - eBPF-based kube-proxy replacement
# - eBPF-based masquerading


######################################################################
# Config 2: Cilium in "Bypass iptables Connection Tracking" mode.
######################################################################
# For the case when eBPF Host-Routing is not working, (because we don't meet any of the requirements)
# the legacy host-routing will be activated (HostPath=Legacy) and thus
# network packets will still traverse the regular network stack in the host namespace,
# resulting in an signification cost addition by iptables. This traversal cost can be minimized by disabling
# the connection tracking requirement for all Pod traffic, thus bypassing the iptables connection tracker.
#
# To avoid iptables connection tracking we could use the flag "installNoConntrackIptablesRules=true"

# helm install cilium cilium/cilium --version 1.12.5 \
#   --namespace kube-system \
#   --set installNoConntrackIptablesRules=true \
#   --set kubeProxyReplacement=strict

# FYI:
# bpf.hostLegacyRouting=false (by default) with true force Cilium to use the Legacy
# Host routing, no matter if the BPF requirements are satisfied.

# Print iptables
# sudo iptables -L -v -n | more
