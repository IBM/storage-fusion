#!/bin/bash

# Script to generate isf-resource config map which will contain the memory and cpu limit of the containers listed in the Fusion CSV

# json struct to hold the resource data
resource_json="{}"

# Get the Fusion subscription and its namespace
sub=$(oc get sub -A -ojson | jq -r '.items[] | select(.spec.name == "isf-operator")')
ns=$(echo $sub | jq -r '.metadata.namespace')

# Get the Fusion CSV
csv_name=$(echo $sub | jq -r '.status.installedCSV')
csv=$(oc get csv $csv_name -n $ns -ojson)

deployments=$(echo $csv | jq '.spec.install.spec.deployments') # Holds the deployment data listed in the Fusion CSV

# Generate the json data containing cpu and memory limits of each deployment/container
for deployment in $(echo $deployments | jq -c '.[]'); do
    dep_name=$(echo $deployment | jq -r '.name')

    containers_json="{}"

    containers=$(echo $deployment | jq -c '.spec.template.spec.containers') # Holds the containers listed in each deployment

    for container in $(echo "$containers" | jq -c '.[]'); do
        container_name=$(echo $container | jq -r '.name')
        cpu_limit=$(echo $container | jq -r '.resources.limits.cpu')
        memory_limit=$(echo $container | jq -r '.resources.limits.memory')

        container_details=$( jq -n \
            --arg container_name "$container_name"\
            --arg cpu_limit "$cpu_limit"\
            --arg memory_limit "$memory_limit"\
            '{$container_name: {resources: {limits: {cpu: $cpu_limit, memory: $memory_limit}}}}'
        )

        containers_json=$(echo "$containers_json" | jq --argjson container_details "$container_details" '. + $container_details')
    done
    resource_json=$(echo "$resource_json" | jq \
        --arg dep_name "$dep_name" \
        --argjson containers_json "$containers_json" \
        '. + {$dep_name: {containers: $containers_json}}')
done

# Data to be added to the isf-resources configmap
cm_data=$(echo "$resource_json" | jq -c .)

# Create the isf-resource configmap
oc create configmap isf-resources -n $ns \
    --from-literal=isf_resources.json=$cm_data \
