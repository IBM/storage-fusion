#!/bin/bash

NUM=$1
echo $NUM

mkdir -p backup
mkdir backup/$NUM
mkdir backup/$NUM/pods
mkdir backup/$NUM/cm
mkdir backup/$NUM/secrets
mkdir backup/$NUM/sa
mkdir backup/$NUM/services
mkdir backup/$NUM/roles
mkdir backup/$NUM/rolebindings
mkdir backup/$NUM/deployments
mkdir backup/$NUM/rs
mkdir backup/$NUM/operatorgroups
mkdir backup/$NUM/csv
mkdir backup/$NUM/subscriptions
mkdir backup/$NUM/ip
mkdir backup/$NUM/networkpolicies
mkdir backup/$NUM/operatorconditions
mkdir backup/$NUM/bascfgs
mkdir backup/$NUM/coreidps
mkdir backup/$NUM/idpcfgs
mkdir backup/$NUM/jdbccfgs
mkdir backup/$NUM/kafkacfgs
mkdir backup/$NUM/mongocfgs
mkdir backup/$NUM/mviedges
mkdir backup/$NUM/objectstoragecfgs
mkdir backup/$NUM/pushnotificationcfgs
mkdir backup/$NUM/replicadbs
mkdir backup/$NUM/scimcfgs
mkdir backup/$NUM/slscfgs
mkdir backup/$NUM/smtpcfgs
mkdir backup/$NUM/suites
mkdir backup/$NUM/watsonstudiocfgs
mkdir backup/$NUM/workspaces
mkdir backup/$NUM/crds
mkdir backup/$NUM/clusterroles
mkdir backup/$NUM/clusterrolebindings

mkdir backup/$NUM/truststores
mkdir backup/$NUM/jobs


