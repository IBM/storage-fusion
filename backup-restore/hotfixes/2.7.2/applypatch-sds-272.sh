#!/bin/bash

BR_NS=$(oc get dataprotectionserver -A --no-headers -o custom-columns=NS:metadata.namespace)
ISF_NS=$(oc get spectrumfusion -A -o custom-columns=NS:metadata.namespace --no-headers)

[ -n "$BR_NS" ] && HUB=true
echo "Saving data before applying SDS patch..."
if [ -n "$HUB" ]
 then
   echo " This is hub"
   oc get deployment -n $BR_NS backup-service -o yaml > backup-service-deployment.save.yaml
   echo "Saved backup-service deployment"
   oc get clusterrole backup-service-role-ibm-backup-restore -o yaml > backup-service-role.save.yaml
   echo "Saved backup-service clusterrole"
   oc get deployment -n $BR_NS job-manager  -o yaml > job-manager-deployment.save.yaml
   echo "Saved job-manager deployment"
   oc get recipes.spp-data-protection.isf.ibm.com fusion-control-plane -n $ISF_NS -o yaml > fusion-control-plane-recipe.save.yaml
   echo "Saved fusion-control-plane recipe"
   oc get deployment -n $BR_NS backup-location-deployment -o yaml > backup-location-deployment.save.yaml
   echo "Saved backup-location-deployment"
 else
   echo "This is spoke" 
fi

oc get deployment -n $BR_NS transaction-manager -o yaml > transaction-manager-deployment.save.yaml
echo "Saved transaction-manager deployment"
oc get deployment -n $BR_NS application-controller -o yaml > application-controller-deployment.save.yaml
echo "Saved application-controller deployment"
echo "Deleting clusterrole guardian-dm-datamover-scc"
oc delete clusterrole guardian-dm-datamover-scc

if [ -n "$HUB" ]
 then
  echo "Patching backup-service deployment..."
  oc patch deployment backup-service -n $BR_NS -p '{"spec":{"template":{"spec":{"containers":[{"name":"backup-service","image":"cp.icr.io/cp/fbr/guardian-backup-service@sha256:54820def941c9ebfde1acca54368b9bc7cd34fedfa94151deb8a6766aeedc505","resources":{"limits":{"ephemeral-storage":"1Gi"},"requests":{"ephemeral-storage":"512Mi"}},"env":[{"name":"POD_NAMESPACE","valueFrom":{"fieldRef":{"apiVersion":"v1","fieldPath":"metadata.namespace"}}}],"volumeMounts":[{"name":"tls-service-ca","readOnly":true,"mountPath":"/etc/tls-service-ca"},{"name":"spdata","mountPath":"/spdata"}]}],"volumes":[{"name":"tls-service-ca","configMap":{"name":"guardian-service-ca","defaultMode":292}},{"name":"spdata","emptyDir":{}}]}}}}'

  echo "Patching backup-service clusterrole..."
  oc patch clusterrole backup-service-role-ibm-backup-restore --type=json -p '[{"op":"add","path":"/rules/-","value":{"verbs":["get"],"apiGroups":[""],"resources":["secrets"]}}]'

  echo "Patching job-manager deployment..."
  oc patch deployment job-manager -n $BR_NS -p '{"spec":{"template":{"spec":{"containers":[{"env":[{"name":"cancelJobAfter","value":"28800000"}],"name":"job-manager-container"}]}}}}'
  
  echo "Patching fusion-control-plane recipe..."
  oc patch recipes.spp-data-protection.isf.ibm.com fusion-control-plane -n $ISF_NS --type=merge -p '{"spec":{"hooks":[{"name":"fbr-hooks","nameSelector":"transaction-manager.*","namespace":"${FBR_NAMESPACE}","onError":"fail","ops":[{"command":"[\"/usr/src/app/code/.venv/bin/python3\",\"/usr/src/app/code/ctl-plane.pyc\",\"backup\"]","container":"transaction-manager","name":"export-backup-inventory"},{"command":"[\"/usr/src/app/code/.venv/bin/python3\",\"/usr/src/app/code/ctl-plane.pyc\",\"restore\"]","container":"transaction-manager","name":"restore-backup-inventory","timeout":28800},{"command":"[\"/usr/src/app/code/.venv/bin/python3\",\"/usr/src/app/code/ctl-plane.pyc\",\"deleteCRs\"]","container":"transaction-manager","name":"deleteCRs","timeout":28800}],"selectResource":"pod","singlePodOnly":true,"type":"exec"},{"name":"isf-dp-operator-hook","nameSelector":"transaction-manager.*","namespace":"${FBR_NAMESPACE}","onError":"fail","ops":[{"command":"[\"/usr/src/app/code/.venv/bin/python3\",\"/usr/src/app/code/patch-isd-dp-cm.pyc\",\"${PARENT_NAMESPACE}\",\"isf-data-protection-config\",\"DisableWebhook\"]","container":"transaction-manager","name":"disable-webhook"},{"command":"[\"/usr/src/app/code/.venv/bin/python3\",\"/usr/src/app/code/patch-isd-dp-cm.pyc\",\"${PARENT_NAMESPACE}\",\"isf-data-protection-config\",\"Recover\"]","container":"transaction-manager","name":"quiesce-isf-dp-controller"},{"command":"[\"/usr/src/app/code/.venv/bin/python3\",\"/usr/src/app/code/patch-isd-dp-cm.pyc\",\"${PARENT_NAMESPACE}\",\"isf-data-protection-config\",\"Normal\"]","container":"transaction-manager","name":"unquiesce-isf-dp-controller"}],"selectResource":"pod","singlePodOnly":true,"type":"exec"},{"name":"appcontroller-restart","nameSelector":"application-controller","namespace":"${FBR_NAMESPACE}","onError":"fail","selectResource":"deployment","type":"scale"}]}}'

  echo "Patching backup-location-deployment..."
  oc patch deployment backup-location-deployment -n $BR_NS -p '{"spec":{"template":{"spec":{"containers":[{"name":"backup-location-container","image":"cp.icr.io/cp/fbr/guardian-backup-location@sha256:7abd42c19eea0e23618fd84d3e1335b51b959d232f88ea1db2a0c2391bc241c3"}]}}}}'
