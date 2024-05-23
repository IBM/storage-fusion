#!/bin/bash

BR_NS=$(oc get dataprotectionserver -A --no-headers -o custom-columns=NS:metadata.namespace)
ISF_NS=$(oc get spectrumfusion -A -o custom-columns=NS:metadata.namespace --no-headers)

[ -n "$BR_NS" ] && HUB=true
if [ -n "$HUB" ]
 then
   echo " This is hub"
   AMQ_VER=$(oc -n $BR_NS get csv -o custom-columns=:spec.version,:status.phase,:metadata.name | grep "Succeeded  *amqstreams" | cut -d" " -f1)
   if [ -n "$AMQ_VER" ]
     then
        KFK_VER=""
        [[ $AMQ_VER == 2.6* ]] && KFK_VER=3.6.0 && PR_VER=3.6
        [[ $AMQ_VER == 2.5* ]] && KFK_VER=3.5.0 && PR_VER=3.5
        [[ $AMQ_VER == 2.4* ]] && KFK_VER=3.4.0 && PR_VER=3.4
        OLD_VER=$(oc -n $BR_NS get kafkas.kafka.strimzi.io guardian-kafka-cluster -o custom-columns=:spec.kafka.version --no-headers)
        if [[ -z "$KFK_VER" ]] 
         then
            echo "WARNING: Could not determine Kafka version for AMQ version $AMQ_VER"
         elif [[ "$KFK_VER" == "$OLD_VER" ]]
         then
            echo "Kafka already $OLD_VER for AMQ $AMQ_VER"
         else
            echo "Setting Kafka version $KFK_VER for AMQ $AMQ_VER"
            PATCH='{"spec":{"kafka":{"version":"'${KFK_VER}'"}}}'
            oc -n $BR_NS patch kafkas.kafka.strimzi.io guardian-kafka-cluster -p "$PATCH" --type=merge

            PATCH='{"spec":{"kafka":{"config":{"inter.broker.protocol.version":"'${PR_VER}'"}}}}'
            oc -n $BR_NS patch kafkas.kafka.strimzi.io guardian-kafka-cluster -p "$PATCH" --type=merge
        fi
     else
        echo "WARNING: No successful installation of AMQ found"
   fi
 else
   BR_NS=$(oc get dataprotectionagent -A --no-headers -o custom-columns=NS:metadata.namespace)
   if [ -n "$BR_NS" ]
     then
        echo "This is spoke" 
     else
        echo "WARNING: No Backup and Restore installation found. Exiting" 
        exit 1
   fi
fi

echo "Saving original guardian-configmap yaml"
oc get configmap  -n $BR_NS guardian-configmap -o yaml > guardian-configmap-original.yaml
echo Updating default data mover pod resource settings...
oc set data -n $BR_NS cm/guardian-configmap datamoverJobpodCPURequest='0.1'
oc set data -n $BR_NS cm/guardian-configmap datamoverJobpodCPURequestRes='0.1'
oc set data -n $BR_NS cm/guardian-configmap datamoverJobpodEphemeralStorageRequest='400Mi'
oc set data -n $BR_NS cm/guardian-configmap datamoverJobpodEphemeralStorageRequestRes='400Mi'
oc set data -n $BR_NS cm/guardian-configmap datamoverJobpodMemoryRequest='4000Mi'
oc set data -n $BR_NS cm/guardian-configmap datamoverJobpodMemoryRequestRes='4000Mi'

