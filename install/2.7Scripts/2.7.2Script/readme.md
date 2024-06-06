# generic-mirror.sh

This script does the mirroring and validation of both HCI & SDS Images.

### Prerequisites Required:
- Docker or Podman should be installed
- jq to be installed
- Skopeo should be installed with minimum version of 1.13
- oc-mirror utility should be installed if redhat images are going to be mirrored

Ensure all the required repository auths are added in the pull-secret.json file.

### USAGE
To use this script, follow the below steps:
- Download the `generic-mirror.sh`, `isf-272-hci-images.json` and `isf-272-sds-images.json` files to the same directory(Preferred to create a new directory).
- Also add your `pull-secret` file to the same direcory.
- Navigate to that directory and make the script executable `chmod +x generic-mirror.sh`.
- Execute the script by following the sample commands below.

### Options Description in the script:
```
-ps    : Mandatory PULL-SECRET file path.
-lreg  : Mandatory LOCAL_ISF_REGISTRY="<Your Enterprise Registry Host>:<Port>", PORT is optional.
-lrep  : Mandatory LOCAL_ISF_REPOSITORY="<Your Image Path>", which is the image path to mirror the images.
-pr    : Optional PRODUCT type, either "hci" or "sds", by default "hci" will be considered.
-ocpv  : Optional OCP_VERSION, Required only if '-all' or '-ocp' or '-redhat' is used.
-fdfv  : Optional FDF_VERSION, Required only if '-all' or '-fdf' or '-redhat' is used.
-all   : Optional ALL_IMAGES, which mirrors all the images(OCP, REDHAT, FUSION, GLOBAL DATA PLATFORM, DATA FOUNDATION, BACKUP & RESTORE and DATA CATALOGING).
-ocp   : Optional OCP_IMAGES, which mirrors all the OCP images.
-redhat: Optional REDHAT_IMAGES, which mirrors all the REDHAT images.
-fusion: Optional FUSION_IMAGES, which mirrors all the FUSION images.
-gdp   : Optional GDP_IMAGES, which mirrors all the GLOBAL DATA PLATFORM images.
-fdf   : Optional DF_IMAGES, which mirrors all the  DATA FOUNDATION images.
-br    : Optional BR_IMAGES, which mirrors all the  BACKUP & RESTORE images.
-dcs   : Optional DCS_IMAGES, which mirrors all the  DATA CATALOGING images.
-validate : Optional VALIDATE_IMAGES, to only validate the mirrored images, should be used only with any/some of the -all/-ocp/-redhat/-fusion/-gdp/-fdf/-br/-dcs.
```

### NOTE:
```
- This Script supports only single repo mirroring & validation, for multirepo please execute this script twice with appropriate options
```

### Syntax to execute the generic-mirror.sh script
- To Mirror All The Images(OCP, REDHAT, FUSION, GLOBAL DATA PLATFORM, FUSION DATA FOUNDATION, BACKUP & RESTORE and DATA CATALOGING):
```
nohup ./generic-mirror.sh -ps "PATH_TO_THE_PULL_SECRET_FILE" -lreg "LOCAL_ISF_REGISTRY:<PORT>" -lrep "LOCAL_ISF_REPOSITORY" -pr "PRODUCT_TYPE" -ocpv "OCP_VERSION" -fdfv "FDF_VERSION" -all &
```

- To Mirror Only The Required Images(Any/Some of the OCP, REDHAT, FUSION, GLOBAL DATA PLATFORM, DATA FOUNDATION, BACKUP & RESTORE and DATA CATALOGING):
```
nohup ./generic-mirror.sh -ps "PATH_TO_THE_PULL_SECRET_FILE" -lreg "LOCAL_ISF_REGISTRY:<PORT>" -lrep "LOCAL_ISF_REPOSITORY" -ocpv "OCP_VERSION" -ocp -redhat -fusion -gdp -fdf -br -dcs &
```
- To only Validate All The Images(OCP, REDHAT, FUSION, GLOBAL DATA PLATFORM, FUSION DATA FOUNDATION, BACKUP & RESTORE and DATA CATALOGING):
```
nohup ./generic-mirror.sh -ps "PATH_TO_THE_PULL_SECRET_FILE" -lreg "LOCAL_ISF_REGISTRY:<PORT>" -lrep "LOCAL_ISF_REPOSITORY" -pr "PRODUCT_TYPE" -ocpv "OCP_VERSION" -fdfv "FDF_VERSION" -all -validate &
```

- To only Validate the Required Images(Any/Some of the OCP, REDHAT, FUSION, GLOBAL DATA PLATFORM, DATA FOUNDATION, BACKUP & RESTORE and DATA CATALOGING):
```
nohup ./generic-mirror.sh -ps "PATH_TO_THE_PULL_SECRET_FILE" -lreg "LOCAL_ISF_REGISTRY:<PORT>" -lrep "LOCAL_ISF_REPOSITORY" -ocpv "OCP_VERSION" -ocp -redhat -fusion -gdp -fdf -br -dcs -validate &
```

