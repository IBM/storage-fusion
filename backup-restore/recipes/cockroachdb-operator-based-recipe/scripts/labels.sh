oc label customresourcedefinitions crdbclusters.crdb.cockroachlabs.com custom-label=cockroach-operator-crd
oc label clusterrole cockroach-operator-role app=cockroach-operator
oc label clusterrolebinding cockroach-operator-rolebinding app=cockroach-operator
oc label service cockroach-operator-webhook-service app=cockroach-operator
oc label mutatingwebhookconfiguration cockroach-operator-mutating-webhook-configuration app=cockroach-operator
oc label validatingwebhookconfiguration cockroach-operator-validating-webhook-configuration app=cockroach-operator