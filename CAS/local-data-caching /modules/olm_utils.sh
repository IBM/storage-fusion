#!/usr/bin/env bash
set -eu

#----------------------------------------
# Function: Check if Fusion operator is installed (HCI or SDS)
#----------------------------------------
is_operator_installed() {
	local package_name="$1"

	logger info "Checking if operator '$package_name' is installed..."

	local csv_info
	csv_info=$(oc get csv -A --no-headers -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,PHASE:.status.phase 2>/dev/null | grep "$package_name")

	if [[ -z "$csv_info" ]]; then
		logger info "Operator '$package_name' not found."
		return 0
	fi

	local operator_namespace phase
	operator_namespace=$(echo "$csv_info" | awk '{print $1}')
	phase=$(echo "$csv_info" | awk '{print $3}')

	if [[ "$phase" == "Succeeded" ]]; then
		logger success "Operator '$package_name' is installed and in Succeeded phase (namespace: $operator_namespace)."
		is_operator_version_supported "$package_name" "-n $operator_namespace" "$FUSION_MINIMUM_VERSION"
		echo "-n $operator_namespace"
	else
		logger info "Operator '$package_name' is not ready (phase: $phase). Cleanup and rerun."
		return 1
	fi
}

#----------------------------------------
# Function: Check if operator version is supported
#----------------------------------------
is_operator_version_supported() {
	local package_name="$1"
	local namespace_flag="$2"
	local target_version="$3"

	local installed_version
	installed_version=$(oc get csv $namespace_flag --no-headers -o custom-columns=NAME:.metadata.name,VERSION:.spec.version 2>/dev/null |
		grep "$package_name" | awk '{print $2}' | head -n1)

	if [[ "$(printf '%s\n%s\n' "$target_version" "$installed_version" | sort -V | head -n1)" == "$target_version" ]]; then
		return 0
	else
		logger error "Version mismatch: Operator '$package_name' version $installed_version is not supported. Minimum required: $target_version."
		return 1
	fi
}

#----------------------------------------
# Function: Get catalogsource for packagemanifest
#----------------------------------------
get_operator_package_catalog() {
	local package_name="$1"

	echo "$(oc get packagemanifests "$package_name" -o jsonpath='{.status.catalogSourceNamespace}{"/"}{.status.catalogSource}' 2>/dev/null)"
}

#----------------------------------------
# Function: Ensure operator packagemanifest exists
#----------------------------------------
ensure_operator_package() {
	local package_name="$1"
	local catalog_name="$2"
	local template_path="$3"

	logger info "Ensuring catalog source '$catalog_name' exists..."

	local found_namespace
	found_namespace=$(oc get catalogsource -A | grep "$catalog_name" | awk '{print $1}' | head -n 1)

	if [[ -n "$found_namespace" ]]; then
		logger info "Catalog source '$catalog_name' found in namespace '$found_namespace'."
		export CATALOG_NAMESPACE="$found_namespace"
	else
		logger info "Catalog source '$catalog_name' not found. Creating in '$CATALOG_NAMESPACE'..."
	fi

	if envsubst <"$template_path" | oc apply -f - &>/dev/null; then
		logger info "Catalog source '$catalog_name' configured..."
	else
		logger error "Operation failed: Unable to create catalog source '$catalog_name'."
		return 1
	fi

	logger info "Waiting for catalog '$catalog_name' to become available (timeout: $CATALOG_WAIT_TIMEOUT)..."

	if oc wait --for=jsonpath='{.status.connectionState.lastObservedState}'=READY \
		catalogsource/"$catalog_name" \
		-n "$CATALOG_NAMESPACE" \
		--timeout="$CATALOG_WAIT_TIMEOUT" &>/dev/null; then
		logger success "Catalog '$catalog_name' is available."
	else
		local retry_count=0
		while ! oc get packagemanifests -n "$CATALOG_NAMESPACE" 2>/dev/null | grep -q "$package_name"; do
			((++retry_count))
			if [[ $retry_count -ge $RETRY_COUNT ]]; then
				logger error "Timeout: Catalog '$catalog_name' did not become available after $((RETRY_COUNT * RETRY_INTERVAL)) seconds."
				return 1
			fi
			logger info "Catalog not available yet... retrying in ${RETRY_INTERVAL}s ($retry_count/$RETRY_COUNT)"
			sleep "$RETRY_INTERVAL"
		done
		logger success "Catalog '$catalog_name' is now available."
	fi
}

