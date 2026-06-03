#!/bin/bash

# Hardware utility functions for IBM Storage Fusion HCI pre-upgrade healthcheck
# This file contains functions for verifying node hardware and firmware status

# Verify node hardware status
# Checks all nodes from kickstart ConfigMaps and their hardware health
# Distinguishes between base OCP nodes, HCP nodes, and nodes not yet in OCP
function verify_nodes_hw(){
  print info "Verify node hardware status"
  local nodeStatus=0
  local healthyCount=0
  local unhealthyCount=0
  local notInOCPCount=0
  local hcpNodeCount=0
  local integrationFailureCount=0
  local totalNodesInKickstart=0
  local nodesWithMonitoring=0
  
  # Get all nodes from all kickstart ConfigMaps referenced in applianceinfo
  # Use serial number as primary key for correlation
  # Note: Using space-separated lists instead of associative arrays for Bash 3.2 compatibility
  local allNodesFromKickstart=""  # Format: "serialNum:OCPRole:immIP serialNum:OCPRole:immIP ..."
  local checkedNodes=""            # Format: "serialNum serialNum ..."
  
  # Read applianceinfo ConfigMap to get all kickstart CM names
  local applianceInfoData=$(oc get configmap appliance-info -n ${FUSIONNS} -o json 2>/dev/null)
  if [[ $? -ne 0 ]]; then
    print error "${CHECK_FAIL} Failed to get appliance-info ConfigMap"
    return 1
  fi
  
  # Extract all kickstart CM names from applianceinfo
  local kickstartCMs=$(echo "$applianceInfoData" | jq -r '.data | to_entries[] | .value' | jq -r '.kickstartCM' 2>/dev/null | grep -v '^null$' | sort -u)
  
  if [[ -z "$kickstartCMs" ]]; then
    print error "${CHECK_FAIL} No kickstart ConfigMaps found in appliance-info"
    return 1
  fi
  
  # Collect all nodes from all kickstart ConfigMaps
  while IFS= read -r ksCM; do
    if [[ -n "$ksCM" ]]; then
      local ksData=$(oc get configmap "$ksCM" -n ${FUSIONNS} -o json 2>/dev/null)
      if [[ $? -eq 0 ]]; then
        # Extract nodes from kickstart (computeNodeIntegratedManagementModules)
        local nodeCount=$(echo "$ksData" | jq -r '.data."kickstart.json"' | jq '.computeNodeIntegratedManagementModules | length' 2>/dev/null)
        if [[ "$nodeCount" =~ ^[0-9]+$ ]] && [[ $nodeCount -gt 0 ]]; then
          for ((i=0; i<nodeCount; i++)); do
            local serialNum=$(echo "$ksData" | jq -r ".data.\"kickstart.json\"" | jq -r ".computeNodeIntegratedManagementModules[$i].serialNum" 2>/dev/null)
            local immIP=$(echo "$ksData" | jq -r ".data.\"kickstart.json\"" | jq -r ".computeNodeIntegratedManagementModules[$i].ipv4" 2>/dev/null)
            local nodeRole=$(echo "$ksData" | jq -r ".data.\"kickstart.json\"" | jq -r ".computeNodeIntegratedManagementModules[$i].OCPRole" 2>/dev/null)
            if [[ -n "$serialNum" && "$serialNum" != "null" ]]; then
              # Store as space-separated list: "serialNum:nodeRole:immIP"
              allNodesFromKickstart="$allNodesFromKickstart $serialNum:$nodeRole:$immIP"
              totalNodesInKickstart=$((totalNodesInKickstart + 1))
            fi
          done
        fi
      fi
    fi
  done <<< "$kickstartCMs"
  
  if [[ $totalNodesInKickstart -eq 0 ]]; then
    print error "${CHECK_FAIL} No nodes found in kickstart ConfigMaps"
    return 1
  fi
  
  print info "Found $totalNodesInKickstart nodes in kickstart ConfigMaps"
  
  # Now check hardware status for each computemonitoring CR
  rm -f ${TEMP_MMHEALTH_FILE} >> /dev/null
  while read -r proc; do echo $proc >> ${TEMP_MMHEALTH_FILE}; done <<< "$(oc get computemonitoring -n ${FUSIONNS} --no-headers 2>/dev/null)"
  
  while IFS= read -r line; do
    if [[ -z "$line" ]]; then
      continue
    fi
    
    monitoringCRD=$(echo $line | awk '{print $1}')
    nodesWithMonitoring=$((nodesWithMonitoring + 1))
    
    # Get node details from computemonitoring CR
    local nodeData=$(oc get computemonitoring -n ${FUSIONNS} $monitoringCRD -o json 2>/dev/null)
    if [[ $? -ne 0 ]]; then
      continue
    fi
    
    local serialNum=$(echo "$nodeData" | jq -r '.status.nodes[0].systemSerialNumber // empty')
    local immIP=$(echo "$nodeData" | jq -r '.spec.nodes[0].ip // empty')
    local ocpNodeName=$(echo "$nodeData" | jq -r '.status.nodes[0].ocpNodeName // empty')
    local nodeHwStatus=$(echo "$nodeData" | jq -r '.status.nodes[0].nodeMonStatus.state // empty')
    local acmMember=$(echo "$nodeData" | jq -r '.status.nodes[0].acmMember // false')
    
    # Get node role from kickstart using serial number (search in space-separated list)
    local nodeRole=""
    local ksImmIP=""
    for nodeEntry in $allNodesFromKickstart; do
      local entrySN=$(echo "$nodeEntry" | cut -d':' -f1)
      if [[ "$entrySN" == "$serialNum" ]]; then
        nodeRole=$(echo "$nodeEntry" | cut -d':' -f2)
        ksImmIP=$(echo "$nodeEntry" | cut -d':' -f3)
        break
      fi
    done
    
    # Mark this node as checked
    if [[ -n "$serialNum" ]]; then
      checkedNodes="$checkedNodes $serialNum"
    fi
    
    # Check for integration failure by examining conditions
    local hasError=$(echo "$nodeData" | jq -r '.status.conditions[] | select(.type=="Error" and .status=="True") | .type' 2>/dev/null)
    
    # Determine node status and display appropriate message
    if [[ -n "$hasError" ]]; then
      nodeStatus=1
      integrationFailureCount=$((integrationFailureCount + 1))
      local errorMsg=$(echo "$nodeData" | jq -r '.status.conditions[] | select(.type=="Error") | .message' 2>/dev/null)
      print error "${CHECK_FAIL} $monitoringCRD ($nodeRole, S/N: $serialNum, IMM IP: $immIP) shows integration failure: $errorMsg"
    elif [[ "$acmMember" == "true" ]]; then
      # Node is part of HCP cluster
      hcpNodeCount=$((hcpNodeCount + 1))
      if [[ "$nodeHwStatus" != "Succeeded" && "$nodeHwStatus" != "\"Succeeded\"" && -n "$nodeHwStatus" ]]; then
        nodeStatus=1
        unhealthyCount=$((unhealthyCount + 1))
        print error "${CHECK_FAIL} $monitoringCRD ($nodeRole, S/N: $serialNum, IMM IP: $immIP) [HCP node] hardware is not healthy (status: $nodeHwStatus)"
      else
        healthyCount=$((healthyCount + 1))
      fi
    elif [[ -z "$ocpNodeName" || "$ocpNodeName" == "null" ]]; then
      notInOCPCount=$((notInOCPCount + 1))
      print info "${CHECK_UNKNOW} $monitoringCRD ($nodeRole, S/N: $serialNum, IMM IP: $immIP) is not part of OCP yet"
    elif [[ "$nodeHwStatus" != "Succeeded" && "$nodeHwStatus" != "\"Succeeded\"" && -n "$nodeHwStatus" ]]; then
      nodeStatus=1
      unhealthyCount=$((unhealthyCount + 1))
      print error "${CHECK_FAIL} $ocpNodeName ($nodeRole, S/N: $serialNum, IMM IP: $immIP) hardware is not healthy (status: $nodeHwStatus)"
    else
      healthyCount=$((healthyCount + 1))
    fi
  done < ${TEMP_MMHEALTH_FILE}
  
  # Check for nodes in kickstart that don't have computemonitoring CRs
  local missingMonitoringCount=0
  for nodeEntry in $allNodesFromKickstart; do
    local serialNum=$(echo "$nodeEntry" | cut -d':' -f1)
    local nodeRole=$(echo "$nodeEntry" | cut -d':' -f2)
    local immIP=$(echo "$nodeEntry" | cut -d':' -f3)
    
    # Check if this serial number was checked
    local wasChecked=0
    for checkedSN in $checkedNodes; do
      if [[ "$checkedSN" == "$serialNum" ]]; then
        wasChecked=1
        break
      fi
    done
    
    if [[ $wasChecked -eq 0 ]]; then
      missingMonitoringCount=$((missingMonitoringCount + 1))
      print info "${CHECK_UNKNOW} Node $nodeRole (S/N: $serialNum, IMM IP: $immIP) from kickstart has no computemonitoring CR"
    fi
  done
  
  rm -f ${TEMP_MMHEALTH_FILE} >> /dev/null
  
  # Print summary
  print_subsection
  print info "Hardware Status Summary:"
  print info "  Total nodes in kickstart: $totalNodesInKickstart"
  print info "  Nodes with computemonitoring CR: $nodesWithMonitoring"
  print info "  Healthy nodes: $healthyCount"
  print info "  Unhealthy nodes: $unhealthyCount"
  print info "  Integration failures: $integrationFailureCount"
  print info "  HCP cluster nodes: $hcpNodeCount"
  print info "  Not in OCP yet: $notInOCPCount"
  print info "  Missing monitoring CR: $missingMonitoringCount"
  
  if [ $nodeStatus -eq 0 ]; then
    if [ $unhealthyCount -eq 0 ] && [ $integrationFailureCount -eq 0 ]; then
      print info "${CHECK_PASS} All nodes with hardware monitoring are healthy"
    fi
  else
    print error "${CHECK_FAIL} Some nodes have hardware issues or integration failures"
  fi
}

