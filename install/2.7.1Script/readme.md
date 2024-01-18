# generic-mirror.sh

This script only does mirroring and validation of HCI Images.

To execute the script, ensure you have either Docker or Podman on your mirroring host and Skopeo version should be minimum of 1.14 .

Ensure all the required repository auths are added in the pull-secret.json file.

### USAGE
To use this script, follow the below steps:
- Download the `generic-mirror.sh` and `isf-271-images.json` files to a single directory(Preferred to create a new directory).
- Navigate to that directory and make the script executable `chmod +x generic-mirror.sh`.
- Execute the script by following the sample commands below.

### Options Description in the script:
```
-ps    : Mandatory PULL-SECRET file path.
-lreg  : Mandatory LOCAL_ISF_REGISTRY="<Your Enterprise Registry Host>:<Port>", PORT is optional.
-lrep  : Mandatory LOCAL_ISF_REPOSITORY="<Your Image Path>", which is the image path to mirror the images.
-ocpv  : Optional OCP_VERSION, Required only if '-all' or '-ocp' or '-redhat' or '-df' is used.
-all   : Optional ALL_IMAGES, which mirrors all the images(OCP, REDHAT, FUSION, GLOBAL DATA PLATFORM, DATA FOUNDATION, BACKUP & RESTORE and DATA CATALOGING).
-ocp   : Optional OCP_IMAGES, which mirrors all the OCP images.
-redhat: Optional REDHAT_IMAGES, which mirrors all the REDHAT images.
-fusion: Optional FUSION_IMAGES, which mirrors all the FUSION images.
-gdp   : Optional GDP_IMAGES, which mirrors all the GLOBAL DATA PLATFORM images.
-df    : Optional DF_IMAGES, which mirrors all the  DATA FOUNDATION images.
-br    : Optional BR_IMAGES, which mirrors all the  BACKUP & RESTORE images.
-dcs"  : Optional DCS_IMAGES, which mirrors all the  DATA CATALOGING images.
```

### Syntax to execute the generic-mirror.sh script
- To Mirror All The HCI Images(OCP, REDHAT, FUSION, GLOBAL DATA PLATFORM, DATA FOUNDATION, BACKUP & RESTORE and DATA CATALOGING):
```
nohup ./generic-mirror.sh -ps "PATH_TO_THE_PULL_SECRET_FILE" -lreg "LOCAL_ISF_REGISTRY:<PORT>" -lrep "LOCAL_ISF_REPOSITORY" -ocpv "OCP_VERSION" -all &
```

- To Mirror Only The Required HCI Images(Any/Some of the OCP, REDHAT, FUSION, GLOBAL DATA PLATFORM, DATA FOUNDATION, BACKUP & RESTORE and DATA CATALOGING):
```
nohup ./generic-mirror.sh -ps "PATH_TO_THE_PULL_SECRET_FILE" -lreg "LOCAL_ISF_REGISTRY:<PORT>" -lrep "LOCAL_ISF_REPOSITORY" -ocpv "OCP_VERSION" -ocp -redhat -fusion -gdp -df -br -dcs &
```

### Example commands to execute the generic-mirror.sh script
- Sample Command to Mirror all the images(OCP, REDHAT, FUSION, GLOBAL DATA PLATFORM, DATA FOUNDATION, BACKUP & RESTORE and DATA CATALOGING):
```
nohup ./generic-mirror.sh -ps ./pull-secret.json -lreg "registryhost.com:443" -lrep "fusion-mirror" -ocpv "4.12.42" -all &
```

- Sample Command to Mirror Only the Required HCI Images(Any/Some of the OCP, REDHAT, FUSION, GLOBAL DATA PLATFORM, DATA FOUNDATION, BACKUP & RESTORE and DATA CATALOGING):
```
nohup ./generic-mirror.sh -ps ./pull-secret.json -lreg "registryhost.com:443" -lrep "fusion-mirror" -ocpv "4.12.42" -ocp -redhat -fusion -gdp -df -br -dcs &
```

- Sample Command to Mirror only the OCP images:
```
nohup ./generic-mirror.sh -ps ./pull-secret.json -lreg "registryhost.com:443" -lrep "fusion-mirror" -ocpv "4.12.42" -ocp &
```

- Sample Command to Mirror only the REDHAT images:
```
nohup ./generic-mirror.sh -ps ./pull-secret.json -lreg "registryhost.com:443" -lrep "fusion-mirror" -ocpv "4.12.42" -redhat &
```

- Sample Command to Mirror only the IBM Storage Fusion operator images:
```
nohup ./generic-mirror.sh -ps ./pull-secret.json -lreg "registryhost.com:443" -lrep "fusion-mirror" -fusion &
```

- Sample Command to Mirror only the GLOBAL DATA PLATFORM images
```
nohup ./generic-mirror.sh -ps ./pull-secret.json -lreg "registryhost.com:443" -lrep "fusion-mirror" -gdp &
```

- Sample Command to Mirror only the DATA FOUNDATION images
```
nohup ./generic-mirror.sh -ps ./pull-secret.json -lreg "registryhost.com:443" -lrep "fusion-mirror" -df &
```

- Sample Command to Mirror only the BACKUP & RESTORE images
```
nohup ./generic-mirror.sh -ps ./pull-secret.json -lreg "registryhost.com:443" -lrep "fusion-mirror" -br &
```

- Sample Command to Mirror only the DATA CATALOGING images
```
nohup ./generic-mirror.sh -ps ./pull-secret.json -lreg "registryhost.com:443" -lrep "fusion-mirror" -dcs &
```

### NOTE
- If port is used in LOCAL_ISF_REGISTRY(-lreg) make sure to add that entry in your pull-secret file
- The Input details like LOCAL_ISF_REGISTRY & LOCAL_ISF_REPOSITORY are based on mirroring in the IBM Knowledge centre, please refer the IBM Knowledge centre for more details https://www.ibm.com/docs/en/sfhs/2.7.x?topic=installation-mirroring-your-images-enterprise-registry .
- For the locations of ImageContentSourcePolicy & CatalogSource which are obtained while mirroring, please refer the respective sections in the IBM Knowledge centre https://www.ibm.com/docs/en/sfhs/2.7.x?topic=installation-mirroring-your-images-enterprise-registry.