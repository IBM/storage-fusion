#!/bin/bash

echo "=== bascfgs.config.mas.ibm.com ==="
oc get bascfgs.config.mas.ibm.com cpst3-bas-system -o json | jq '.spec.config.url'

echo -e "\n=== coreidps.internal.mas.ibm.com ==="
oc get coreidps.internal.mas.ibm.com cpst3-coreidp -o json | jq '.spec.domain'

echo -e "\n=== kafkacfgs.config.mas.ibm.com ==="
oc get kafkacfgs.config.mas.ibm.com cpst3-kafka-system -o json | jq '{host:.spec.config.hosts[0].host, displayName:.spec.displayName}' 

echo -e "\n=== slscfgs.config.mas.ibm.com ==="
oc get slscfgs.config.mas.ibm.com cpst3-sls-system -o json | jq '.spec.config.url'

echo -e "\n=== suites.core.mas.ibm.com ==="
oc get suites.core.mas.ibm.com cpst3 -o json | jq '.spec.domain'

echo -e "\n=== watsonstudiocfgs.config.mas.ibm.com ==="
oc get watsonstudiocfgs.config.mas.ibm.com cpst3-watsonstudio-system -o json | jq '{endpoint:.spec.config.endpoint, displayName:.spec.displayName}'
