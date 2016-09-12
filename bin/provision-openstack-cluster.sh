#!/bin/bash

set -e

THIS_DIR=$(cd $(dirname $0); pwd) # absolute path
CONTRIB_DIR=$(dirname $THIS_DIR)
USER_DATA=$CONTRIB_DIR/coreos/user-data
KUBERNETES_MASTER_IP=192.168.111.31

SECGROUP=${SECGROUP:-kubernetes_security_group}
NETWORK=${NETWORK:-docker_internal_net}
NUM_INSTANCES=${NUM_INSTANCES:-3}
FLAVOR=${FLAVOR:-m1.small}

# COREOS_IMAGE_ID=
# KEYPAIR=

function echo_yellow {
  echo -e "\033[0;33m$1\033[0m"
}

function echo_red {
  echo -e "\033[0;31m$1\033[0m"
}

function echo_green {
  echo -e "\033[0;32m$1\033[0m"
}

if [ -z "$KEYPAIR" ]; then
  echo_red "ERROR: Keypair not set!"
  echo_yellow "Please make sure to run 'export KEYPAIR=xxx'"
  exit 1
fi

if [ -z "$COREOS_IMAGE_ID" ]; then
  echo_red "ERROR: CoreOS Image ID not set!"
  echo_yellow "Please make sure to run 'export COREOS_IMAGE_ID=xxx'"
  exit 1
fi

if ! which nova > /dev/null; then
  echo_red 'Please install nova and ensure it is in your $PATH .. '
  exit 1
fi

if nova net-list | grep -q $NETWORK &> /dev/null; then
  NETWORK_ID=$(nova net-list | grep $NETWORK | \
    awk -F'|' '{gsub(/ /, "", $0); print $2}')
else
  echo_yellow "Creating Kubernetes private network..."
  CIDR=${KUBERNETES_CIDR:-10.21.12.0/24}
  SUBNET_OPTIONS=""
  if [ ! -z "$KUBERNETES_DNS" ]; then
    SUBNET_OPTIONS=$(echo $KUBERNETES_DNS | \
      awk -F "," '{for (i=1; i<=NF; i++) printf "--dns-nameserver %s ", $i}')
  fi
  NETWORK_ID=$(nova net-create $NETWORK | \
    awk '{ printf "%s", ($2 == "id" ? $4 : "")}')
  echo "DBG: SUBNET_OPTIONS=$SUBNET_OPTIONS"
  SUBNET_ID=$(nova subnet-create \
    --name kubernetes_subnet \
    $SUBNET_OPTIONS \
    $NETWORK_ID $CIDR | awk '{ printf "%s", ($2 == "id" ? $4 : "")}')
fi

if ! nova secgroup-list | grep -q $SECGROUP &>/dev/null; then
  echo_yellow "Create Kubernetes Security Group .. "
  nova secgroup-create $SECGROUP 'Kubernetes Network' > /dev/null
  nova secgroup-add-group-rule $SECGROUP $SECGROUP icmp -1 -1  > /dev/null
  nova secgroup-add-group-rule $SECGROUP $SECGROUP tcp 1 65535  > /dev/null

  echo_yellow "Allow SSH to Kubernetes nodes .. "
  nova secgroup-add-rule $SECGROUP tcp 22 22 0.0.0.0/0  > /dev/null

  echo_yellow "Allow git push/pull from Kubernetes nodes .. "
  nova secgroup-add-rule $SECGROUP tcp 2222 2222 0.0.0.0/0  > /dev/null

  echo_yellow "Allow HTTP to Kubernetes nodes .. "
  nova secgroup-add-rule $SECGROUP tcp 80 80 0.0.0.0/0  > /dev/null

  echo_yellow "Allow ping to Kubernetes nodes .. "
  nova secgroup-add-rule $SECGROUP icmp -1 -1 0.0.0.0/0  > /dev/null
fi

echo_yellow "Provisioning Kubernetes Master node .. "
erb "$USER_DATA/kubernetes-master.yml.erb" \
  > "$USER_DATA/kubernetes-master.yml"
nova boot \
  --security-groups $SECGROUP \
  --user-data $USER_DATA/kubernetes-master.yml \
  --description 'Kubernetes Master' \
  --nic net-id=$NETWORK_ID \
  --image $COREOS_IMAGE_ID \
  --config-drive=true \
  --key-name $KEYPAIR \
  --flavor $FLAVOR \
  kubernetes-master > /dev/null

echo_yellow "Waiting for Kubernetes Master node IP .. "
while [ -z $KUBERNETES_MASTER_IP ]; do
  export KUBERNETES_MASTER_IP=$(nova show kubernetes-master | \
    grep $NETWORK | sed 's/,//'g | awk '{ print $5 }')
  sleep 3
done

echo_yellow "Provisioning Kubernetes Minion node .. "
erb "$USER_DATA/kubernetes-minion.yml.erb" \
  > "$USER_DATA/kubernetes-minion.yml"
nova boot \
  --security-groups $SECGROUP \
  --min-count $NUM_INSTANCES \
  --max-count $NUM_INSTANCES \
  --user-data $USER_DATA/kubernetes-minion.yml \
  --description 'Kubernetes Minion' \
  --nic net-id=$NETWORK_ID \
  --image $COREOS_IMAGE_ID \
  --config-drive=true \
  --key-name $KEYPAIR \
  --flavor $FLAVOR \
  kubernetes-minion > /dev/null

sleep 10

echo_yellow "Adding floating IPs .. "
nova add-floating-ip kubernetes-master 172.16.190.80
nova add-floating-ip kubernetes-minion-1 172.16.190.81
nova add-floating-ip kubernetes-minion-2 172.16.190.82
nova add-floating-ip kubernetes-minion-3 172.16.190.83

echo_green "Your Kubernetes cluster has successfully deployed to OpenStack."
