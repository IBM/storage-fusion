#!/bin/bash

# Check if the NAMESPACE argument is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <namespace>"
  exit 1
fi

# Set the namespace from the first argument
NAMESPACE=$1


# Set the Neo4j password (replace with your actual password)
export NEO4J_PASSWORD=$(kubectl get secrets neo4j-cluster-neo4j-secrets --namespace "$NAMESPACE" -o jsonpath='{.data.neo4j-password}' | base64 -d)


# Run the kubectl command and filter the output to get the pod name
output=$(kubectl run -it --rm cypher-shell \
            --image=neo4j:4.4.9-enterprise \
            --restart=Never \
            --namespace "$NAMESPACE" \
            --command -- ./bin/cypher-shell -u neo4j -p "$NEO4J_PASSWORD" -a neo4j://neo4j-cluster-neo4j.neo4j-cluster.svc.cluster.local "CALL dbms.routing.getRoutingTable({}, 'system') YIELD ttl, servers
            UNWIND servers AS server
            WITH server
            WHERE server.role = 'WRITE'
            RETURN head(split(head(server.addresses), '.')) AS podName;")

REPLACE_WRITER_POD_NAME=$(echo $output | awk -F'"' '/podName/ {print $2}')
# Output the pod name
echo "Write server pod name: $REPLACE_WRITER_POD_NAME"


awk -v WRITER_POD_NAME="$REPLACE_WRITER_POD_NAME" '{gsub(/\$REPLACE_WRITER_POD_NAME/, WRITER_POD_NAME)}1' neo4j-cluster-backup-restore-template.yaml > neo4j-cluster-backup-restore.yaml


