# How can I protect the OpenShift  image registry using Fusion Recipe



# Introduction 

OpenShift Container Platform provides a built in Container Image Registry which runs as a standard workload on the cluster. A registry is typically used as a publication target for images built on the cluster, as well as a source of images for workloads running on the cluster.

For more information:

https://www.redhat.com/en/blog/configure-the-openshift-image-registry-backed-by-openshift-container-storage

https://docs.openshift.com/container-platform/4.8/registry/configuring-registry-operator.html


In this page, we will take a look at how to backup and restore the OpenShift image registry.


## Registry Storage Requirements

A registry needs to have storage in order to store its contents. Image data is stored in two locations. The actual image data is stored in a configurable storage location such as 
1.	Cloud storage 	or 
2.	A filesystem volume.


## Registry Operator configuration settings
Let’s review the current Registry settings first. To do so, please run the command:

***Use case 1*** :  If cloud storage is configured
```
oc edit configs.imageregistry.operator.openshift.io/cluster
```

```
apiVersion: imageregistry.operator.openshift.io/v1
kind: Config
metadata:
  ...
  name: cluster
  ...
spec:
  ...
  storage:
    s3:
      bucket: cluster-image-registry-us-east-1
      encrypt: true
      keyID: ""
      region: us-east-1
      regionEndpoint: ""
...
```

In case the cluster is configured with the cloud storage, we need to back up the 
1.	secret/image-registry-private-configuration-user (which contains s3 credentials)
2.	configs.imageregistry.operator.openshift.io/cluster


As after the disaster when cluster is recovered, so we can restore these resources.

**Note**: When a cluster is created or recovered, the Image Registry Operator reconciles and creates the resources in the `openshift-image-registry` namespace. Therefore, please wait until the resource `configs.imageregistry.operator.openshift.io/cluster` is created before running the recipe.
Basically, we must override the configs.imageregistry.operator.openshift.io/cluster to get the original configuration.


***Follow below steps to backup/restore s3 base configuration:***

1. Label the secret i.e. secret/image-registry-private-configuration-user before running the recipe
```
oc label secret image-registry-private-configuration-user cutom-label=fusion
```
2. Create the policy from the Fusion UI 

3. Assign the policies to openshift-image-registry namespace . This will get assigned to the default recipe.

4. Apply the below recipe.
```
oc apply -f openshift-image-registry-with-s3-backup-restore.yaml
```
***[openshift-image-registry-with-s3-backup-restore.yaml](recipes/openshift-image-registry-with-s3-backup-restore.yaml)***

5. Patch the updated recipe.
```
oc get policyassignment -n ibm-spectrum-fusion-ns
```

```
oc -n ibm-spectrum-fusion-ns patch policyassignment <policy-assignment-name> --type merge -p '{"spec":{"recipe":{"name":"openshift-image-registry-with-s3-backup-restore-recipe", "namespace":"ibm-spectrum-fusion-ns"}}}'
```

6. Now we can take backup. 


***Use case 2*** :  If a filesystem volume is configured
```
oc edit configs.imageregistry.operator.openshift.io/cluster
```

```
apiVersion: imageregistry.operator.openshift.io/v1
kind: Config
metadata:
  ...
  name: cluster
  ...
spec:
  ...
  storage:
    managementState: Managed
    pvc:
      claim: image-registry-storage
...
```

In case the cluster is configured with a filesystem volume, we need to take a backup of the
1.	 PVC (Persistent Volume Claim) i.e. image-registry-storage
2.	configs.imageregistry.operator.openshift.io/cluster

which is used by the image registry.
This ensures that when a restore operation is performed, all the necessary data (i.e. images) will be present.


***Follow below steps to backup/restore volume configuration:***

1.	Follow steps 2 and 3 from use case 1.
2.	Apply the below recipe.
```
oc apply -f openshift-image-registry-with-pvc-backup-restore.yaml
```

***[openshift-image-registry-with-pvc-backup-restore.yaml](recipes/openshift-image-registry-with-pvc-backup-restore.yaml)***

3.	Patch the updated recipe.
```
oc get policyassignment -n ibm-spectrum-fusion-ns
```
```
oc -n ibm-spectrum-fusion-ns patch policyassignment <policy-assignment-name> --type merge -p '{"spec":{"recipe":{"name":"openshift-image-registry-with-pvc-backup-restore-recipe", "namespace":"ibm-spectrum-fusion-ns"}}}'
```

4.	Now we can take backup.
