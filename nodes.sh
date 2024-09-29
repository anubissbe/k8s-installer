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

# Kubernetes componenten installeren
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list
chmod 644 /etc/apt/sources.list.d/kubernetes.list

apt update
apt install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

# Controleer of dit de eerste master node is die geïnitialiseerd moet worden
if [ ! -f "/etc/kubernetes/admin.conf" ]; then
    echo "Dit lijkt de eerste master node te zijn. Voer het volgende commando uit om het cluster te initialiseren:"
    echo "sudo kubeadm init --control-plane-endpoint \"lb.telkom.be:6443\" --upload-certs --pod-network-cidr=192.168.0.0/16"
    echo "Na initialisatie, voer de volgende commando's uit:"
    echo "mkdir -p \$HOME/.kube"
    echo "sudo cp -i /etc/kubernetes/admin.conf \$HOME/.kube/config"
    echo "sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config"
    echo "kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml"
else
    # Als admin.conf al bestaat, configureer kubectl
    mkdir -p $HOME/.kube
    cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    chown $(id -u):$(id -g) $HOME/.kube/config
    echo "kubectl is geconfigureerd voor de huidige gebruiker."
fi

echo "Master node setup compleet."
echo "Als dit een extra master node is, gebruik dan het join commando van de eerste master node om toe te treden tot het cluster."
