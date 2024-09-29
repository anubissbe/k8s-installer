#!/bin/bash

# Load Balancer Installation Script for Kubernetes Cluster
# Run this script with sudo on Ubuntu 22.04.5 LTS

set -e

# Update and upgrade the system
apt update && apt upgrade -y

# Install HAProxy
apt install -y haproxy

# Backup the original HAProxy configuration
cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.bak

# Create a new HAProxy configuration
cat <<EOF > /etc/haproxy/haproxy.cfg
global
    log /dev/log    local0
    log /dev/log    local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    log     global
    mode    tcp
    option  tcplog
    option  dontlognull
    timeout connect 5000
    timeout client  50000
    timeout server  50000

frontend kubernetes
    bind *:6443
    option tcplog
    mode tcp
    default_backend kubernetes-master-nodes

backend kubernetes-master-nodes
    mode tcp
    balance roundrobin
    option tcp-check
    server kube1 192.168.1.31:6443 check fall 3 rise 2
    server kube2 192.168.1.32:6443 check fall 3 rise 2
    server kube3 192.168.1.33:6443 check fall 3 rise 2

listen stats
    bind *:9000
    mode http
    stats enable
    stats uri /stats
    stats realm Haproxy\ Statistics
    stats auth admin:admin  # Change this to a secure password
EOF

# Restart HAProxy to apply the new configuration
systemctl restart haproxy

# Enable HAProxy to start on boot
systemctl enable haproxy

# Open necessary ports
if command -v ufw > /dev/null; then
    ufw allow 6443/tcp
    ufw allow 9000/tcp
    ufw reload
fi

echo "Load balancer setup complete."
echo "HAProxy is configured to balance traffic on port 6443 across your Kubernetes master nodes."
echo "You can access HAProxy stats at http://lb_ip:9000/stats"
echo "Please ensure your master nodes are reachable at the IPs specified in the HAProxy configuration."
