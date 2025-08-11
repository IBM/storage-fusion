#!/bin/bash


echo "=== Update sls registration key ==="
# reg_key=`oc get licenseservice sls -n ibm-sls -o json | jq '.status.registrationKey'`
# registrationKey=`echo -n "$reg_key | base64"`
# echo -n "" | base64
oc patch secrets sls-registration-key --type merge  -p '{"data":{"registrationKey":"YmI0OTJhMjgtOWZhZi01MGMxLWJlOTAtMWVlNmM0NTgwNWEz"}}'

echo -e "\n=== bascfgs.config.mas.ibm.com ==="
oc patch bascfgs.config.mas.ibm.com cpst3-bas-system --type merge  -p '{"spec":{"config":{"url":"https://uds-endpoint-ibm-common-services.maximo-vpc-test1-98b7318c91b01bd72490e80cc2328915-0000.us-east.containers.appdomain.cloud"}}}'

echo -e "\n=== coreidps.internal.mas.ibm.com ==="
oc patch coreidps.internal.mas.ibm.com cpst3-coreidp --type merge  -p '{"spec":{"domain":"cpst3.maximo-vpc-test1-98b7318c91b01bd72490e80cc2328915-0000.us-east.containers.appdomain.cloud"}}'

echo -e "\n=== kafkacfgs.config.mas.ibm.com ==="
oc patch kafkacfgs.config.mas.ibm.com cpst3-kafka-system --type merge  -p '{"spec":{"config":{"hosts":[{"host":"maskafka-kafka-tls-bootstrap-kafka.maximo-vpc-test1-98b7318c91b01bd72490e80cc2328915-0000.us-east.containers.appdomain.cloud","port":443}]},"displayName":"maskafka-kafka-tls-bootstrap-kafka.maximo-vpc-test1-98b7318c91b01bd72490e80cc2328915-0000.us-east.containers.appdomain.cloud"}}'

