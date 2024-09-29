# Geoptimaliseerde Kubernetes Cluster Gids voor AI Workloads

## Inleiding
Deze gids beschrijft het opzetten en optimaliseren van een Kubernetes cluster voor AI-workloads op Ubuntu 22.04.5 LTS. Alle servers zijn headless, dus we zullen ons richten op command-line interfaces en remote toegang waar nodig.

## Cluster Overzicht
- Load Balancer: lb.telkom.be (192.168.1.30)
- Master Nodes: 
  - kube1.telkom.be (192.168.1.31)
  - kube2.telkom.be (192.168.1.32)
  - kube3.telkom.be (192.168.1.33)
- GPU Worker Nodes:
  - jarvis.telkom.be (192.168.1.25)
  - hal9000.telkom.be (192.168.1.34)

## Deel 1: Voorbereiding en Basis Setup

### 1.1 Systeem Voorbereiding (Alle Nodes)

Voer de volgende commando's uit op alle nodes:

```bash
# Update het systeem
sudo apt update && sudo apt upgrade -y

# Installeer essentiële tools
sudo apt install -y apt-transport-https ca-certificates curl software-properties-common gnupg2

# Schakel swap uit
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Laad de nodige kernel modules
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Stel de nodige sysctl parameters in
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system

# Installeer en configureer containerd
sudo apt install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd
```

### 1.2 Kubernetes Installatie (Alle Nodes)

Voer de volgende commando's uit op alle nodes:

```bash
# Voeg Kubernetes repository toe
sudo curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list

# Installeer Kubernetes componenten
sudo apt update
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
```

### 1.3 Load Balancer Setup (op lb.telkom.be)

Op de load balancer node:

```bash
# Installeer HAProxy
sudo apt install -y haproxy

# Configureer HAProxy
sudo tee /etc/haproxy/haproxy.cfg <<EOF
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
EOF

# Start en enable HAProxy
sudo systemctl restart haproxy
sudo systemctl enable haproxy
```

### 1.4 Initialiseer het Kubernetes Cluster (op kube1.telkom.be)

Op de eerste master node (kube1.telkom.be):

```bash
# Initialiseer het cluster
sudo kubeadm init --control-plane-endpoint "lb.telkom.be:6443" --upload-certs --pod-network-cidr=192.168.0.0/16

# Configureer kubectl voor de root gebruiker
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Bewaar de join commando's die kubeadm genereert voor later gebruik
```

### 1.5 Installeer Calico Netwerk Plugin (op kube1.telkom.be)

Op de eerste master node:

```bash
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml
```

# Geoptimaliseerde Kubernetes Cluster Gids voor AI Workloads - Deel 2

## 2. Cluster Uitbreiding en GPU Setup

### 2.1 Voeg Overige Master Nodes toe (op kube2.telkom.be en kube3.telkom.be)

Voer het volgende commando uit op kube2.telkom.be en kube3.telkom.be. Gebruik het control-plane join commando dat gegenereerd werd tijdens de initialisatie op kube1.telkom.be:

```bash
sudo kubeadm join lb.telkom.be:6443 --token <token> \
    --discovery-token-ca-cert-hash sha256:<hash> \
    --control-plane --certificate-key <certificate-key>
```

Na het joinen, voer op elke nieuwe master node uit:

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

### 2.2 Voeg Worker Nodes toe (op jarvis.telkom.be en hal9000.telkom.be)

Voer het worker join commando uit op jarvis.telkom.be en hal9000.telkom.be:

```bash
sudo kubeadm join lb.telkom.be:6443 --token <token> \
    --discovery-token-ca-cert-hash sha256:<hash>
```

### 2.3 Verifieer Cluster Status (op een master node)

```bash
kubectl get nodes
```

### 2.4 GPU Setup (op jarvis.telkom.be en hal9000.telkom.be)

Op beide GPU worker nodes:

```bash
# Installeer NVIDIA drivers
sudo apt install -y linux-headers-$(uname -r)
sudo apt install -y nvidia-driver-470 nvidia-dkms-470

# Installeer NVIDIA Container Toolkit
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | sudo tee /etc/apt/sources.list.d/nvidia-docker.list

sudo apt update
sudo apt install -y nvidia-docker2

# Herstart containerd
sudo systemctl restart containerd
```

### 2.5 Installeer NVIDIA Device Plugin (op een master node)

```bash
kubectl create -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.12.2/nvidia-device-plugin.yml
```

## 3. Cluster Optimalisatie voor AI Workloads

### 3.1 Resource Quota's en Limits (op een master node)

Creëer een namespace voor AI projecten:

```bash
kubectl create namespace ai-projects
```

Maak een bestand `ai-resource-quota.yaml`:

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: ai-compute-resources
  namespace: ai-projects
