# Fusion authority alleviation and restore utility
Customers that would like to remove cluster-admin like authority from our operators can use this set of scripts to alleviate the authority post-install or restore authority before upgrade . Before applying these changes the customer needs to understand the following limitations.

## Support
Fusion version must be 2.14.0

## Limitations
The authority change will need to be reversed before upgrading or patching the product. The changes can be re-applied using the same script with `reduce-authority` and `restore-authority` options.

## Prerequisite
The script has a dependency on following tools:
- oc (OpenShift CLI)
- yq (Command-line YAML processor, v4.x+ required)
- jq (Command-line JSON processor)

After installing these tools, login to the cluster via `oc login` command.

## Procedure to reduce the authority (post-install, post-upgrade, post-patch)
`./updateFusionAuthority.sh  reduce-authority`

## Procedure to restore the authority (pre-upgrade, pre-patch)
`./updateFusionAuthority.sh  restore-authority`