#----------------------------------------
# Function: Verify all catalog sources are READY
#----------------------------------------
verify_catalog_sources() {
	logger info "Verifying catalog sources health in cluster..."
	local unhealthy=0
	local catalogs
	catalogs=$(oc get catalogsource -A --no-headers 2>/dev/null || echo "")

	if [[ -z "$catalogs" ]]; then
		logger error "No catalog sources found in cluster!"
		return 1
	fi

	while read -r ns name _; do
		local state
		state=$(oc get catalogsource "$name" -n "$ns" -o jsonpath='{.status.connectionState.lastObservedState}' 2>/dev/null || echo "")
		if [[ "$state" != "READY" ]]; then
			logger error "CatalogSource '$name' in namespace '$ns' is not READY (state: ${state:-Unknown})."
			unhealthy=1
		fi
	done <<<"$catalogs"

	if [[ $unhealthy -eq 0 ]]; then
		logger success "All catalog sources are READY."
	else
		logger error "One or more catalog sources are not ready. Please fix before proceeding since any unhealthy catalog source in cluster results in failure of OLM operations."
		return 1
	fi
}

#----------------------------------------
# Function: Ensure OperatorGroup exists
#----------------------------------------
ensure_operator_group() {
	local namespace="$1"
	local template_path="$2"

	logger info "Checking for OperatorGroup in namespace '$namespace'..."

	# Get all operatorgroups in the namespace
	local og_count
	og_count=$(oc get operatorgroup -n "$namespace" --no-headers 2>/dev/null | wc -l | xargs)

	# No operatorgroup found — create one
	if [[ "$og_count" -eq 0 ]]; then
		logger info "No OperatorGroup found. Creating..."
		if envsubst <"$template_path" | oc apply -f - >/dev/null 2>&1; then
			logger success "OperatorGroup created successfully in namespace '$namespace'."
		else
			logger error "Operation failed: Unable to create OperatorGroup in namespace '$namespace'."
			return 1
		fi

	# Exactly one operatorgroup — valid
	elif [[ "$og_count" -eq 1 ]]; then
		local og_name
		og_name=$(oc get operatorgroup -n "$namespace" --no-headers | awk '{print $1}')
		logger success "Valid OperatorGroup '$og_name' already exists in namespace '$namespace'."

	# More than one operatorgroup — invalid
	else
		logger error "Multiple OperatorGroups ($og_count) found in namespace '$namespace'. Only one OperatorGroup is allowed per namespace. Please remove the extra ones and retry."
		oc get operatorgroup -n "$namespace"
		return 1
	fi
}

#----------------------------------------
# Function: Create and verify Subscription
#----------------------------------------
apply_subscription() {
	local template_path="$1"

	logger info "Creating Fusion Subscription..."
	if envsubst <"$template_path" | oc apply -f -; then
		logger success "Fusion Subscription applied successfully."
	else
		logger error "Operation failed: Unable to create Fusion Subscription."
		return 1
	fi
}

#----------------------------------------
# Function: Wait for CSV to reach 'Succeeded'
#----------------------------------------
wait_for_csv_success() {
	local namespace="$1"
	local package_name="$2"

	logger info "Waiting for CSV of operator '$package_name' to become 'Succeeded' (timeout: $CSV_WAIT_TIMEOUT)..."

	local retry_count=0
	local csv_name=""

	while [[ -z "$csv_name" ]]; do
		csv_name=$(oc get csv -n "$namespace" --no-headers 2>/dev/null | grep "$package_name" | awk '{print $1}' | head -n1 || echo "")
		if [[ -z "$csv_name" ]]; then
			((++retry_count))
			if [[ $retry_count -ge 10 ]]; then
				logger error "Operation failed: CSV for operator '$package_name' not found after $((retry_count * RETRY_INTERVAL)) seconds."
				return 1
			fi
			logger info "CSV not found yet... waiting ${RETRY_INTERVAL}s ($retry_count/10)"
			sleep "$RETRY_INTERVAL"
		fi
	done

	logger info "Found CSV: $csv_name. Waiting for Succeeded status..."

	# Wait until the CSV phase becomes 'Succeeded'
	if oc wait csv/"$csv_name" \
		-n "$namespace" \
		--for=jsonpath='{.status.phase}'=Succeeded \
		--timeout="$CSV_WAIT_TIMEOUT" 2>/dev/null; then
		logger success "Operator '$package_name' CSV reached 'Succeeded' state."
		return 0
	else
		logger warn "oc wait failed, falling back to manual status check..."
		retry_count=0
		while true; do
			csv_status=$(oc get csv "$csv_name" -n "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Pending")
			if [[ "$csv_status" == "Succeeded" ]]; then
				logger success "Operator '$package_name' CSV reached 'Succeeded' state."
				return 0
			fi
			((++retry_count))
			if [[ $retry_count -ge $RETRY_COUNT || "$csv_status" == "Failed" ]]; then
				logger error "Operation failed: Operator '$package_name' CSV did not reach 'Succeeded' state (Status: $csv_status) after $((RETRY_COUNT * RETRY_INTERVAL)) seconds."
				return 1
			fi
			logger info "Current CSV status: $csv_status. Retrying in ${RETRY_INTERVAL}s ($retry_count/$RETRY_COUNT)..."
			sleep "$RETRY_INTERVAL"
		done
	fi
}
