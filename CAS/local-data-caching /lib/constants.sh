#!/usr/bin/env bash

#========================================
# WARNING!
#========================================
#  This file contains values that are
#  considered internal to the project and
#  should not be changed by the user
#  unless they know what they're doing.
#========================================

#========================================
# OpenShift Configuration
#========================================
OCP_TARGET_VERSION="4.20.0"
OCP_TOLERATED_VERSION="4.18.0"
MARKETPLACE_NAMESPACE="openshift-marketplace"
CLUSTER_OCS_OPENSHIFT_IO="cluster.ocs.openshift.io"
EXPECTED_NODE_COUNT=3

#========================================
# Red Hat Catalog Configuration
#========================================
CATALOG_NAMESPACE="${MARKETPLACE_NAMESPACE}"
RH_CATALOG="redhat-operators"
LSO_PACKAGE="local-storage-operator"

#========================================
# ODF Configuration
#========================================
OCS_NAMESPACE="openshift-storage"
OCS_LOCAL_NAMESPACE="openshift-local-storage"
OCS_CLIENT_NAMESPACE="openshift-storage-client"
OCS_CLUSTER_NAME="ocs-storagecluster"
STORAGE_CLUSTER="storagecluster"

# StorageClass used by OCS to provision
# OSD PVs from the LocalStorageOperator
OCS_BACKING_STORAGECLASS="ocs-backing-lvs"

EXPOSE_RBD_DS_NAME="expose-ceph-rbd-block-devices"

# RBD CSI DaemonSet pod & container labels
RBD_POD_NEW_LABEL="app=openshift-storage.rbd.csi.ceph.com-nodeplugin"
RBD_POD_OLD_LABEL="app=csi-rbdplugin"
RBD_CONTAINER="csi-rbdplugin"
DEVICESET_LABEL="ceph.rook.io/DeviceSet"

#========================================
# Environment Types
#========================================
HCI_ENVIRONMENT="HCI"
SDS_ENVIRONMENT="SDS"

#========================================
# Fusion Operator Configuration
#========================================
FUSION_PACKAGE_NAME="isf-operator"
FUSION_MINIMUM_VERSION="2.12.0"
FUSION_SERVICE_INSTANCE_CR="fusionserviceinstances"
FUSION_SC="ibm-spectrum-fusion-mgmt-sc"
SPECTRUM_FUSION_CRD="spectrumfusion"
SPECTRUM_FUSION="spectrumfusion"

#========================================
# Fusion HCI Configuration
#========================================
HCI_FUSION_NAMESPACE="ibm-spectrum-fusion-ns"
APPLIANCE_INFO="appliance-info"

#========================================
# DF (Data Foundation) Configuration
#========================================
DF_CATALOG="isf-data-foundation-catalog"
DF_SERVICE_DEFINITION="data-foundation-service"
DF_SERVICE_NAME="odfmanager"

#========================================
# Spectrum Scale Configuration
#========================================
SCALE_SERVICE_NAME="scalemanager"
ISF_CNS_MANAGER="isf-cns-operator-controller-manager"
SCALE_SERVICE_DEFINITION="global-data-platform-remote-mount-service"
SCALE_CUSTOM_RESOURCE="clusters.scale.spectrum.ibm.com"
SCALE_INSTANCE="ibm-spectrum-scale"
SCALE_NAMESPACE="ibm-spectrum-scale"
SCALE_STORAGE_CLASS="ibm-spectrum-scale-sample"

#========================================
# IBM Catalog Configuration
#========================================
SOFTWARE_CATALOG="isf-operator-software-catalog"
HCI_CATALOG="isf-operator-catalog"
HCI_CATALOG_SUFFIX="linux.amd64"

#========================================
# IBM Container Registry
#========================================
IBM_OPEN_REGISTRY="icr.io"
IBM_OPEN_REGISTRY_NS="cpopen"

#========================================
# Scale Filesystem Default Values
#========================================
DEFAULT_FS_NAME="cache-fs"
DEFAULT_FS_SIZE="755Gi"

#========================================
# LOCAL_DISK_PVC Configuration
#========================================
LOCAL_DISK_PVC_ACCESS_MODE="ReadWriteMany"
LOCAL_DISK_PVC_STORAGE_CLASS="ocs-storagecluster-ceph-rbd"
LOCAL_DISK_PVC_VOLUME_MODE="Block"
NO_OF_RBD_PVCS=3

#========================================
# Retry and Timeout Configuration
#========================================
RETRY_COUNT=60
RETRY_INTERVAL=10
CATALOG_WAIT_TIMEOUT=300s
CSV_WAIT_TIMEOUT=600s
FUSION_SERVICE_RETRY_COUNT=90
STORAGE_CLUSTER_RETRY_COUNT=180
GDP_RETRY_INTERVAL=120
