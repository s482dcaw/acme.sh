#!/usr/bin/bash

# Here is a script to deploy cert to Oracle Cloud Infrastructure load balancer
#
# it requires the jq binary to be available in PATH, and the following
# environment variables:
#
# LB_OCID - ocid of the load balancer
# LISTENER_NAME - what it says
#
# Heavily inspired by https://github.com/fuzziebrain/oci-le-cert-manager
# Created by s482dcaw

#returns 0 means success, otherwise error.

########  Public functions #####################

#domain keyfile certfile cafile fullchain
oci_deploy() {

  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"

  if [ -f "$DOMAIN_CONF" ]; then
    # shellcheck disable=SC1090
    . "$DOMAIN_CONF"
  fi

  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cca "$_cca"
  _debug _cfullchain "$_cfullchain"


  # validate required env vars
#  _getdeployconf LB_OCID
  if [ -z "$LB_OCID" ]; then
    if [ -z "$Le_Deploy_lb_ocid" ]; then
      _err "LB_OCID needs to be defined (contains load balancer ocid)"
      return 1
     fi 
else
	Le_Deploy_lb_ocid="$LB_OCID"
	_savedomainconf Le_Deploy_lb_ocid "$Le_Deploy_lb_ocid"
  fi

  if [ -z "$LISTENER_NAME" ]; then
    if [ -z "$Le_Deploy_listener_name" ]; then
     _err "LISTENER_NAME needs to be defined (contains the name of the listener)"
    return 1
  fi
else
	Le_Deploy_listener_name="$LISTENER_NAME"
	_savedomainconf Le_Deploy_listener_name "$Le_Deploy_listener_name"
  fi


  CERT_NAME=$(basename "$_ccert")_$(date +"%Y%m%d")


# Default parameters for oci command
oci_defaults=()
oci_defaults+=(--load-balancer-id ${Le_Deploy_lb_ocid})

  LB_DATA=$(oci lb load-balancer get ${oci_defaults[@]})
  if [ ! $? ]; then
    _err "cannot read data for listener (oci)!"
    return 1
  fi

    DEFAULT_BACKEND_SET=$(echo $LB_DATA | jq -r --arg listener_name "$Le_Deploy_listener_name" \
      '.data.listeners[$listener_name]."default-backend-set-name"')
    BACKEND_TCP_PROXY_PROTOCOL_VERSION=$(echo $LB_DATA | jq -r --arg listener_name "$Le_Deploy_listener_name" \
      '.data.listeners[$listener_name]."connection-configuration"."backend-tcp-proxy-protocol-version"')
    LISTENER_PORT=$(echo $LB_DATA | jq -r --arg listener_name "$Le_Deploy_listener_name" \
      '.data.listeners[$listener_name].port')
    LISTENER_PROTOCOL=$(echo $LB_DATA | jq -r --arg listener_name "$Le_Deploy_listener_name" \
      '.data.listeners[$listener_name].protocol')
    PATH_ROUTE_SET_NAME=$(echo $LB_DATA | jq -r --arg listener_name "$Le_Deploy_listener_name" \
      '.data.listeners[$listener_name]."path-route-set-name"')
    RULE_SET_NAMES=$(echo $LB_DATA | jq -rc --arg listener_name "$Le_Deploy_listener_name" \
      '.data.listeners[$listener_name]."rule-set-names"')
    HOSTNAME_NAMES=$(echo $LB_DATA | jq -rc --arg listener_name "$Le_Deploy_listener_name" \
      '.data.listeners[$listener_name]."hostname-names"')
    CONNECTION_IDLE_TIMEOUT=$(echo $LB_DATA | jq -r --arg listener_name "$Le_Deploy_listener_name" \
      '.data.listeners[$listener_name]."connection-configuration"."idle-timeout"')
    SSL_VERIFY_DEPTH=$(echo $LB_DATA | jq -rc --arg listener_name "$Le_Deploy_listener_name" \
      '.data.listeners[$listener_name]."ssl-configuration"."verify-depth"')
    SSL_VERIFY_PEER_CERTIFICATE=$(echo $LB_DATA | jq -rc --arg listener_name "$Le_Deploy_listener_name" \
      '.data.listeners[$listener_name]."ssl-configuration"."verify-peer-certificate"')
    CIPHER_SUITE_NAME=$(echo $LB_DATA | jq -rc --arg listener_name "${Le_Deploy_listener_name}" \
      '.data.listeners[$listener_name]."ssl-configuration"."cipher-suite-name"')
    PROTOCOLS=$(echo $LB_DATA | jq -rc --arg listener_name "${Le_Deploy_listener_name}" \
      '.data.listeners[$listener_name]."ssl-configuration"."protocols"')
    SERVER_ORDER_PREFERENCE=$(echo $LB_DATA | jq -rc --arg listener_name "${Le_Deploy_listener_name}" \
      '.data.listeners[$listener_name]."ssl-configuration"."server-order-preference"')
    CERT_OLD=$(echo $LB_DATA | jq -rc --arg listener_name "${Le_Deploy_listener_name}" \
      '.data.listeners[$listener_name]."ssl-configuration"."certificate-name"')

    params=(${oci_defaults[@]})
    params+=(--default-backend-set-name ${DEFAULT_BACKEND_SET})
    if [[ $BACKEND_TCP_PROXY_PROTOCOL_VERSION =~ '^[0-9]+$' ]]; then
      params+=(--connection-configuration-backend-tcp-proxy-protocol-version ${BACKEND_TCP_PROXY_PROTOCOL_VERSION})
    fi
    params+=(--listener-name ${Le_Deploy_listener_name})
    params+=(--port ${LISTENER_PORT})
    params+=(--protocol ${LISTENER_PROTOCOL})
    params+=(--path-route-set-name ${PATH_ROUTE_SET_NAME})
    params+=(--rule-set-names ${RULE_SET_NAMES})
    params+=(--hostname-names ${HOSTNAME_NAMES})
    params+=(--connection-configuration-idle-timeout ${CONNECTION_IDLE_TIMEOUT})
    params+=(--ssl-verify-depth ${SSL_VERIFY_DEPTH})
    params+=(--ssl-verify-peer-certificate ${SSL_VERIFY_PEER_CERTIFICATE})
    params+=(--cipher-suite-name ${CIPHER_SUITE_NAME})
    params+=(--protocols ${PROTOCOLS})
    params+=(--server-order-preference ${SERVER_ORDER_PREFERENCE})
    params+=(--force)
    params+=(--wait-for-state SUCCEEDED)
    params+=(--ssl-certificate-name ${CERT_NAME})


    # Create the certificate
oci lb certificate create ${oci_defaults[@]} \
  --certificate-name ${CERT_NAME} \
  --private-key-file $_ckey \
  --public-certificate-file $_ccert \
  --ca-certificate-file $_cca \
  --wait-for-state SUCCEEDED

if [ $? -eq 0 ]; then
  echo "Successfully created certificate."
else
  _err "Failed to create certificate."
  return 1
fi

    # Update the certificate
    oci lb listener update \
      ${params[@]}
    if [ ! $? ]; then
	_err "cannot update listener (oci)!"
	return 1
    fi

    # Delete the old certificate
    oci lb certificate delete ${oci_defaults[@]} \
	--certificate-name "${CERT_OLD}" \
	--force

    if [ ! $? ]; then
	_err "cannot delete old certificate (oci)!"
	return 1
    fi

}
