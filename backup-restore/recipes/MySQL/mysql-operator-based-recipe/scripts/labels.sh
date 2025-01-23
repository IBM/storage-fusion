oc label crd innodbclusters.mysql.oracle.com custom-label=mysql-operator-crd
oc label crd mysqlbackups.mysql.oracle.com custom-label=mysql-operator-crd
oc label crd clusterkopfpeerings.zalando.org custom-label=mysql-operator-crd
oc label crd kopfpeerings.zalando.org custom-label=mysql-operator-crd

oc label clusterrole mysql-operator custom-label=mysql-operator
oc label clusterrole mysql-sidecar custom-label=mysql-operator
oc label clusterrolebinding mysql-operator-rolebinding custom-label=mysql-operator
oc label clusterkopfpeering mysql-operator custom-label=mysql-operator

oc label serviceaccount mysql-operator-sa custom-label=mysql-operator

oc label deployment mysql-operator custom-label=mysql-operator

oc label secret mysql-c1-root-user-creds custom-label=mysql-innodbcluster 

oc label secret mysql-c1-privsecrets custom-label=mysql-innodbcluster-post
oc label secret mysql-c1-router custom-label=mysql-innodbcluster-post
oc label secret mysql-c1-backup custom-label=mysql-innodbcluster-post