spec:
  hard:
    requests.cpu: "20"
    requests.memory: 100Gi
    requests.nvidia.com/gpu: "3"
    limits.cpu: "40"
    limits.memory: 200Gi
    limits.nvidia.com/gpu: "3"
```

Pas de quota toe:

```bash
kubectl apply -f ai-resource-quota.yaml
```

### 3.2 Node Labeling voor AI Workloads (op een master node)

Label de GPU nodes:

```bash
kubectl label nodes jarvis.telkom.be nvidia.com/gpu=true
kubectl label nodes hal9000.telkom.be nvidia.com/gpu=true
```

### 3.3 Taint GPU Nodes (op een master node)

Taint de GPU nodes om te voorkomen dat niet-GPU workloads er per ongeluk op worden geplanned:

```bash
kubectl taint nodes jarvis.telkom.be nvidia.com/gpu=true:NoSchedule
kubectl taint nodes hal9000.telkom.be nvidia.com/gpu=true:NoSchedule
```

### 3.4 Optimaliseer Kubelet Configuratie (op jarvis.telkom.be en hal9000.telkom.be)

Op beide GPU worker nodes, pas `/var/lib/kubelet/config.yaml` aan:

```yaml
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
# ... andere bestaande configuraties ...
systemReserved:
  cpu: 1
  memory: 2Gi
kubeReserved:
  cpu: 1
  memory: 2Gi
evictionHard:
  memory.available: "1Gi"
  nodefs.available: "10%"
```

Herstart kubelet na de aanpassingen:

```bash
sudo systemctl restart kubelet
```

### 3.5 Configureer High-Performance Local Storage (op jarvis.telkom.be en hal9000.telkom.be)

Op beide GPU worker nodes:

```bash
sudo mkdir -p /mnt/fast-local-storage
```

Creëer een StorageClass voor local storage (op een master node). Maak een bestand `local-storage-class.yaml`:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-local-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
```

Pas toe:

```bash
kubectl apply -f local-storage-class.yaml
```

Creëer PersistentVolumes voor elke GPU node. Maak een bestand `local-pv-gpu.yaml`:

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: fast-local-storage-jarvis
spec:
  capacity:
    storage: 5Ti
  volumeMode: Filesystem
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: fast-local-storage
  local:
    path: /mnt/fast-local-storage
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - jarvis.telkom.be

---

apiVersion: v1
kind: PersistentVolume
metadata:
  name: fast-local-storage-hal9000
spec:
  capacity:
    storage: 500Gi
  volumeMode: Filesystem
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: fast-local-storage
  local:
    path: /mnt/fast-local-storage
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - hal9000.telkom.be
```

Pas toe:

```bash
kubectl apply -f local-pv-gpu.yaml
```

# Geoptimaliseerde Kubernetes Cluster Gids voor AI Workloads - Deel 3

## 4. Monitoring en Logging Setup

### 4.1 Installeer Helm (op een master node)

```bash
curl https://baltocdn.com/helm/signing.asc | sudo apt-key add -
echo "deb https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt update
sudo apt install helm
```

### 4.2 Installeer Prometheus en Grafana (op een master node)

```bash
# Voeg Prometheus Helm repository toe
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Maak een namespace voor monitoring
kubectl create namespace monitoring

# Installeer Prometheus stack
helm install prometheus prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --set grafana.adminPassword=your-secure-password \
    --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false
```

### 4.3 Configureer GPU Monitoring (op een master node)

Installeer de NVIDIA DCGM exporter:

```bash
helm repo add gpu-helm-charts https://nvidia.github.io/dcgm-exporter/helm-charts
helm repo update

helm install dcgm-exporter gpu-helm-charts/dcgm-exporter \
    --namespace monitoring
```

Creëer een ServiceMonitor voor de DCGM exporter. Maak een bestand `dcgm-servicemonitor.yaml`:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: dcgm-exporter
  namespace: monitoring
  labels:
    release: prometheus
spec:
  jobLabel: dcgm-exporter
  endpoints:
  - port: metrics
    interval: 15s
  selector:
    matchLabels:
      app: dcgm-exporter
  namespaceSelector:
    matchNames:
    - monitoring
```

Pas toe:

```bash
kubectl apply -f dcgm-servicemonitor.yaml
```

### 4.4 Configureer Logging (op een master node)

We gebruiken Fluentd voor logging. Installeer Fluentd:

```bash
kubectl create namespace logging

helm repo add fluent https://fluent.github.io/helm-charts
helm repo update

helm install fluentd fluent/fluentd \
    --namespace logging \
    --set persistence.enabled=true
```

## 5. Kubeflow Installatie

### 5.1 Installeer kfctl (op een master node)

```bash
wget https://github.com/kubeflow/kfctl/releases/download/v1.2.0/kfctl_v1.2.0-0-gbc038f9_linux.tar.gz
tar -xvf kfctl_v1.2.0-0-gbc038f9_linux.tar.gz
sudo mv kfctl /usr/local/bin
```