for i in `oc get pod | grep -v NAME | awk '{print $1}' | xargs`; do oc get pod $i -o yaml >backup/$NUM/pods/$i.yaml;  done 
for i in `oc get cm | grep -v NAME | awk '{print $1}' | xargs`; do oc get cm $i -o yaml >backup/$NUM/cm/$i.yaml;  done 
for i in `oc get secrets | grep -v NAME | awk '{print $1}' | xargs`; do oc get secrets $i -o yaml >backup/$NUM/secrets/$i.yaml;  done 
for i in `oc get sa | grep -v NAME | awk '{print $1}' | xargs`; do oc get sa $i -o yaml >backup/$NUM/sa/$i.yaml;  done 
for i in `oc get services | grep -v NAME | awk '{print $1}' | xargs`; do oc get services $i -o yaml >backup/$NUM/services/$i.yaml;  done 
for i in `oc get roles | grep -v NAME | awk '{print $1}' | xargs`; do oc get roles $i -o yaml >backup/$NUM/roles/$i.yaml;  done 
for i in `oc get rolebindings | grep -v NAME | awk '{print $1}' | xargs`; do oc get rolebindings $i -o yaml >backup/$NUM/rolebindings/$i.yaml;  done 
for i in `oc get deployments | grep -v NAME | awk '{print $1}' | xargs`; do oc get deployments $i -o yaml >backup/$NUM/deployments/$i.yaml;  done 
for i in `oc get rs | grep -v NAME | awk '{print $1}' | xargs`; do oc get rs $i -o yaml >backup/$NUM/rs/$i.yaml;  done
for i in `oc get operatorgroups | grep -v NAME | awk '{print $1}' | xargs`; do oc get operatorgroups $i -o yaml >backup/$NUM/operatorgroups/$i.yaml;  done
for i in `oc get csv | grep -v NAME | awk '{print $1}' | xargs`; do oc get csv $i -o yaml >backup/$NUM/csv/$i.yaml;  done
for i in `oc get subscriptions | grep -v NAME | awk '{print $1}' | xargs`; do oc get subscriptions $i -o yaml >backup/$NUM/subscriptions/$i.yaml;  done
for i in `oc get ip | grep -v NAME | awk '{print $1}' | xargs`; do oc get ip $i -o yaml >backup/$NUM/ip/$i.yaml;  done
for i in `oc get networkpolicies | grep -v NAME | awk '{print $1}' | xargs`; do oc get networkpolicies $i -o yaml >backup/$NUM/networkpolicies/$i.yaml;  done 
for i in `oc get operatorconditions | grep -v NAME | awk '{print $1}' | xargs`; do oc get operatorconditions $i -o yaml >backup/$NUM/operatorconditions/$i.yaml;  done
for i in `oc get bascfgs | grep -v NAME | awk '{print $1}' | xargs`; do oc get bascfgs $i -o yaml >backup/$NUM/bascfgs/$i.yaml;  done
for i in `oc get coreidps | grep -v NAME | awk '{print $1}' | xargs`; do oc get coreidps $i -o yaml >backup/$NUM/coreidps/$i.yaml;  done
for i in `oc get idpcfgs | grep -v NAME | awk '{print $1}' | xargs`; do oc get idpcfgs $i -o yaml >backup/$NUM/idpcfgs/$i.yaml;  done
for i in `oc get jdbccfgs | grep -v NAME | awk '{print $1}' | xargs`; do oc get jdbccfgs $i -o yaml >backup/$NUM/jdbccfgs/$i.yaml;  done
for i in `oc get kafkacfgs | grep -v NAME | awk '{print $1}' | xargs`; do oc get kafkacfgs $i -o yaml >backup/$NUM/kafkacfgs/$i.yaml;  done
for i in `oc get mongocfgs | grep -v NAME | awk '{print $1}' | xargs`; do oc get mongocfgs $i -o yaml >backup/$NUM/mongocfgs/$i.yaml;  done
for i in `oc get mviedges | grep -v NAME | awk '{print $1}' | xargs`; do oc get mviedges $i -o yaml >backup/$NUM/mviedges/$i.yaml;  done
for i in `oc get objectstoragecfgs | grep -v NAME | awk '{print $1}' | xargs`; do oc get objectstoragecfgs $i -o yaml >backup/$NUM/objectstoragecfgs/$i.yaml;  done
for i in `oc get pushnotificationcfgs | grep -v NAME | awk '{print $1}' | xargs`; do oc get pushnotificationcfgs $i -o yaml >backup/$NUM/pushnotificationcfgs/$i.yaml;  done
for i in `oc get replicadbs | grep -v NAME | awk '{print $1}' | xargs`; do oc get replicadbs $i -o yaml >backup/$NUM/replicadbs/$i.yaml;  done
for i in `oc get scimcfgs | grep -v NAME | awk '{print $1}' | xargs`; do oc get scimcfgs $i -o yaml >backup/$NUM/scimcfgs/$i.yaml;  done
for i in `oc get slscfgs | grep -v NAME | awk '{print $1}' | xargs`; do oc get slscfgs $i -o yaml >backup/$NUM/slscfgs/$i.yaml;  done
for i in `oc get smtpcfgs | grep -v NAME | awk '{print $1}' | xargs`; do oc get smtpcfgs $i -o yaml >backup/$NUM/smtpcfgs/$i.yaml;  done
for i in `oc get suites | grep -v NAME | awk '{print $1}' | xargs`; do oc get suites $i -o yaml >backup/$NUM/suites/$i.yaml;  done
for i in `oc get watsonstudiocfgs | grep -v NAME | awk '{print $1}' | xargs`; do oc get watsonstudiocfgs $i -o yaml >backup/$NUM/watsonstudiocfgs/$i.yaml;  done
for i in `oc get workspaces | grep -v NAME | awk '{print $1}' | xargs`; do oc get workspaces $i -o yaml >backup/$NUM/workspaces/$i.yaml;  done
for i in `oc get crd -l app.kubernetes.io/name=ibm-mas | grep -v NAME | awk '{print $1}' | xargs`; do oc get crd  $i -o yaml >backup/$NUM/crds/$i.yaml;  done
for i in bascfgs.config.mas.ibm.com-v1-admin bascfgs.config.mas.ibm.com-v1-crdview bascfgs.config.mas.ibm.com-v1-edit bascfgs.config.mas.ibm.com-v1-view coreidps.internal.mas.ibm.com-v1-admin coreidps.internal.mas.ibm.com-v1-crdview coreidps.internal.mas.ibm.com-v1-edit coreidps.internal.mas.ibm.com-v1-view idpcfgs.config.mas.ibm.com-v1-admin idpcfgs.config.mas.ibm.com-v1-crdview idpcfgs.config.mas.ibm.com-v1-edit idpcfgs.config.mas.ibm.com-v1-view jdbccfgs.config.mas.ibm.com-v1-admin jdbccfgs.config.mas.ibm.com-v1-crdview jdbccfgs.config.mas.ibm.com-v1-edit jdbccfgs.config.mas.ibm.com-v1-view kafkacfgs.config.mas.ibm.com-v1-admin kafkacfgs.config.mas.ibm.com-v1-crdview kafkacfgs.config.mas.ibm.com-v1-edit kafkacfgs.config.mas.ibm.com-v1-view mongocfgs.config.mas.ibm.com-v1-admin mongocfgs.config.mas.ibm.com-v1-crdview mongocfgs.config.mas.ibm.com-v1-edit mongocfgs.config.mas.ibm.com-v1-view mviedges.addons.mas.ibm.com-v1-admin mviedges.addons.mas.ibm.com-v1-crdview mviedges.addons.mas.ibm.com-v1-edit mviedges.addons.mas.ibm.com-v1-view objectstoragecfgs.config.mas.ibm.com-v1-admin objectstoragecfgs.config.mas.ibm.com-v1-crdview objectstoragecfgs.config.mas.ibm.com-v1-edit objectstoragecfgs.config.mas.ibm.com-v1-view pushnotificationcfgs.config.mas.ibm.com-v1-admin pushnotificationcfgs.config.mas.ibm.com-v1-crdview pushnotificationcfgs.config.mas.ibm.com-v1-edit pushnotificationcfgs.config.mas.ibm.com-v1-view replicadbs.addons.mas.ibm.com-v1-admin replicadbs.addons.mas.ibm.com-v1-crdview replicadbs.addons.mas.ibm.com-v1-edit replicadbs.addons.mas.ibm.com-v1-view scimcfgs.config.mas.ibm.com-v1-admin scimcfgs.config.mas.ibm.com-v1-crdview scimcfgs.config.mas.ibm.com-v1-edit scimcfgs.config.mas.ibm.com-v1-view slscfgs.config.mas.ibm.com-v1-admin slscfgs.config.mas.ibm.com-v1-crdview slscfgs.config.mas.ibm.com-v1-edit slscfgs.config.mas.ibm.com-v1-view smtpcfgs.config.mas.ibm.com-v1-admin smtpcfgs.config.mas.ibm.com-v1-crdview smtpcfgs.config.mas.ibm.com-v1-edit smtpcfgs.config.mas.ibm.com-v1-view suites.core.mas.ibm.com-v1-admin suites.core.mas.ibm.com-v1-crdview suites.core.mas.ibm.com-v1-edit suites.core.mas.ibm.com-v1-view watsonstudiocfgs.config.mas.ibm.com-v1-admin watsonstudiocfgs.config.mas.ibm.com-v1-crdview watsonstudiocfgs.config.mas.ibm.com-v1-edit watsonstudiocfgs.config.mas.ibm.com-v1-view workspaces.core.mas.ibm.com-v1-admin workspaces.core.mas.ibm.com-v1-crdview workspaces.core.mas.ibm.com-v1-edit workspaces.core.mas.ibm.com-v1-view ibm-mas-coreapi-base:cpst3 ibm-mas-deployer-assist:cpst3 ibm-mas-deployer-hputilities:cpst3 ibm-mas-deployer-iot:cpst3 ibm-mas-deployer-manage:cpst3 ibm-mas-deployer-monitor:cpst3 ibm-mas-deployer-mso:cpst3 ibm-mas-deployer-optimizer:cpst3 ibm-mas-deployer-predict:cpst3 ibm-mas-deployer-safety:cpst3 ibm-mas-deployer-visualinspection:cpst3 ibm-mas-internalapi:cpst3 ibm-mas-sbo-view:cpst3 ibm-mas.v8.11.6-84ddc59d5c openshift-pipelines-clusterinterceptors; do oc get clusterroles $i -o yaml >backup/$NUM/clusterroles/$i.yaml;  done
for i in ibm-mas-coreapi-base:cpst3 ibm-mas-deployer-assist:cpst3 ibm-mas-deployer-hputilities:cpst3 ibm-mas-deployer-iot:cpst3 ibm-mas-deployer-manage:cpst3 ibm-mas-deployer-monitor:cpst3 ibm-mas-deployer-mso:cpst3 ibm-mas-deployer-optimizer:cpst3 ibm-mas-deployer-predict:cpst3 ibm-mas-deployer-safety:cpst3 ibm-mas-deployer-visualinspection:cpst3 ibm-mas-internalapi:cpst3 ibm-mas-sbo-view:cpst3 ibm-mas.v8.11.6-84ddc59d5c openshift-pipelines-clusterinterceptors; do oc get clusterrolebindings $i -o yaml >backup/$NUM/clusterrolebindings/$i.yaml;  done

for i in `oc get truststores | grep -v NAME | awk '{print $1}' | xargs`; do oc get truststores $i -o yaml >backup/$NUM/truststores/$i.yaml;  done

for i in `oc get jobs | grep -v NAME | awk '{print $1}' | xargs`; do oc get jobs $i -o yaml >backup/$NUM/jobs/$i.yaml;  done