echo -e "\n=== slscfgs.config.mas.ibm.com ==="
# oc get secret sls-cert-ca -n  ibm-sls -o json | jq '.data."ca.crt"' | xargs echo -n | base64 -d
# after this, get current slscfgs.config.mas.ibm.com and convert to string for recipe as below
# oc get slscfg cpst3-sls-system -o json | jq '.spec.certificates[0].crt' | sed 's|\\n|\\\\n|g' 
#oc patch slscfgs.config.mas.ibm.com cpst3-sls-system --type merge  -p '{"spec":{"certificates":[{"crt":"-----BEGIN CERTIFICATE-----\nMIIDvDCCAqSgAwIBAgIQX+xdfM4Yi9jGxi7bzKeCtDANBgkqhkiG9w0BAQsFADB4\nMQswCQYDVQQGEwJHQjEPMA0GA1UEBxMGTG9uZG9uMQ8wDQYDVQQJEwZMb25kb24x\nLTArBgNVBAsTJElCTSBTdWl0ZSBMaWNlbnNlIFNlcnZpY2UgKEludGVybmFsKTEY\nMBYGA1UEAxMPc2xzLnNscy5pYm0uY29tMB4XDTI0MDMyNzE4NTU0OVoXDTQ0MDMy\nMjE4NTU0OVoweDELMAkGA1UEBhMCR0IxDzANBgNVBAcTBkxvbmRvbjEPMA0GA1UE\nCRMGTG9uZG9uMS0wKwYDVQQLEyRJQk0gU3VpdGUgTGljZW5zZSBTZXJ2aWNlIChJ\nbnRlcm5hbCkxGDAWBgNVBAMTD3Nscy5zbHMuaWJtLmNvbTCCASIwDQYJKoZIhvcN\nAQEBBQADggEPADCCAQoCggEBAL8q4UgxL8N5u+AiBnK7FVJRGVeEj1AG23fAilMh\nqTPOGlY9Gd9jEMO0d9VwY39WHwLwouhJ93YsYZrHP8Uhr4X2Rgnb2lSRnW3JXCbi\nl3kkQV9mMqWr33vUbzR7AdLYpfma80QLmJLQupcpoNK0eWkkGjXPyqLhHbOdZy3Y\nmvKWSh0V3+s2R99ODMDrka4naLvibz+BBS8cV5mq6Aysh9/QNmylPeg4l0yHWJZf\n/bYQXqFpdbc01L6HPUt19eD4AqOrzvuciYBKoLntv4dwS27kngeIVbXaw+1Lu6YT\nykC3rQ71aCqbw7JttUDFiizuG3ISVhj5ZKB+D+zkPElkbWECAwEAAaNCMEAwDgYD\nVR0PAQH/BAQDAgIEMA8GA1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFDWhn6hpTQDh\n6UtVsbI9YijWQt1TMA0GCSqGSIb3DQEBCwUAA4IBAQBrQNts3TeFyk5tfYbRFNr/\nguo/xt7gPXSqzBPiQBVMLv1FUYU4uLI2hkpTrV0TE/eRkNdPf92ZqXLebuCtmXJZ\n7Mle1n1nemGcndJag8VgXg+l0tl8BppvMhSUDwL8nd1uhmjfdznQsQfMirFiTtDl\nhbGvWOF2EHYg+DgwaIoJ+ZXzC4y2t9VuSRC31GPrmFmt7VpOSMzfVCx+oO3Kocd4\nGC8Q1bPsWLYpda0NniOWMyeeUsySHZ7dIrnZpxYhNo+mJnNuk02ip6cuDMwd60HJ\nB8ScaLcDjmvhSe9hS4LfwSRhiiETb7RWEh+4MzieQUahfPoT/BSq9LrsCIPXG3Xz\n-----END CERTIFICATE-----\n","alias":"ca"}],"config":    {"url":"https://sls.ibm-sls.ibm-sls.maximo-vpc-test1-98b7318c91b01bd72490e80cc2328915-0000.us-east.containers.appdomain.cloud"}}}'
oc patch slscfgs.config.mas.ibm.com cpst3-sls-system --type merge  -p '{"spec":{"certificates":[{"crt":"-----BEGIN CERTIFICATE-----\nMIIDvDCCAqSgAwIBAgIQMMpFP0aU04wdiuLGGXBxfjANBgkqhkiG9w0BAQsFADB4\nMQswCQYDVQQGEwJHQjEPMA0GA1UEBxMGTG9uZG9uMQ8wDQYDVQQJEwZMb25kb24x\nLTArBgNVBAsTJElCTSBTdWl0ZSBMaWNlbnNlIFNlcnZpY2UgKEludGVybmFsKTEY\nMBYGA1UEAxMPc2xzLnNscy5pYm0uY29tMB4XDTI0MDQwMTE2MjcwNFoXDTQ0MDMy\nNzE2MjcwNFoweDELMAkGA1UEBhMCR0IxDzANBgNVBAcTBkxvbmRvbjEPMA0GA1UE\nCRMGTG9uZG9uMS0wKwYDVQQLEyRJQk0gU3VpdGUgTGljZW5zZSBTZXJ2aWNlIChJ\nbnRlcm5hbCkxGDAWBgNVBAMTD3Nscy5zbHMuaWJtLmNvbTCCASIwDQYJKoZIhvcN\nAQEBBQADggEPADCCAQoCggEBAKO84KFU2ZKlCSVMNfNuQXnP/v7b83NFIvstohzk\n+TtEcHkcrAxqdYzDezoZvbP4E7IxtB0ojVy4FaA57kNPETXpecvHPNAQIOkXjDIg\nIi81vSiAFEWsREiiLCPhZHcSAxwRl0JrVFUOJIxVDuowsXUaqYCQeQy1YSk1B4dW\n+zb4OlPkekndALJKxFkNKLXg9b8vWUMrj9ArhmEdAWQdUyQG56bQshpIg29BH4Pb\nj+Eu0f+KNttWMxE+mfnrEZfMeP5Aca7NPBKosAnA5/HQoJYdigoA7+fnKCkrmo+B\nvwBgVjSj56Yh1bpQsR+ZrTO7cISfUeVgtOJ92+Ok0ERMZS8CAwEAAaNCMEAwDgYD\nVR0PAQH/BAQDAgIEMA8GA1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFMRMjTbaGB7n\n0VM9cLfvtO3SmJeMMA0GCSqGSIb3DQEBCwUAA4IBAQBqoTRRa4nWSC6wudGPyQoX\nHqqIAV71lTsDDRWiRfKrpiECnI5+cG39sdCaee7EPBLfFcuPNcO+lafAMwMi4g2U\nkMRN6eXzLV39kp6nLa1b8bT7r6JAazPu0cKpozsi05VOAcyIuljBAVsLSmYQQ2p9\nbEDjXFyYhIKmXhOeNt24ahBSUq+x0oelHY58DMtc0yqBZ6u/O8QKX3EjLOcoKHmv\ng2WmA1CF3k8JMix8gjHPrIS5BGmBMFHsK0Pp3/YTbTiDD+VciO9ZM5YZZDqrsH+S\nFyhp9OyFKfxnEd5Z+hapF75ZmF107TeE66gHUgjDwGi/IBDg6Lx5WXCpsjV2HJNv\n-----END CERTIFICATE-----\n","alias":"ca"}],"config":    {"url":"https://sls.ibm-sls.ibm-sls.maximo-vpc-test1-98b7318c91b01bd72490e80cc2328915-0000.us-east.containers.appdomain.cloud"}}}'

echo -e "\n=== suites.core.mas.ibm.com ==="
oc patch suites.core.mas.ibm.com cpst3 --type merge  -p '{"spec":{"domain":"cpst3.maximo-vpc-test1-98b7318c91b01bd72490e80cc2328915-0000.us-east.containers.appdomain.cloud"}}'

echo -e "\n=== watsonstudiocfgs.config.mas.ibm.com ==="
oc patch watsonstudiocfgs.config.mas.ibm.com cpst3-watsonstudio-system --type merge  -p '{"spec":{"config":{"endpoint":"https://cpd-ibm-cpd.maximo-vpc-test1-98b7318c91b01bd72490e80cc2328915-0000.us-east.containers.appdomain.cloud"},"displayName":"https://cpd-ibm-cpd.maximo-vpc-test1-98b7318c91b01bd72490e80cc2328915-0000.us-east.containers.appdomain.cloud"}}'