### 5.2 Deploy Kubeflow (op een master node)

```bash
export KF_NAME=my-kubeflow
export BASE_DIR=/opt/kubeflow
export KF_DIR=${BASE_DIR}/${KF_NAME}
export CONFIG_URI="https://raw.githubusercontent.com/kubeflow/manifests/v1.2-branch/kfdef/kfctl_k8s_istio.v1.2.0.yaml"

mkdir -p ${KF_DIR}
cd ${KF_DIR}
kfctl apply -V -f ${CONFIG_URI}
```

### 5.3 Verifieer Kubeflow Installatie

```bash
kubectl get pods -n kubeflow
```

## 6. Verdere Optimalisaties voor AI Workloads

### 6.1 Configureer Pod Priority en Preemption (op een master node)

Maak een PriorityClass voor AI workloads. Creëer een bestand `ai-priority-class.yaml`:

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: ai-workload-priority
value: 1000000
globalDefault: false
description: "Priority class for AI workloads"
```

Pas toe:

```bash
kubectl apply -f ai-priority-class.yaml
```

### 6.2 Configureer Horizontal Pod Autoscaler (op een master node)

Installeer de Metrics Server als die nog niet aanwezig is:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

Creëer een HPA voor een voorbeeld AI deployment. Maak een bestand `ai-hpa.yaml`:

```yaml
apiVersion: autoscaling/v2beta1
kind: HorizontalPodAutoscaler
metadata:
  name: ai-model-hpa
  namespace: ai-projects
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: ai-model-deployment
  minReplicas: 1
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      targetAverageUtilization: 50
```

Pas toe:

```bash
kubectl apply -f ai-hpa.yaml
```

### 6.3 Netwerkbeleid voor AI Workloads (op een master node)

Creëer een netwerkbeleid voor de AI namespace. Maak een bestand `ai-network-policy.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: ai-network-policy
  namespace: ai-projects
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ai-projects
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: ai-projects
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53
```

Pas toe:

```bash
kubectl apply -f ai-network-policy.yaml
```

### 6.4 Configureer Resource Requests en Limits voor AI Pods

Wanneer je AI workloads deployt, zorg ervoor dat je altijd resource requests en limits specificeert. Bijvoorbeeld:

```yaml
resources:
  requests:
    cpu: 4
    memory: 8Gi
    nvidia.com/gpu: 1
  limits:
    cpu: 8
    memory: 16Gi
    nvidia.com/gpu: 1
```

### 6.5 Optimaliseer etcd Performance (op alle master nodes)

Bewerk het bestand `/etc/kubernetes/manifests/etcd.yaml` op elke master node:

```yaml
spec:
  containers:
  - command:
    - etcd
    - --auto-compaction-retention=1
    # andere bestaande opties...
```

Dit zorgt voor automatische compactie van de etcd database elke 1 uur, wat de performance verbetert.

# Geoptimaliseerde Kubernetes Cluster Gids voor AI Workloads - Deel 4

## 7. Beveiliging

### 7.1 Implementeer Role-Based Access Control (RBAC) (op een master node)

Creëer een rol voor AI onderzoekers. Maak een bestand `ai-researcher-role.yaml`:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: ai-projects
  name: ai-researcher
rules:
- apiGroups: ["", "apps", "batch"]
  resources: ["pods", "jobs", "deployments"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: [""]
  resources: ["persistentvolumeclaims"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
```

Pas toe:

```bash
kubectl apply -f ai-researcher-role.yaml
```

### 7.2 Configureer Pod Security Policies (op een master node)

Maak een bestand `restricted-psp.yaml`:

```yaml
apiVersion: policy/v1beta1
kind: PodSecurityPolicy
metadata:
  name: restricted
spec:
  privileged: false
  seLinux:
    rule: RunAsAny
  supplementalGroups:
    rule: RunAsAny
  runAsUser:
    rule: MustRunAsNonRoot
  fsGroup:
    rule: RunAsAny
  volumes:
  - 'configMap'
  - 'emptyDir'
  - 'projected'
  - 'secret'
  - 'downwardAPI'
  - 'persistentVolumeClaim'
```

Pas toe:

```bash
kubectl apply -f restricted-psp.yaml
```

### 7.3 Beveilig etcd (op alle master nodes)

Configureer etcd om data-at-rest encryptie te gebruiken. Bewerk `/etc/kubernetes/manifests/etcd.yaml`:

```yaml
spec:
  containers:
  - command:
    - etcd
    - --encrypt-at-rest
    - --encryption-provider-config=/etc/kubernetes/etcd/encryption-config.yaml
    # andere bestaande opties...
    volumeMounts:
    - mountPath: /etc/kubernetes/etcd
      name: etcd-certs
  volumes:
  - hostPath:
      path: /etc/kubernetes/etcd
      type: DirectoryOrCreate
    name: etcd-certs
```

