#!/bin/bash

# GPU Node Installation Script for Kubernetes AI Cluster
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
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list
chmod 644 /etc/apt/sources.list.d/kubernetes.list

apt update
apt install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

# Install NVIDIA drivers
apt install -y linux-headers-$(uname -r)
apt install -y nvidia-driver-470 nvidia-dkms-470

# Install NVIDIA Container Toolkit
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | tee /etc/apt/sources.list.d/nvidia-docker.list

apt update
apt install -y nvidia-docker2

# Restart containerd
systemctl restart containerd

# Set up local storage for AI workloads
mkdir -p /mnt/fast-local-storage

# Optimize kubelet configuration
cat <<EOF | tee /var/lib/kubelet/config.yaml
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
systemReserved:
  cpu: 1
  memory: 2Gi
kubeReserved:
  cpu: 1
  memory: 2Gi
evictionHard:
  memory.available: "1Gi"
  nodefs.available: "10%"
EOF

systemctl restart kubelet

echo "GPU node setup complete. Please join this node to the cluster using the join command from the master node."