### Example commands to execute the generic-mirror.sh script
- Sample Command to Mirror all the HCI images(OCP, REDHAT, FUSION, GLOBAL DATA PLATFORM, DATA FOUNDATION, BACKUP & RESTORE and DATA CATALOGING):
```
nohup ./generic-mirror.sh -ps ./pull-secret.json -lreg "registryhost.com:443" -lrep "fusion-mirror" -ocpv "4.12.42" -fdfv "4.14" -all &
```

- Sample Command to Mirror all the SDS images(OCP, REDHAT, FUSION, GLOBAL DATA PLATFORM, DATA FOUNDATION, BACKUP & RESTORE and DATA CATALOGING):
```
nohup ./generic-mirror.sh -ps ./pull-secret.json -lreg "registryhost.com:443" -lrep "fusion-mirror" -pr "sds" -ocpv "4.12.42" -fdfv "4.14" -all &
```

- Sample Command to Mirror Only the Required Images(Any/Some of the OCP, REDHAT, FUSION, GLOBAL DATA PLATFORM, DATA FOUNDATION, BACKUP & RESTORE and DATA CATALOGING):
```
nohup ./generic-mirror.sh -ps ./pull-secret.json -lreg "registryhost.com:443" -lrep "fusion-mirror" -ocpv "4.12.42" -fdfv "4.14" -ocp -redhat -fusion -gdp -fdf -br -dcs &
```

- Sample Command to Mirror only the OCP images:
```
nohup ./generic-mirror.sh -ps ./pull-secret.json -lreg "registryhost.com:443" -lrep "fusion-mirror" -ocpv "4.12.42" -ocp &
```

- Sample Command to Mirror only the REDHAT images:
```
nohup ./generic-mirror.sh -ps ./pull-secret.json -lreg "registryhost.com:443" -lrep "fusion-mirror" -ocpv "4.12.42" -redhat &
```

- Sample Command to Mirror only the DATA FOUNDATION images
```
nohup ./generic-mirror.sh -ps ./pull-secret.json -lreg "registryhost.com:443" -lrep "fusion-mirror" -ocpv "4.12.42" -fdfv "4.14" -fdf &
```

- Sample Command to Mirror only the IBM Storage Fusion operator images:
```
nohup ./generic-mirror.sh -ps ./pull-secret.json -lreg "registryhost.com:443" -lrep "fusion-mirror" -fusion &
```

- Sample Command to Mirror only the GLOBAL DATA PLATFORM images
```
nohup ./generic-mirror.sh -ps ./pull-secret.json -lreg "registryhost.com:443" -lrep "fusion-mirror" -gdp &
```

- Sample Command to Mirror only the BACKUP & RESTORE images
```
nohup ./generic-mirror.sh -ps ./pull-secret.json -lreg "registryhost.com:443" -lrep "fusion-mirror" -br &
```

- Sample Command to Mirror only the DATA CATALOGING images
```
nohup ./generic-mirror.sh -ps ./pull-secret.json -lreg "registryhost.com:443" -lrep "fusion-mirror" -dcs &
```

- Sample Command to only validate all the HCI images(OCP, REDHAT, FUSION, GLOBAL DATA PLATFORM, DATA FOUNDATION, BACKUP & RESTORE and DATA CATALOGING):
```
nohup ./generic-mirror.sh -ps ./pull-secret.json -lreg "registryhost.com:443" -lrep "fusion-mirror" -ocpv "4.12.42" -fdfv "4.14" -all -validate &
```

- Sample Command to only validate the Required Images(Any/Some of the OCP, REDHAT, FUSION, GLOBAL DATA PLATFORM, DATA FOUNDATION, BACKUP & RESTORE and DATA CATALOGING):
```
nohup ./generic-mirror.sh -ps ./pull-secret.json -lreg "registryhost.com:443" -lrep "fusion-mirror" -ocpv "4.12.42" -fdfv "4.14" -ocp -redhat -fusion -gdp -fdf -br -dcs -validate &
```

### NOTE
- If port is used in LOCAL_ISF_REGISTRY(-lreg) make sure to add that entry in your pull-secret file
- For the required Pull-secret registries & input details like LOCAL_ISF_REGISTRY & LOCAL_ISF_REPOSITORY of respective images are based on mirroring steps in the IBM Knowledge centre, please refer the IBM Knowledge centre for more details https://www.ibm.com/docs/en/sfhs/2.7.x?topic=installation-mirroring-your-images-enterprise-registry .
- This script doesn't fully validate the OCP, Redhat and Data Foundation images.
- While installing Backup & Restore or Data cataloging service make sure to add the Redhat ImageContentSourcePolicy, please refer the IBM Knowledge centre for more details https://www.ibm.com/docs/en/sfhs/2.7.x?topic=registry-mirroring-red-hat-operator-images-enterprise . For other ImageContentSourcePolicies & CatalogSources please refer https://www.ibm.com/docs/en/sfhs/2.7.x?topic=installation-mirroring-your-images-enterprise-registry .