Creëer een encryptie configuratiebestand `/etc/kubernetes/etcd/encryption-config.yaml`:

```yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
    - secrets
    providers:
    - aescbc:
        keys:
        - name: key1
          secret: <base64-encoded-32-byte-secret>
    - identity: {}
```

### 7.4 Implementeer Network Policies voor Systeemnamespaces (op een master node)

Maak een bestand `system-netpol.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-from-other-namespaces
  namespace: kube-system
spec:
  podSelector:
    matchLabels:
  ingress:
  - from:
    - podSelector: {}
```

Pas toe:

```bash
kubectl apply -f system-netpol.yaml
```

## 8. Backup en Herstel Procedures

### 8.1 Installeer Velero (op een master node)

```bash
wget https://github.com/vmware-tanzu/velero/releases/download/v1.6.0/velero-v1.6.0-linux-amd64.tar.gz
tar -xvf velero-v1.6.0-linux-amd64.tar.gz
sudo mv velero-v1.6.0-linux-amd64/velero /usr/local/bin/

# Configureer een storage provider (bijvoorbeeld MinIO)
kubectl apply -f https://raw.githubusercontent.com/vmware-tanzu/velero/main/examples/minio/00-minio-deployment.yaml

# Installeer Velero in het cluster
velero install \
    --provider aws \
    --plugins velero/velero-plugin-for-aws:v1.2.0 \
    --bucket velero \
    --secret-file ./credentials-velero \
    --use-volume-snapshots=false \
    --backup-location-config region=minio,s3ForcePathStyle="true",s3Url=http://minio.velero.svc:9000
```

### 8.2 Configureer Regelmatige Backups

Stel een dagelijkse backup in:

```bash
velero schedule create daily-cluster-backup --schedule="0 1 * * *"
```

### 8.3 Test Backup en Herstel

Maak een handmatige backup:

```bash
velero backup create test-backup --include-namespaces ai-projects
```

Test het herstelproces:

```bash
velero restore create --from-backup test-backup
```

## 9. Onderhoud en Best Practices

### 9.1 Automatische Updates (op alle nodes)

Configureer unattended-upgrades voor automatische beveiligingsupdates:

```bash
sudo apt install unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades
```

### 9.2 Monitoring en Logging Best Practices

- Stel alerting rules in Prometheus in voor kritieke metrics:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: ai-cluster-alerts
  namespace: monitoring
spec:
  groups:
  - name: ai-cluster-alerts
    rules:
    - alert: HighGPUUsage
      expr: nvidia_gpu_utilization > 90
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: "High GPU usage detected"
        description: "GPU usage is over 90% for more than 10 minutes"
```

- Implementeer log rotatie om schijfruimte te besparen. Bewerk de Fluentd configuratie:

```
<match **>
  @type file
  path /var/log/fluent/myapp
  time_slice_format %Y%m%d
  time_slice_wait 10m
  time_keep_days 5
  compress gzip
</match>
```

### 9.3 Regelmatige Audits

- Voer regelmatig security audits uit met kube-bench:

```bash
kubectl apply -f https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job.yaml
```

- Review RBAC policies regelmatig:

```bash
kubectl auth can-i --list --namespace=ai-projects
```

### 9.4 Performance Tuning

- Optimaliseer kubelet configuratie voor GPU nodes. In `/var/lib/kubelet/config.yaml`:

```yaml
kubeReserved:
  cpu: 1
  memory: 2Gi
  ephemeral-storage: 1Gi
systemReserved:
  cpu: 1
  memory: 2Gi
  ephemeral-storage: 1Gi
```

- Gebruik node anti-affinity om AI workloads te spreiden:

```yaml
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        labelSelector:
          matchExpressions:
          - key: app
            operator: In
            values:
            - ai-workload
        topologyKey: kubernetes.io/hostname
```

### 9.5 Documentatie en Kennisdeling

- Houd een up-to-date runbook bij voor veelvoorkomende operaties en troubleshooting
- Organiseer regelmatige kennisdelingssessies voor het team
- Documenteer alle custom configuraties en optimalisaties in een centraal wiki of repository

## Conclusie

Deze gids heeft je door het proces geleid van het opzetten, optimaliseren en onderhouden van een Kubernetes cluster specifiek voor AI-workloads. Door deze best practices te volgen, heb je een robuuste, efficiënte en veilige omgeving gecreëerd voor het uitvoeren van AI en machine learning taken.

Vergeet niet dat Kubernetes en de gerelateerde technologieën snel evolueren. Het is belangrijk om regelmatig de documentatie van de gebruikte tools te raadplegen en je cluster bij te werken naar de nieuwste stabiele versies om optimale prestaties en beveiliging te garanderen.