# Verify node firmware status
# Checks if nodes require firmware updates
function verify_nodes_fw(){
  print info "Verify node firmware status"
  nodeStatus=0
  rm -f ${TEMP_MMHEALTH_FILE} >> /dev/null
  while read -r proc; do echo $proc >> ${TEMP_MMHEALTH_FILE}; done <<< "$(oc get cfw -n ${FUSIONNS} --no-headers )"
  while IFS= read -r line
    do
      firmwareCR=$(echo $line |awk '{print $1}')
      monitorCR="monitoring-c"`echo $firmwareCR | cut -f2 -d'c'`
      configuredNode=$(oc get computemonitoring -n ${FUSIONNS} $monitorCR -o json | jq .status.nodes[].ocpNodeName)
      #check only configured nodes, not discovered one
      if [[ "${configuredNode}" == null ]]; then
        print error "$monitorCR is not part of OCP yet."
      else
        nodeFwStatus=$(oc get computefirmware -n ${FUSIONNS} $firmwareCR -o json | jq .status.updateRequired)
        if [[ "$nodeFwStatus" == "true" ]]; then
           nodeStatus=1
           print error "${CHECK_FAIL} ${configuredNode} firmware is not at latest level."
        fi
      fi
    done < ${TEMP_MMHEALTH_FILE}
  rm -f ${TEMP_MMHEALTH_FILE} >> /dev/null
  if [ $nodeStatus -eq 0 ]; then
    print info "${CHECK_PASS} All configured nodes are at latest firmware level."
  fi
}

# Made with Bob
