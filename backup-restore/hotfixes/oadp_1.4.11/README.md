# Customer Advisory: OADP 1.4.11 Certificate Handling Issue Impacting Backup and Restore Operations

## Overview

IBM has identified an issue in OpenShift API for Data Protection (OADP) 1.4.11 related to certificate handling. This issue can cause backup and restore operations in IBM Storage Fusion to fail.

OADP 1.4.x is supported on OpenShift Container Platform (OCP) 4.18.x and earlier releases. This issue does not impact customers using OCP 4.19 and later.

## Problem Details

Due to a certificate handling defect in OADP 1.4.11, backup operations may fail unexpectedly. Affected environments may observe backup or restore jobs entering a failed state with errors similar to the following:

```
Failed validationBMYBR0009There was an error when processing the job in the Transaction Manager service. The underlying error was: Unexpected failure: "Velero BackupStorageLocation isf-aws-20260921-185853 could not be imported: FailedValidationException('Velero BackupStorageLocation 7d37a2a7-7841-4a30-a076-25d3fced2be1 is still Unavailable after 5 minutes')".
```


## Impacted Releases

### IBM Storage Fusion 2.14.0

The issue impacts IBM Storage Fusion 2.14.0 only when the **In-Place Snapshot** feature is being used.

### Other IBM Storage Fusion Releases

The issue affects all supported IBM Storage Fusion releases except:

- IBM Storage Fusion 2.12.4 (September Monthly Release)
- IBM Storage Fusion 2.13.2 (September Monthly Release)
- Future monthly releases will include this fix.

## Resolution

IBM has released a hotfix to address this issue.

The hotfix can be downloaded from:

<https://github.com/IBM/storage-fusion/tree/master/backup-restore/hotfixes/oadp_1.4.11/br-oadp-1.4.11-patch.sh>

## Upgrade Considerations

Before fixing the issue, if the customer upgraded to a Fusion version which already includes a fix (such as 2.13.2), the Fusion upgrade will be successful but the Backup and Restore service will remain on the previous version. To complete the upgrade, the customer must run <https://github.com/IBM/storage-fusion/tree/master/backup-restore/hotfixes/oadp_1.4.11/br-oadp-1.4.11-patch.sh> script.
