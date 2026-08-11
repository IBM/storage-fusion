# Using Maximo Fusion Recipes
For Maximo Application Suite 9.1.x, Fusion based backup and restore leverages Fusion dynamic recipes, using a single parent recipe to discover and execute workflows contained within child recipes.
Maximo application suite is deployed in multiple namespaces (`sls`, `core`, `manage`, ...), therefore, there are child recipes for each application.

For additional information on Fusion Backup & Restore dynamic recipes, refer to the [documentation](https://www.ibm.com/docs/en/fusion-software/2.13.0?topic=recipe-dynamic).

For detailed Maximo suite backup and restored procedures, refer to the [documentation](https://www.ibm.com/docs/en/mas-cd/continuous-delivery?topic=administering-backing-up-restoring-maximo-application-suite).

## High level description of Maximo application suite backup and restore procedure

**Backup:**
- Run the backup pre-requisite scripts for each installed MAS service component.
   - Labels specific Maximo resources for backup/restore flow.
   - Creates a local customized version of the correlating Maximo component Fusion child recipe.
   - Adds RBAC permissions for the Fusion Backup & Restore transaction manager to access and backup specific Maximo resources.
- Create (apply) the Fusion parent and child recipes for the Maximo instance.
- Prepare Fusion for backup by creating required resources, such as backup storage location, policy, and policy assignment.
   - For the Fusion policy assignment, add the Maximo parent recipe reference.
- At this point, Fusion will backup Maximo based on the Fusion backup policy schedule.
   - You can also perform a backup now by initiating an on-demand backup, to help test and validate the environment is set up correctly.

**Restore:**
- For the target restore cluster, run the restore pre-requisite scripts for each installed MAS service component
   - Adds RBAC permissions for the Fusion Backup & Restore transaction manager to restore (create) specific Maximo resources.
- Prepare target cluster for restore
   - For same cluster restore, cleanup the existing Maximo instance, so it can be restored.
   - For different cluster restore, prepare the Maximo resources that will not be restored, such as cert manager, DRO, catalogsource, grafana.
- From the Fusion console, restore the Maximo instance.

## Limitations
Fusion Backup and Restore operator requires AMQ-Streams operator for configuring Kafka cluster, if planning to configure Kafka with Maximo, it is not advised to install open source Strimzi operator as this could lead to potential issues between both operators. It is also recommended that you match the version of Fusion B/R AMQ-Streams operator to the one you are planning to use for Maximo, based on RedHat own recommendations https://access.redhat.com/solutions/7028595. 

----

## Support

- A version of IBM Fusion `2.12.1` or later should be installed.
- The current version of the recipes supports the following Maximo components:
    - mongodb
    - db2u
    - amq-streams
    - ibm-sls
    - mas-core
    - mas-manage
    - mas-iot
    - mas-monitor
    - mas-optimizer
    - mas-visual-inspection
    - mas-predict\*
    - mas-assist
    - mas-aiservice
    - mref

\**Predict is only supported for Backup and restore to the same cluster and only for scenarios where the Cloud Pak for Data instance is untouched.
Backing up and restoring Cloud Pak for Data deployed by Maximo is not supported.*


## Backup Prerequisites

1. Clone this repository to your local computer.

2. cd to `maximo/9.1.x`

3. Some recipes rely on variables that need to be set before appling the recipe. For these variables, edit the `maximo_env.sh` script to set these variables to make the necessary modifications according to your configuration. 

    ```
    source maximo_env.sh
    ```

4. Run the prerequisite scripts that apply to the Maximo instance. Some prerequisite scripts must always be run, while others depend on the deployed capabilities and databases. The prerequisite scripts that must be run regardless of the capabilities installed are: `ibm-sls`, `mas-core` and `mas-manage`. If the cluster hosts the databases as well, then `mongodb` and/or `db2u` should also be run, depending on the case at hand.


    - **mongodb**:
    
        ```
        mongodb/backup-pre-req-mongodb.sh
        ```
    
    - **db2u**:
    
        ```
        db2/backup-pre-req-db2.sh
        ```
    
    - **amq-streams**:

        ```
        amq-streams/backup-pre-req-amq-streams.sh
        ```

        *Applies if "monitor" or "predict" are deployed capabilities.*
    

    - **ibm-sls**:
    
        ```
        sls/backup-pre-req-sls.sh
        ```
    
    - **mas-core**:
    
        ```
        core/backup-pre-req-core.sh
        ```
    
    - **mas-manage**:
    
        ```
        manage/backup-pre-req-manage.sh
        ```
    
    - **mas-iot**:

    
        ```
        iot/backup-pre-req-iot.sh
        ```
    
    - **mas-monitor**:
    
        ```
        monitor/backup-pre-req-monitor.sh
        ```
    
    - **mas-optimizer**:
    
        ```
        optimizer/backup-pre-req-optimizer.sh
        ```
    
    - **mas-visual-inspection**:
    
        ```
        visual-inspection/backup-pre-req-visual-inspection.sh
        ```
    
    - **mas-predict**\*:
    
        ```
        predict/backup-pre-req-predict.sh
        ```
    
    - **mas-assist**:
    
        ```
        assist/backup-pre-req-assist.sh
        ```
    
    - **mas-aiservice**:
    
        ```
        aiservice/backup-pre-req-aiservice.sh
        ```
    
    - **mref**:
    
        ```
        mref/backup-pre-req-mref.sh
        ```

\**Predict is only supported for Backup and restore to the same cluster and only for scenarios where the Cloud Pak for Data instance is untouched.
Backing up and restoring Cloud Pak for Data deployed by Maximo is not supported.*

## Backup

1. Verify that the Fusion namespace environment variable `$ISF_NAMESPACE` is set. This variable should have been set when you ran `source maximo_env.sh`.
   - Validate it is set: `echo $ISF_NAMESPACE`
   - Set again, if required (default Fusion namespace is `ibm-spectrum-fusion-ns`): `export ISF_NAMESPACE=<fusion-namespace>`

1. Apply parent recipe

    ```
    oc -n $ISF_NAMESPACE apply -f maximo-parent-backup-restore.yaml
    ```

1. Apply the local child recipe (frcpe) generated by the backup-pre-req script for each application that is installed.

    *Note: In the previous section "Backup Prerequisites", it was indicated which prerequisite scripts must always be run (`ibm-sls`, `mas-core`, and `mas-manage`) and which depend on deployed capabilities and databases (`db2u` and `mongodb`).*


    - **mongodb**:
    
        ```
        oc -n $ISF_NAMESPACE apply -f mongodb/maximo-child-mongodb-backup-restore-local.yaml
        ```
      
    - **db2u**:
    
    
        ```
        oc -n $ISF_NAMESPACE apply -f db2/maximo-child-db2-backup-restore-local.yaml
        ```
    
    - **amq-streams**:
    
    
        ```
        oc -n $ISF_NAMESPACE apply -f amq-streams/maximo-child-amq-streams-backup-restore-local.yaml
        ```

        *Applies if "monitor" or "predict" are deployed capabilities.*
    
    
    - **ibm-sls**:
    
    
        ```
        oc -n $ISF_NAMESPACE apply -f sls/maximo-child-sls-backup-restore-local.yaml
        ```
    
    - **mas-core**:
    
    
        ```
        oc -n $ISF_NAMESPACE apply -f core/maximo-child-core-backup-restore-local.yaml
        ```
    
    - **mas-manage**:
    
    
        ```
        oc -n $ISF_NAMESPACE apply -f manage/maximo-child-manage-backup-restore-local.yaml
        ```
    
    - **mas-iot**:
    
    
        ```
        oc -n $ISF_NAMESPACE apply -f iot/maximo-child-iot-backup-restore-local.yaml
        ```
    
    - **mas-monitor**:
    
    
        ```
        oc -n $ISF_NAMESPACE apply -f monitor/maximo-child-monitor-backup-restore-local.yaml
        ```
    
    - **mas-optimizer**:
    
    
        ```
        oc -n $ISF_NAMESPACE apply -f optimizer/maximo-child-optimizer-backup-restore-local.yaml
        ```
    
    - **visual-inspection**:
    
    
        ```
        oc -n $ISF_NAMESPACE apply -f visual-inspection/maximo-child-visual-inspection-backup-restore-local.yaml
        ```
    
        > **⚠️ Note — cluster-specific configmaps not auto-restored:**
        > The configmaps `custom-edgeman-config` and `custom-ui-config` contain **cluster-specific values** (edge manager hostname, Content Security Policy headers) and are intentionally **excluded from automatic restore** to prevent the VI console from breaking on the target cluster.
        >
        > **Before running the Fusion backup, it is strongly recommended to manually back up these configmaps** and store the files in a safe location outside the cluster:
        > ```bash
        > oc get configmap custom-edgeman-config -n $VISUALINSPECTION_NAMESPACE -o yaml > custom-edgeman-config.yaml
        > oc get configmap custom-ui-config -n $VISUALINSPECTION_NAMESPACE -o yaml > custom-ui-config.yaml
        > ```
        >
        > The `backup-pre-req-visual-inspection.sh` script also collects these configmaps automatically — it stores them as Kubernetes secrets (`custom-edgeman-config-backup` and `custom-ui-config-backup`) in the Visual Inspection namespace (backed up and restored by Fusion), and prints their full YAML content to stdout for reference.
        >
        > After the restore, the configmaps must be applied manually. **If performing an alternate-cluster restore**, the hostname and CSP values must be updated to match the target cluster before applying — see the [mas-visual-inspection restore section](#mas-visual-inspection-1) below.
    
    - **mas-predict**\*:
    
    
        ```
        oc -n $ISF_NAMESPACE apply -f predict/maximo-child-predict-backup-restore-local.yaml
        ```
    
    - **mas-assist**:
    
    
        ```
        oc -n $ISF_NAMESPACE apply -f assist/maximo-child-assist-backup-restore-local.yaml
        ```
    
    - **mas-aiservice**:
    
    
        ```
        oc -n $ISF_NAMESPACE apply -f aiservice/maximo-child-aiservice-backup-restore-local.yaml
        ```
    
    - **mref**:
    
    
        ```
        oc -n $ISF_NAMESPACE apply -f mref/maximo-child-facilities-backup-restore-local.yaml
        ```
    
    \**Predict is only supported for Backup and restore to the same cluster and only for scenarios where the Cloud Pak for Data instance is untouched.
    Backing up and restoring Cloud Pak for Data deployed by Maximo is not supported.*

1. Prepare Fusion for backup. If you have not already done so, follow the procedures to achieve the following:

    - Create a [backup storage location](https://www.ibm.com/docs/en/fusion-software/2.13.0?topic=machines-backup-storage-locations).
    - Create a [backup policy](https://www.ibm.com/docs/en/fusion-software/2.13.0?topic=policies-creating-backup-policy).
    - Create a policy assignment by [assigning the policy to the application](https://www.ibm.com/docs/en/fusion-software/2.13.0?topic=policies-managing-backup-policy).
    
    *Refer to https://www.ibm.com/docs/en/fusion-software/2.13.0?topic=restore-backup-your-workloads.*


1. On Fusion, after [assigning a backup policy to the application](https://www.ibm.com/docs/en/fusion-software/2.13.0?topic=policies-managing-backup-policy).
patch the policy assignment to point to the parent recipe:
  
    - Identify the policy assignment's name:

        ```
        $ oc -n $ISF_NAMESPACE get policyassignments
        
        NAME                                                   CLUSTER   APPLICATION       BACKUPPOLICY   RECIPE                RECIPENAMESPACE   PHASE      LASTBACKUPTIMESTAMP   CAPACITY
        sample-policy-xxx-apps.sbsa-br1.cp.fyre.ibm.com                  mas-arft-core     maximo-policy                                          Assigned   3d7h                  4521418945
        ```


    - Patch that policy assignment with the recipe name and namepace (the recipe is always the same):

        ```
        $ oc -n $ISF_NAMESPACE patch policyassignment/POLICY-ASSIGNMENT-NAME --type merge -p '
        {
          "spec": {
            "recipe": {
              "name":"maximo-parent-recipe",
              "namespace":"'$ISF_NAMESPACE'",
              "apiVersion":"spp-data-protection.isf.ibm.com/v1alpha1"
            }
          }
        }'
        ```

        Where "POLICY-ASSIGNMENT-NAME" is the name of the PolicyAssignment CR (see immediate step above).

1. In the Fusion console, follow the procedure to [initiate an on-demand backup](https://www.ibm.com/docs/en/fusion-software/2.13.0?topic=machines-running-demand-backups), or let the backup policy schedule it for you.


----


## Restore Prerequisites

1. Some prerequisite scripts require environment variables to be configured before execution. Edit the `maximo_env.sh` script with the appropriate values for your environment, following the same configuration used in the Backup Prerequisites section.

    ```
    source maximo_env.sh
    ```

1. Run the prerequisite script for each application that applies to the Maximo instance

    - **mongodb**:

        ```
        mongodb/restore-pre-req-mongodb.sh
        ```

    - **db2u**:

        ```
        db2/restore-pre-req-db2.sh
        ```

    - **amq-streams**:

        ```
        amq-streams/restore-pre-req-amq-streams.sh
        ```

        *Applies if "monitor" or "predict" are deployed capabilities.*
    
    - **ibm-sls**:

        ```
        sls/restore-pre-req-sls.sh
        ```

    - **mas-core**:

        ```
        core/restore-pre-req-core.sh
        ```

    - **mas-manage**:

        ```
        manage/restore-pre-req-manage.sh
        ```

    - **mas-iot**:

        ```
        iot/restore-pre-req-iot.sh
        ```

    - **mas-monitor**:

        ```
        monitor/restore-pre-req-monitor.sh
        ```

    - **mas-optimizer**:

        ```
        optimizer/restore-pre-req-optimizer.sh
        ```

    - **mas-visual-inspection**:

        ```
        visual-inspection/restore-pre-req-visual-inspection.sh
        ```

    - **mas-predict**\*:

        ```
        predict/restore-pre-req-predict.sh
        ```

    - **mas-assist**:

        ```
        assist/restore-pre-req-assist.sh
        ```

    - **mref**:

        ```
        mref/restore-pre-req-mref.sh
        ```

    - **mas-aiservice**:

        ```
        aiservice/restore-pre-req-aiservice.sh
        ```

    \**Predict is only supported for Backup and restore to the same cluster and only for scenarios where the Cloud Pak for Data instance is untouched.
    Backing up and restoring Cloud Pak for Data deployed by Maximo is not supported.*

1. (AIService only) Install and configure OpenDataHub using mas cli on Target cluster.
AI Service ansible overview: https://ibm-mas.github.io/ansible-devops/playbooks/aiservice/#overview

    - Start mas cli container (using docker or podman)

        ```bash
        docker run -ti --rm -v ~:/mnt/home --pull always quay.io/ibmmas/cli
        ```

    - oc-login to target cluster, setup and run the OpenDataHub role.

        ```bash
        export ROLE_NAME="aiservice_odh"
        export AISERVICE_ODH_MODEL_DEPLOYMENT_TYPE="serverless"
    
        cd ansible-devops/
        ansible-playbook playbooks/run_role.yml
        ```

## Restore

### Restore to same cluster

1. Before restoring applications, delete the namespaces from the Maximo instance to be restored: `ibm-sls`, `mas-arft-core`, `mas-arft-manage`, `mongoce`, `db2u`, etc.

1. Verify that the namespaces `cert-manager`, `grafana` and `redhat-marketplace` exist or have not been deleted. If any of these namespaces are missing, refer to step 1 from the "Restore to an alternative cluster" section below.

1. In the Fusion console, follow [Restoring an application](https://www.ibm.com/docs/en/fusion-software/2.13.0?topic=machines-restoring-application) procedure to initiate a restore.


### Restore to an alternative cluster

1. Before restoring the application, the following Maximo Ansible roles need to be run:

    - [cert_manager](https://ibm-mas.github.io/ansible-devops/roles/cert_manager/#run-role-playbook) (run "Run Role Playbook")
    - [dro (redhat-marketplace)](https://ibm-mas.github.io/ansible-devops/roles/dro/#install-in-cluster-and-generate-mas-configuration) (run "To install DRO")
    - [ibm-catalogs](https://ibm-mas.github.io/ansible-devops/roles/ibm_catalogs/#run-role-playbook) (run "Run Role Playbook")
    
    Optionally, depending on the deployment or Maximo version you might need to include `grafana`:

     - [grafana](https://ibm-mas.github.io/ansible-devops/roles/grafana/#example-playbook) (run "Example Playbook")
 
1. Some recipes rely on variables that need to be set before appling the recipe. For these variables, edit the `maximo_env.sh` script to set these variables to make the necessary modifications according to your configuration. 
 
1. On the Fusion console, follow [the procedure to kick off a restore](https://www.ibm.com/docs/en/fusion-software/2.13.0?topic=machines-restoring-application).


## Post-Restore Tasks

- Visual Inspection

    > **⚠️ Note — manual recovery of cluster-specific configmaps:**
    > This section only applies if the Maximo Visual Inspection UI was customized and tuned originally, to help manually restore the customized configmaps.
    > 
    > The configmaps `custom-edgeman-config` and `custom-ui-config` are **not automatically restored**. After the restore completes, they must be applied manually using one of the options below.
    >
    > **🔁 Same-cluster restore:** apply the files as-is — no hostname changes needed.
    >
    > **🔀 Alternate-cluster restore:** the hostname and CSP values inside the files are cluster-specific and **must be updated** to match the target cluster before applying.
    >
    > ---
    >
    > **Option 1 — Restore from manually saved files (recommended)**
    >
    > If you followed the backup recommendation and saved the files manually:
    >
    > 1. *(Alternate-cluster restore only)* Edit the saved YAML files and update cluster-specific values:
    >
    >    **`custom-edgeman-config.yaml`** — update the `hostname` field:
    >    ```yaml
    >    # Before (source cluster):
    >    "hostname": "arft.visualinspection.arft.apps.<source-cluster>.example.com"
    >    # After (target cluster):
    >    "hostname": "arft.visualinspection.arft.apps.<target-cluster>.example.com"
    >    ```
    >
    >    **`custom-ui-config.yaml`** — update all hostnames in the Content Security Policy (CSP) headers:
    >    ```yaml
    >    # Before (source cluster):
    >    connect-src 'self' *.arft.apps.<source-cluster>.example.com
    >    # After (target cluster):
    >    connect-src 'self' *.arft.apps.<target-cluster>.example.com
    >    ```
    >    > Note: the CSP hostname appears multiple times — update all occurrences.
    >
    > 2. Apply the configmaps:
    > ```bash
    > oc apply -n $VISUALINSPECTION_NAMESPACE -f custom-edgeman-config.yaml
    > oc apply -n $VISUALINSPECTION_NAMESPACE -f custom-ui-config.yaml
    > ```
    >
    > ---
    >
    > **Option 2 — Restore from the backup secrets (alternative)**
    >
    > If you do not have the manually saved files, extract the configmap YAML from the secrets automatically created by the pre-req script and restored by Fusion:
    >
    > 1. Extract the configmap YAML from the restored secrets:
    > ```bash
    > oc extract -n $VISUALINSPECTION_NAMESPACE secret/custom-edgeman-config-backup --to=- > custom-edgeman-config.yaml
    > oc extract -n $VISUALINSPECTION_NAMESPACE secret/custom-ui-config-backup --to=- > custom-ui-config.yaml
    > ```
    >
    > 2. *(Alternate-cluster restore only)* Edit the extracted YAML files and update cluster-specific values:
    >
    >    **`custom-edgeman-config.yaml`** — update the `hostname` field:
    >    ```yaml
    >    # Before (source cluster):
    >    "hostname": "arft.visualinspection.arft.apps.<source-cluster>.example.com"
    >    # After (target cluster):
    >    "hostname": "arft.visualinspection.arft.apps.<target-cluster>.example.com"
    >    ```
    >
    >    **`custom-ui-config.yaml`** — update all hostnames in the Content Security Policy (CSP) headers:
    >    ```yaml
    >    # Before (source cluster):
    >    connect-src 'self' *.arft.apps.<source-cluster>.example.com
    >    # After (target cluster):
    >    connect-src 'self' *.arft.apps.<target-cluster>.example.com
    >    ```
    >    > Note: the CSP hostname appears multiple times — update all occurrences.
    >
    > 3. Apply the configmaps:
    > ```bash
    > oc apply -n $VISUALINSPECTION_NAMESPACE -f custom-edgeman-config.yaml
    > oc apply -n $VISUALINSPECTION_NAMESPACE -f custom-ui-config.yaml
    > ```
    >
    > ---
    >
    > **If neither option is available** (manual files were not saved and the pre-req script was not run before the backup), the VI console will still function but will lose its tuning configuration. In that case, contact the **MAS Visual Inspection team** for help retuning the console.

---
