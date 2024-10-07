#!/bin/bash
#
# Common setup for all servers (Control Plane and Nodes)

set -euxo pipefail

# Kubernetes Variable Declaration
KUBERNETES_VERSION="v1.31"
KUBERNETES_INSTALL_VERSION="1.31"
CONTAINERD_VERSION="1.7.22"
RUNC_VERSION="1.1.14"
CNI_PLUGIN_VERSION="1.5.1"

# Disable swap
sudo swapoff -a

# Keeps the swap off during reboot
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
(crontab -l 2>/dev/null; echo "@reboot sudo /sbin/swapoff -a") | crontab - || true

# Create the .conf file to load the modules at bootup
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Sysctl params required by setup, params persist across reboots
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# Verify that the br_netfilter, overlay modules are loaded by running the following commands:
lsmod | grep br_netfilter
lsmod | grep overlay

# Verify that the net.bridge.bridge-nf-call-iptables, net.bridge.bridge-nf-call-ip6tables, and net.ipv4.ip_forward system variables are set to 1 in your sysctl config by running the following command:
sysctl net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables net.ipv4.ip_forward

# Install containerd container runtime
curl -LO https://github.com/containerd/containerd/releases/download/v$CONTAINERD_VERSION/containerd-$CONTAINERD_VERSION-linux-amd64.tar.gz
sudo tar Cxzvf /usr/local containerd-$CONTAINERD_VERSION-linux-amd64.tar.gz
curl -LO https://raw.githubusercontent.com/containerd/containerd/main/containerd.service
sudo mkdir -p /usr/local/lib/systemd/system/
sudo mv containerd.service /usr/local/lib/systemd/system/
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml
sudo systemctl daemon-reload
sudo systemctl enable --now containerd
#Check that containerd service is up and running
systemctl status containerd

# Install runc
curl -LO https://github.com/opencontainers/runc/releases/download/v$RUNC_VERSION/runc.amd64
sudo install -m 755 runc.amd64 /usr/local/sbin/runc

# Install cni plugin
curl -LO https://github.com/containernetworking/plugins/releases/download/v$CNI_PLUGIN_VERSION/cni-plugins-linux-amd64-v$CNI_PLUGIN_VERSION.tgz
sudo mkdir -p /opt/cni/bin
sudo tar Cxzvf /opt/cni/bin cni-plugins-linux-amd64-v$CNI_PLUGIN_VERSION.tgz

# Install kubelet, kubectl, and kubeadm
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg

curl -fsSL https://pkgs.k8s.io/core:/stable:/$KUBERNETES_VERSION/deb/Release.key |
    sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/$KUBERNETES_VERSION/deb/ /" |
    sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update -y
# sudo apt-get install -y kubelet="$KUBERNETES_INSTALL_VERSION" kubectl="$KUBERNETES_INSTALL_VERSION" kubeadm="$KUBERNETES_INSTALL_VERSION"
sudo apt-get install -y kubelet kubectl kubeadm

# Prevent automatic updates for kubelet, kubeadm, and kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# Configure crictl to work with containerd
sudo crictl config runtime-endpoint unix:///var/run/containerd/containerd.sock


# Install jq, a command-line JSON processor
sudo apt-get update -y
sudo apt-get install -y jq

# Retrieve the local IP address of the eth0 interface and set it for kubelet
local_ip="$(ip --json addr show eth0 | jq -r '.[0].addr_info[] | select(.family == "inet") | .local')"

# Write the local IP address to the kubelet default configuration file
echo KUBELET_EXTRA_ARGS=--node-ip=$local_ip | sudo tee /etc/default/kubelet

# Reboot system
sudo reboot

# Enable the kubelet service before running kubeadm:
sudo systemctl enable --now kubelet

# Restart kubelet and containerd
sudo systemctl restart kubelet
sudo systemctl restart containerd
