#!/usr/bin/env bash
# start_Copyright_Notice
# Licensed Materials - Property of IBM

# IBM Spectrum Fusion 5900-AOY
# (C) Copyright IBM Corp. 2022 All Rights Reserved.

# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with
# IBM Corp.
# end_Copyright_Notice

###############################################################
### Global Envrionment Variables

set -u

TIMEOUT=600

# Colorful constants
RED='\033[91m'
GREEN='\033[92m'
YELLOW='\033[93m'
NORMAL='\033[0m'

# Message labels
INFO="$(echo -e $GREEN"I"$NORMAL)"
WARNING="$(echo -e $YELLOW"W"$NORMAL)"
ERROR="$(echo -e $RED"E"$NORMAL)"


###############################################################

info() {
    printf "$(date +"%T") [$INFO] %s\n" "$1"
}

warn() {
    printf "$(date +"%T") [$WARNING] %s\n" "$1"
}

error() {
    printf "$(date +"%T") [$ERROR] %s\n" "$1"
}