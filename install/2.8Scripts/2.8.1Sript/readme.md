# generic-mirror.sh

This script does the mirroring and validation of both HCI & SDS Images.

### Prerequisites Required:
- Please refer the "Before you begin" section in IBM Knowledge centre for prerequisites https://www.ibm.com/docs/en/sfhs/2.8.x?topic=installation-mirroring-your-images-enterprise-registry#tasktask_htj_h1w_stb__prereq__1

### USAGE
To use this script, follow the below steps:
- Download/copy the `generic-mirror.sh`, `isf-281-hci-images.json` and `isf-281-sds-images.json` files to the same directory(Preferred to create a new directory).
- Also add your `pull-secret` file to the same directory.
- Navigate to that directory and make the script executable `chmod +x generic-mirror.sh`.
- Execute the script by following the sample commands below.

### Options Description in the script:
```
-ps    : Mandatory PULL-SECRET file path.
-lreg  : Mandatory LOCAL_ISF_REGISTRY="<Your Enterprise Registry Host>:<Port>", PORT is optional.
-lrep  : Mandatory LOCAL_ISF_REPOSITORY="<Your Image Path>", which is the image path to mirror the images.
-pr    : Optional PRODUCT type, either "hci" or "sds", by default "hci" will be considered.
-dest_as_tag_with_selfsigned_cert : Optional destination as tag with selfsigned certificate option, which does tag based mirroring with selfsigned certificate.
-dest_as_tag : Optional destination as tag without selfsigned certificate option, which does tag based mirroring without selfsigned certificate.
-dest_as_digest_with_selfsigned_cert : Optional(By default this option is used) destination as digest with selfsigned certificate option, which does digest based mirroring with selfsigned certificate.
-dest_as_digest : Optional destination as digest without selfsigned certificate option, which does digest based mirroring without selfsigned certificate.
-ocpv  : Optional OCP_VERSION (eg: "4.14.14" or multiple versions like "4.14.14,4.15.2"), Required only if '-all' or '-ocp' or '-redhat' is used.
-fdfv  : Optional FDF_VERSION (eg: "4.14" or multiple versions like "4.14,4.15"), Required only if '-all' or '-fdf' or '-redhat' is used.
-all   : Optional ALL_IMAGES, which mirrors all the images(OCP, REDHAT, FUSION, GLOBAL DATA PLATFORM, DATA FOUNDATION, BACKUP & RESTORE and DATA CATALOGING).
-ocp   : Optional OCP_IMAGES, which mirrors all the OCP images.
-redhat: Optional REDHAT_IMAGES, which mirrors all the REDHAT images.
-fusion: Optional FUSION_IMAGES, which mirrors all the FUSION images.
-gdp   : Optional GDP_IMAGES, which mirrors all the GLOBAL DATA PLATFORM images.
-fdf   : Optional DF_IMAGES, which mirrors all the DATA FOUNDATION images.
-br    : Optional BR_IMAGES, which mirrors all the BACKUP & RESTORE images.
-dcs   : Optional DCS_IMAGES, which mirrors all the DATA CATALOGING images.
-validate : Optional VALIDATE_IMAGES, to only validate the mirrored images, should be used only with any/some of the -all/-ocp/-redhat/-fusion/-gdp/-fdf/-br/-dcs.
```

### Syntax to execute the generic-mirror.sh script

1. ### For Mirroring

- To Mirror All The Images(OCP, REDHAT, FUSION, GLOBAL DATA PLATFORM, FUSION DATA FOUNDATION, BACKUP & RESTORE and DATA CATALOGING):
```
nohup ./generic-mirror.sh -ps "PATH_TO_THE_PULL_SECRET_FILE" -lreg "LOCAL_ISF_REGISTRY:<PORT>" -lrep "LOCAL_ISF_REPOSITORY" -pr "PRODUCT_TYPE" -ocpv "OCP_VERSION" -fdfv "FDF_VERSION" -all &
```

- To Mirror Only The Required Images(Any/Some of the OCP, REDHAT, FUSION, GLOBAL DATA PLATFORM, DATA FOUNDATION, BACKUP & RESTORE and DATA CATALOGING):
```
nohup ./generic-mirror.sh -ps "PATH_TO_THE_PULL_SECRET_FILE" -lreg "LOCAL_ISF_REGISTRY:<PORT>" -lrep "LOCAL_ISF_REPOSITORY" -ocpv "OCP_VERSION" -fdfv "FDF_VERSION" -ocp -redhat -fusion -gdp -fdf -br -dcs &
```

