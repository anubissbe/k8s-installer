#!/bin/bash

# Master Node Installation Script for Kubernetes AI Cluster
# Run this script with sudo on Ubuntu 22.04.5 LTS

set -e

# Update and upgrade the system
apt update && apt upgrade -y

# Install essential tools
apt install -y apt-transport-https ca-certificates curl software-properties-common gnupg2

# Disable swap
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Load necessary kernel modules
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# Set up required sysctl params
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system

# Install containerd
apt install -y containerd
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

# Install Kubernetes components
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | tee /etc/apt/sources.list.d/kubernetes.list
apt update
apt install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

# Initialize the Kubernetes cluster (only on the first master node)
# Uncomment and modify the following line on the first master node
# kubeadm init --control-plane-endpoint "lb.telkom.be:6443" --upload-certs --pod-network-cidr=192.168.0.0/16

# Set up kubectl for the root user
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

# Install Calico network plugin (only on the first master node)
# Uncomment the following line on the first master node
# kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml

echo "Master node setup complete. If this is the first master node, please initialize the cluster with kubeadm init."
echo "If this is an additional master node, please join the cluster using the join command from the first master node."