fi

echo "Patching transaction-manager deployment..."
oc patch deployment/transaction-manager -n $BR_NS -p '{"spec":{"template":{"spec":{"containers":[{"name":"transaction-manager","image":"cp.icr.io/cp/fbr/guardian-transaction-manager@sha256:f7e325d1a051dfacfe18139e46a668359a9c11129870a4b2c4b3c2fdaec615eb"}]}}}}'

echo "Patching application-controller deployment..."
oc patch deployment/application-controller -n $BR_NS -p '{"spec":{"template":{"spec":{"containers":[{"name":"application-controller","image":"cp.icr.io/cp/fbr/guardian-transaction-manager@sha256:f7e325d1a051dfacfe18139e46a668359a9c11129870a4b2c4b3c2fdaec615eb"}]}}}}'

echo "Deployment rollout status..."
if [ -n "$HUB" ]
 then
  oc rollout status -n $BR_NS deployment backup-service  job-manager  transaction-manager application-controller backup-location-deployment
 else
  oc rollout status -n $BR_NS deployment transaction-manager application-controller
fi


DM_CSV=$(oc get csv -n $BR_NS | grep guardian-dm-operator | awk '{print $1}')
echo "Saving original guardian-dm-operator yaml"
oc get csv -n $BR_NS ${DM_CSV} -o yaml > guardian-dm-operator.v2.7.2-original.yaml
oc get configmap  -n $BR_NS guardian-dm-image-config -o yaml > guardian-dm-image-config-original.yaml
echo Updating data mover image...
oc set data -n $BR_NS cm/guardian-dm-image-config DM_IMAGE=icr.io/cpopen/guardian-datamover@sha256:1f72a26a9f9e5cb732c8447e5aad40a4574a59d13b80c45d4405b6cf3c61ffa0
echo Updating CSV $DM_CSV...
oc patch csv -n $BR_NS $DM_CSV  --type='json' -p='[{"op":"replace", "path":"/spec/install/spec/deployments/0/spec/template/spec/containers/1/image", "value":"icr.io/cpopen/guardian-dm-operator@sha256:36df2a2cacd66f5cf8c01297728cb59dabc013d3c8d0b4eae3d8e1770f3839ec"}]'

