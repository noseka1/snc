#!/bin/bash

YQ=${YQ:-yq}
JQ=${JQ:-jq}

QEMU_IMG=${QEMU_IMG:-qemu-img}
VIRT_FILESYSTEMS=${VIRT_FILESYSTEMS:-virt-filesystems}
GUESTFISH=${GUESTFISH:-guestfish}

XMLLINT=${XMLLINT:-xmllint}

DIG=${DIG:-dig}
UNZIP=${UNZIP:-unzip}

ARCH=$(uname -m)


yq_ARCH=${ARCH}
# yq and install_config.yaml use amd64 as arch for x86_64
if [ "${ARCH}" == "x86_64" ]; then
    yq_ARCH="amd64"
fi

# Download yq/jq for manipulating in place yaml configs
if ! "${YQ}" -V; then
    if [[ ! -e yq ]]; then
        curl -L https://github.com/mikefarah/yq/releases/download/3.3.0/yq_linux_${yq_ARCH} -o yq
        chmod +x yq
    fi
    YQ=./yq
fi

if ! which ${JQ}; then
    sudo yum -y install /usr/bin/jq
fi

# Add virt-filesystems/guestfish/qemu-img
if ! which ${VIRT_FILESYSTEMS}; then
    sudo yum -y install /usr/bin/virt-filesystems
fi

if ! which ${GUESTFISH}; then
    sudo yum -y install /usr/bin/guestfish
fi

if ! which ${QEMU_IMG}; then
    sudo yum -y install /usr/bin/qemu-img
fi
# The CoreOS image uses an XFS filesystem
# Beware than if you are running on an el7 system, you won't be able
# to resize the crc VM XFS filesystem as it was created on el8
if ! rpm -q libguestfs-xfs; then
    sudo yum install libguestfs-xfs
fi


if ! which ${XMLLINT}; then
    sudo yum -y install /usr/bin/xmllint
fi

if ! which ${DIG}; then
    sudo yum -y install /usr/bin/dig
fi
if ! which ${UNZIP}; then
    sudo yum -y install /usr/bin/unzip
fi

function retry {
    local retries=10
    local count=0
    until "$@"; do
        exit=$?
        wait=$((2 ** $count))
        count=$(($count + 1))
        if [ $count -lt $retries ]; then
            echo "Retry $count/$retries exited $exit, retrying in $wait seconds..."
            sleep $wait
        else
            echo "Retry $count/$retries exited $exit, no more retries left."
            return $exit
        fi
    done
    return 0
}

function get_vm_prefix {
    local crc_vm_name=$1
    # This random_string is created by installer and added to each resource type,
    # in installer side also variable name is kept as `random_string`
    # so to maintain consistancy, we are also using random_string here.
    random_string=$(sudo virsh list --all | grep -oP "(?<=${crc_vm_name}-).*(?=-master-0)")
    if [ -z $random_string ]; then
        echo "Could not find virtual machine created by snc.sh"
        exit 1;
    fi
    echo ${crc_vm_name}-${random_string}
}

function shutdown_vm {
    local vm_prefix=$1
    sudo virsh shutdown ${vm_prefix}-master-0
    # Wait till instance started successfully
    until sudo virsh domstate ${vm_prefix}-master-0 | grep shut; do
        echo " ${vm_prefix}-master-0 still running"
        sleep 3
    done
}

function start_vm {
    local vm_prefix=$1
    sudo virsh start ${vm_prefix}-master-0
    # Wait till ssh connection available
    until ${SSH} core@api.${CRC_VM_NAME}.${BASE_DOMAIN} -- "exit 0" >/dev/null 2>&1; do
        echo " ${vm_prefix}-master-0 still booting"
        sleep 2
    done
}

# Restart the libvirt service after update
sudo systemctl restart libvirtd