- To Mirror All Images with **Destination as Tag with Selfsigned Certificate** option(OCP, REDHAT, FUSION, GLOBAL DATA PLATFORM, DATA FOUNDATION, BACKUP & RESTORE and DATA CATALOGING):
```
nohup ./generic-mirror.sh -ps "PATH_TO_THE_PULL_SECRET_FILE" -lreg "LOCAL_ISF_REGISTRY:<PORT>" -lrep "LOCAL_ISF_REPOSITORY" -pr "PRODUCT_TYPE" -ocpv "OCP_VERSION" -fdfv "FDF_VERSION" -dest_as_tag_with_selfsigned_cert -all &
```

2. ### For Validation

- To only Validate All The Images(OCP, REDHAT, FUSION, GLOBAL DATA PLATFORM, FUSION DATA FOUNDATION, BACKUP & RESTORE and DATA CATALOGING):
```
nohup ./generic-mirror.sh -ps "PATH_TO_THE_PULL_SECRET_FILE" -lreg "LOCAL_ISF_REGISTRY:<PORT>" -lrep "LOCAL_ISF_REPOSITORY" -pr "PRODUCT_TYPE" -ocpv "OCP_VERSION" -fdfv "FDF_VERSION" -all -validate &
```

- To only Validate the Required Images(Any/Some of the OCP, REDHAT, FUSION, GLOBAL DATA PLATFORM, DATA FOUNDATION, BACKUP & RESTORE and DATA CATALOGING):
```
nohup ./generic-mirror.sh -ps "PATH_TO_THE_PULL_SECRET_FILE" -lreg "LOCAL_ISF_REGISTRY:<PORT>" -lrep "LOCAL_ISF_REPOSITORY" -ocpv "OCP_VERSION" -fdfv "FDF_VERSION" -ocp -redhat -fusion -gdp -fdf -br -dcs -validate &
```

- To only validate All Images with **Destination as Tag without Selfsigned Certificate** option(OCP, REDHAT, FUSION, GLOBAL DATA PLATFORM, DATA FOUNDATION, BACKUP & RESTORE and DATA CATALOGING):
```
nohup ./generic-mirror.sh -ps "PATH_TO_THE_PULL_SECRET_FILE" -lreg "LOCAL_ISF_REGISTRY:<PORT>" -lrep "LOCAL_ISF_REPOSITORY" -pr "PRODUCT_TYPE" -ocpv "OCP_VERSION" -fdfv "FDF_VERSION" -dest_as_tag -all -validate &
```

### Example commands to execute the generic-mirror.sh script

1. ### For Mirroring

- Sample Command to Mirror all the HCI images(OCP, REDHAT, FUSION, GLOBAL DATA PLATFORM, DATA FOUNDATION, BACKUP & RESTORE and DATA CATALOGING):
```
nohup ./generic-mirror.sh -ps ./pull-secret.json -lreg "registryhost.com:443" -lrep "fusion-mirror" -ocpv "4.14.24" -fdfv "4.14" -all &
```

- Sample Command to Mirror all the SDS images(OCP, REDHAT, FUSION, GLOBAL DATA PLATFORM, DATA FOUNDATION, BACKUP & RESTORE and DATA CATALOGING):
```
nohup ./generic-mirror.sh -ps ./pull-secret.json -lreg "registryhost.com:443" -lrep "fusion-mirror" -pr "sds" -ocpv "4.14.24" -fdfv "4.14" -all &
```

- Sample Command to Mirror Only the Required Images(Any/Some of the OCP, REDHAT, FUSION, GLOBAL DATA PLATFORM, DATA FOUNDATION, BACKUP & RESTORE and DATA CATALOGING):
```
nohup ./generic-mirror.sh -ps ./pull-secret.json -lreg "registryhost.com:443" -lrep "fusion-mirror" -ocpv "4.14.24" -fdfv "4.14" -ocp -redhat -fusion -gdp -fdf -br -dcs &
```

- Sample Command to Mirror only the OCP images:
```
nohup ./generic-mirror.sh -ps ./pull-secret.json -lreg "registryhost.com:443" -lrep "fusion-mirror" -ocpv "4.14.24" -ocp &
```

