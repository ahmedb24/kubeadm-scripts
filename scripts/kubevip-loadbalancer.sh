#!/bin/bash
#
# Setup for kube-vip loadbalancer

set -euxo pipefail

# Set configuration details
export VIP=10.10.5.29
export INTERFACE=eth0
KVVERSION=v0.8.4

# Get latest version
# KVVERSION=$(curl -sL https://api.github.com/repos/kube-vip/kube-vip/releases | jq -r ".[0].name")

# Configure to use a container runtime
sudo ctr images pull ghcr.io/kube-vip/kube-vip:$KVVERSION
alias kube-vip="sudo ctr run --rm --net-host ghcr.io/kube-vip/kube-vip:$KVVERSION vip /kube-vip"
kube-vip manifest pod \
    --interface $INTERFACE \
    --vip $VIP \
    --controlplane \
    --arp \
    --leaderElection | sudo tee /etc/kubernetes/manifests/kube-vip.yaml
