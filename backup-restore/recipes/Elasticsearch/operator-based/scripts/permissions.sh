elasticsearch_permissions() {
    # Patch ClusterRole only if rule doesn't already exist
    echo "============>  Checking and patching ClusterRole..."
    
    echo "============>  For elasticsearches.elasticsearch.k8s.elastic.co..."
    EXISTING_RULE=$(oc get clusterrole transaction-manager-ibm-backup-restore -o json | \
      jq '.rules[] | select(.apiGroups == ["elasticsearch.k8s.elastic.co"] and .resources == ["elasticsearches"] and (.verbs | index("get") and index("list")))' )
    
    if [ -z "$EXISTING_RULE" ]; then
      echo "============>  Rule not present. Patching ClusterRole..."
      oc get clusterrole transaction-manager-ibm-backup-restore -o json | \
        jq '.rules += [{"verbs":["get","list"],"apiGroups":["elasticsearch.k8s.elastic.co"],"resources":["elasticsearches"]}]' | \
        oc apply -f -
      echo "============>  ClusterRole patched successfully."
    else
      echo "============>  ClusterRole already has the required rule. No action taken."
    fi
    
    echo "============>  For kibanas.kibana.k8s.elastic.co..."
    EXISTING_RULE=$(oc get clusterrole transaction-manager-ibm-backup-restore -o json | \
      jq '.rules[] | select(.apiGroups == ["kibana.k8s.elastic.co"] and .resources == ["kibanas"] and (.verbs | index("get") and index("list")))' )
    
    if [ -z "$EXISTING_RULE" ]; then
      echo "============>  Rule not present. Patching ClusterRole..."
      oc get clusterrole transaction-manager-ibm-backup-restore -o json | \
        jq '.rules += [{"verbs":["get","list"],"apiGroups":["kibana.k8s.elastic.co"],"resources":["kibanas"]}]' | \
        oc apply -f -
      echo "============>  ClusterRole patched successfully."
    else
      echo "============>  ClusterRole already has the required rule. No action taken."
    fi
}
