oc label crd backups.mariadb.mmontes.io custom-label=mariadb
oc label crd connections.mariadb.mmontes.io custom-label=mariadb
oc label crd databases.mariadb.mmontes.io custom-label=mariadb
oc label crd grants.mariadb.mmontes.io custom-label=mariadb
oc label crd mariadbs.mariadb.mmontes.io custom-label=mariadb
oc label crd restores.mariadb.mmontes.io custom-label=mariadb
oc label crd sqljobs.mariadb.mmontes.io custom-label=mariadb
oc label crd users.mariadb.mmontes.io custom-label=mariadb

oc label clusterrole mariadb-operator custom-label=mariadb
oc label clusterrolebinding mariadb-operator custom-label=mariadb
oc label clusterrolebinding mariadb-operator:auth-delegator custom-label=mariadb