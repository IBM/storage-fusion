#!/bin/bash

set -e
set -u

echo "================================================================="
echo "This script will setup a squid proxy server on the mgen of the rack."
echo "Squid installation initiated!"

dnf install -y squid

if [[ $? -eq 0 ]]; then
    echo "Squid installed successfully."
else
    echo "Failed to install squid."
fi

echo "================================================================="
echo "Post install, starting squid service."

sudo systemctl start squid.service
if [[ $? -eq 0 ]]; then
    echo "Squid service started."
else
    echo "Failed to start squid."
fi

echo "================================================================="
echo "Enabling squid service"

sudo systemctl enable squid
if [[ $? -eq 0 ]]; then
    echo "Squid service enabled."
else
    echo "Failed to enable squid."
fi

echo "================================================================="
echo "Running command to look for private ip."

all_ips=$(ip -br a)

# Initialize variable to store internal IP
internal_ip=""

# Iterate through each IP address
for ip in $all_ips; do
    # Check if the IP address starts with 172.
    if [[ $ip =~ ^172\. ]]; then
        # Remove the subnet mask if present
        internal_ip=$(echo $ip | cut -d'/' -f1)
        break  # Exit the loop once we find the IP address
    fi
done

echo "INTERNAL_IP_IS:${internal_ip}"

echo "================================================================="
echo "Creating the whitelist file and adding sites!"

cat <<EOF > /etc/squid/sites.whitelist.txt
.docker.io
https://cloud.google.com/artifact-registry/
https://auth.docker.io
https://registry-1.docker.io/
https://index.docker.io/
https://mirrors.fedoraproject.org/
https://dseasb33srnrn.cloudfront.net
https://docker.io
https://registry.access.redhat.com/
hyc-abell-devops-team-dev-offline-docker-local.artifactory.swg-devops.com
hyc-abell-devops-team-qa-offline-docker-local.artifactory.swg-devops.com
hyc-abell-devops-team-mint-docker-local.artifactory.swg-devops.com
.docker-na-public.artifactory.swg-devops.com
.docker-na-public.artifactory.swg-devops.com:443
na.artificatory.swg.devops.com
na.artificatory.swg.devops.com:443
sys-spectrum-scale-team-cloud-native-docker-local.artifactory.swg-devops.com
.icr.io
registry.redhat.io
registry.connect.redhat.com
.quay.io
www.redhat.com
redhat.com
catalog.redhat.com
openshift.org
.openshift.com
nohost.com
gcr.io
.amazonaws.com
oso-rhc4tp-docker-registry.s3-us-west-2.amazonaws.com
rhc4tp-prod-z8cxf-image-registry-us-east-1-evenkyleffocxqvofrk.s3.dualstack.us-east-1.amazonaws.com
storage.googleapis.com
www.okd.io
.cloud.google.com
www.ibm.com
.mydomain.com
.dseasb33srnrn.cloudfront.net
www.secure.ecurep.ibm.com
sso.redhat.com
cloud.redhat.com
.access.redhat.com
okd.io
esupport.ibm.com
.docker.com
.console.redhat.com
s3.us-west-2.amazonaws.com
aws.amazon.com
s3.us-west-2.amazonaws.com
.s3.us-west-2.amazonaws.com
s3.us-south.cloud-object-storage.appdomain.cloud
dpcos1.blob.core.windows.net
EOF

CONF_FILE="/etc/squid/squid.conf"

echo "================================================================="
echo "Running commands to modify the squid.conf file!"

# Comment out the line containing http_access deny all after the pattern
sed -i "/^http_access deny all/s/^/#/" "$CONF_FILE"

# Insert lines after the line containing the specific pattern
sed -i "/# from where browsing should be allowed/a \
auth_param basic program /usr/lib64/squid/basic_ncsa_auth /etc/squid/users_passwd\n\
auth_param basic realm proxy\n\
acl whitelist dstdomain \"/etc/squid/sites.whitelist.txt\"\n\
http_access allow whitelist\n\
http_access deny all" "$CONF_FILE"

# Add the line http_access allow all after the line containing the specific pattern
sed -i "/# And finally deny all other access to this proxy/a http_access allow all" "$CONF_FILE"

if [[ $? -eq 0 ]]; then
    echo "Squid.conf file modified successfully."
else
    echo "Failed to modify squid.conf file."
fi

echo "================================================================="
echo "Running commands to setup the squid user-id and password. Please note details: user-id=squid and password=squid."

sudo dnf install -y httpd-tools

htpasswd -b -c /etc/squid/users_passwd squid squid

echo "================================================================="
echo "Restarting the squid service after modifying the squid.conf file!"

timeout 60 sudo systemctl restart squid.service

echo "================================================================="
echo "Starting the firewalld service!"

sudo systemctl start firewalld.service

if [[ $? -eq 0 ]]; then
    echo "Firewalld started successfully."
else
    echo "Failed to start firewalld service."
fi

firewall-cmd --zone=public --add-port=3128/tcp --permanent
firewall-cmd --reload
result=$(firewall-cmd --list-all --permanent)

echo "Below is the list of open ports present on the system!"
echo $result

echo "Confirming if squid is active!"
result=$(sudo systemctl is-active squid.service)

if [[ "$result" == "inactive" ]]; then
    echo "Squid is inactive. Restarting the service..."
    sudo systemctl start squid.service
else
    echo "Squid is already active."
fi

echo "================================================================="
echo "Using curl command to see if squid working properly!"

timeout 30 curl -O -L "https://www.redhat.com/index.html" -x "squid:squid@${internal_ip}:3128"
timeout 30 curl -O -L "https://www.google.com/index.html" -x "squid:squid@${internal_ip}:3128"

cat /var/log/squid/access.log

redhat_denied=$(grep "TCP_DENIED/403" /var/log/squid/access.log | grep "www.redhat.com")
google_allowed=$(grep "TCP_TUNNEL/200" /var/log/squid/access.log | grep "www.google.com")

if [[ -n "$redhat_denied" ]]; then
    echo "ERROR: RedHat access is incorrectly denied (TCP_DENIED/403)."
    exit 1
fi

if [[ -n "$google_allowed" ]]; then
    echo "ERROR: Google access is incorrectly allowed (TCP_TUNNEL/200)."
    exit 1
fi

echo "================================================================="
echo "Script completed successfully!"
exit 0
