#!/bin/bash
# verify-nemotron.sh — thin wrapper: verify Nemotron 3 Ultra through Bob.
# All logic is in ../verify.sh; the model details come from ../models/nemotron-3-ultra-550b-nvfp4.yaml.
#
#   BOB_NAMESPACE=bob ./scripts/verify-nemotron.sh [alias]
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$HERE/../verify.sh" nemotron-3-ultra-550b-nvfp4 "$@"