- Sample Command to Mirror only the REDHAT images:
```
nohup ./generic-mirror.sh -ps ./pull-secret.json -lreg "registryhost.com:443" -lrep "fusion-mirror" -ocpv "4.14.24" -redhat &
```

- Sample Command to Mirror only the DATA FOUNDATION images
```
nohup ./generic-mirror.sh -ps ./pull-secret.json -lreg "registryhost.com:443" -lrep "fusion-mirror" -ocpv "4.14.24" -fdfv "4.14" -fdf &
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

- Sample Command to Mirror all the HCI images with **Destination as Tag with Selfsigned Certificate** option(OCP, REDHAT, FUSION, GLOBAL DATA PLATFORM, DATA FOUNDATION, BACKUP & RESTORE and DATA CATALOGING):
```
nohup ./generic-mirror.sh -ps ./pull-secret.json -lreg "registryhost.com:443" -lrep "fusion-mirror" -ocpv "4.14.24" -fdfv "4.14" -dest_as_tag_with_selfsigned_cert -all &
```

2. ### For Only Validation

- Sample Command to only validate all the HCI images(OCP, REDHAT, FUSION, GLOBAL DATA PLATFORM, DATA FOUNDATION, BACKUP & RESTORE and DATA CATALOGING):
```
nohup ./generic-mirror.sh -ps ./pull-secret.json -lreg "registryhost.com:443" -lrep "fusion-mirror" -ocpv "4.14.24" -fdfv "4.14" -all -validate &
```

- Sample Command to only validate the Required Images(Any/Some of the OCP, REDHAT, FUSION, GLOBAL DATA PLATFORM, DATA FOUNDATION, BACKUP & RESTORE and DATA CATALOGING):
```
nohup ./generic-mirror.sh -ps ./pull-secret.json -lreg "registryhost.com:443" -lrep "fusion-mirror" -ocpv "4.14.24" -fdfv "4.14" -ocp -redhat -fusion -gdp -fdf -br -dcs -validate &
```

- Sample Command to only validate all the HCI images with **Destination as Tag without Selfsigned Certificate** option(OCP, REDHAT, FUSION, GLOBAL DATA PLATFORM, DATA FOUNDATION, BACKUP & RESTORE and DATA CATALOGING):
```
nohup ./generic-mirror.sh -ps ./pull-secret.json -lreg "registryhost.com:443" -lrep "fusion-mirror" -ocpv "4.14.24" -fdfv "4.14" -dest_as_tag -all -validate &
```

### NOTE
- If port is used in LOCAL_ISF_REGISTRY(-lreg) make sure to add that entry in your pull-secret file .
- For the required Pull-secret registries & input details like LOCAL_ISF_REGISTRY & LOCAL_ISF_REPOSITORY of respective images are based on mirroring steps in the IBM Knowledge centre, please refer the IBM Knowledge centre for more details .
  - "Download pull-secret.txt" section https://www.ibm.com/docs/en/sfhs/2.8.x?topic=installation-mirroring-your-images-enterprise-registry .
  - "See the following sample values" section under 1st point Procedure https://www.ibm.com/docs/en/sfhs/2.8.x?topic=registry-mirroring-storage-fusion-hci-images#tasksf_mirror_scale_images__steps__1 .
- This Script supports only single repo mirroring & validation, for multirepo please execute this script twice with appropriate options .
- For mirroring 4.15 Redhat or Data Foundation images, please refer the 1st Note point in Procedure section's 1st point in IBM Knowledge centre for more details https://www.ibm.com/docs/en/sfhs/2.8.x?topic=registry-mirroring-red-hat-operator-images-enterprise#tasktask_vpk_nbw_stb__steps__1 .
- This script doesn't fully validate the OCP, Redhat and Data Foundation images .
- While installing Backup & Restore or Data cataloging service make sure to add the Redhat ImageContentSourcePolicy, please refer the 6th point Procedure section in IBM Knowledge centre for more details https://www.ibm.com/docs/en/sfhs/2.8.x?topic=registry-mirroring-red-hat-operator-images-enterprise .
- For applying other ImageContentSourcePolicies & CatalogSources during installation, please refer the respective mirroring sections https://www.ibm.com/docs/en/sfhs/2.8.x?topic=installation-mirroring-your-images-enterprise-registry .