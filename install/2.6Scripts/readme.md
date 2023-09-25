Below scripts only do mirroring and validation for IBM related images, for any external redhat operator package used as pre-requisite to install service follow IBM Knowledge centre. https://www.ibm.com/docs/en/storage-fusion/2.6?topic=installation-mirroring-your-images-enterprise-registry

To execute below scripts, ensure you have either docker or podman on your mirroring host.
Ensure all repository auths are added in config.json file, for any incorrect auth or missing repo use below commands.

if container tool is podman
podman login <Your enterprise registry host:port> --authfile=<absolute path of config.json>
Sample command :
```
podman login testregistryhost.com:443 --authfile=/home/mirror/pull-secret.json
```

if container tool is docker
docker --config <absolute path of config.json directory> login <Your enterprise registry host:port>
Sample command :
```
docker --config=/home/mirror  login testregistryhost.com:443 
```

After adding credentials execute below scripts to mirror images 
For mirroring HCI 261 images, use isf-261-images.json

command to mirror IBM Spectrum Fusion operator images
```
nohup ./mirror-isf-images.sh -rh "<Your enterprise registry host>" -ps "<absolute path to config.json directory>" -tp "<Your image path>" -p "<Your enterprise registry port>" -il "<image-list>.json" -sds [y|n] &

Sample command to mirror SDS fusion 260 images:
nohup ./mirror-isf-images.sh -rh "testregistryhost.com" -ps "/home/mirror" -tp "testscript-260" -p "443" -il "isf-260-images.json" -sds y &

Sample command to mirror HCI fusion 261 images:
nohup ./mirror-isf-images.sh -rh "testregistryhost.com" -ps "/home/mirror" -tp "testscript-261" -p "443" -il "isf-261-images.json" &
 ```
 
command to mirror IBM Global Data Platform images
```
nohup ./mirror-scale-images.sh -rh "<Your enterprise registry host>" -ps "<absolute path to config.json directory>" -tp "<Your image path>" -p "<Your enterprise registry port>" -il "<image-list>.json" -sds [y|n] &

Sample command to mirror SDS Global Data Platform 260 images:
nohup ./mirror-scale-images.sh -rh "testregistryhost.com" -ps "/home/mirror" -tp "testscript-260" -p "443" -il "isf-260-images.json" -sds y &

Sample command to mirror HCI Global Data Platform 261 images:
nohup ./mirror-scale-images.sh -rh "testregistryhost.com" -ps "/home/mirror" -tp "testscript-261" -p "443" -il "isf-261-images.json" &
```
 
command to mirror IBM Spectrum Protect Plus images
```
nohup ./mirror-spp-images.sh -rh "<Your enterprise registry host>" -ps "<absolute path to config.json directory>" -tp "<Your image path>" -p "<Your enterprise registry port>" -il "<image-list>.json" &

sample command to mirror 260 images:
nohup ./mirror-spp-images.sh -rh "testregistryhost.com" -ps "/home/mirror" -tp "testscript-260" -p "443" -il "isf-260-images.json" &

sample command to mirror 261 images:
nohup ./mirror-spp-images.sh -rh "testregistryhost.com" -ps "/home/mirror" -tp "testscript-261" -p "443" -il "isf-261-images.json" &
```

command to mirror data cataloging images
```
nohup ./mirror-data-cataloging-images.sh -rh "<Your enterprise registry host>" -ps "<absolute path to config.json directory>" -tp "<Your image path>" -p "<Your enterprise registry port>" -il "<image-list>.json" &

sample command to mirror 260 images:
nohup ./mirror-data-cataloging-images.sh -rh "testregistryhost.com" -ps "/home/mirror" -tp "testscript-260" -p "443" -il "isf-260-images.json" &

sample command to mirror 261 images:
nohup ./mirror-data-cataloging-images.sh -rh "testregistryhost.com" -ps "/home/mirror" -tp "testscript-261" -p "443" -il "isf-261-images.json" &
```

command to mirror backup and restore images
```
nohup ./mirror-bkp-restore-images.sh -rh "<Your enterprise registry host>" -ps "<absolute path to config.json directory>" -tp "<Your image path>" -p "<Your enterprise registry port>" -il "<image-list>s.json" &

sample command to mirror 260 images:
nohup ./mirror-bkp-restore-images.sh -rh "testregistryhost.com" -ps "/home/mirror" -tp "testscript-260" -p "443" -il "isf-260-images.json" &

sample command to mirror 260 images:
nohup ./mirror-bkp-restore-images.sh -rh "testregistryhost.com" -ps "/home/mirror" -tp "testscript-261" -p "443" -il "isf-261-images.json" &
```

command to run validate-images.sh
```
nohup ./validate-images.sh -repo [1/2] -rh1 "https://<Your enterprise registry host1:port1>/<Your image path>" -rh2 "https://<Your enterprise registry host2:port2>/<Your image path2>" -il "<image-list>.json" -sds [y|n] -spp [y|n] -discover [y|n] -guardian [y|n] &

sample command to validate SDS 260 images:
nohup ./validate-images.sh -repo 1 -rh1 "https://testregistryhost.com:443/testscript-260" -ps "/home/mirror" -il "isf-260-images.json" -sds n -spp y -discover y -guardian y &

sample command to validate 261 HCI images:
nohup ./validate-images.sh -repo 1 -rh1 "https://testregistryhost.com:443/testscript-261" -ps "/home/mirror" -il "isf-261-images.json" -sds n -spp y -discover y -guardian y &
```

Options Description for all scripts in folder:
rh: Enterprise registry host/Local registry host where you want your images to mirror.
ps: Absolute path for auth file, config.json directory.
tp: Target path or folder where all images will be copied to on Enterprise registry.
p: Enterprise registry port
sds: Use this flag y|n if installing IBM Storage Fusion Operator, by default it will mirror HCI images.
il: Image-list.json files  
