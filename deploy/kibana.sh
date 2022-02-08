#!/usr/bin/bash

#Here is a script to deploy to kibana server
# Created by s482dcaw

########  Public functions #####################

#domain keyfile certfile cafile fullchain
kibana_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"

  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cca "$_cca"
  _debug _cfullchain "$_cfullchain"

  cp $_ccert /etc/kibana/certs/kibana.pem
  if [ $? -ne "0" ]; then
    _err "Could not copy certificate; check that kibana certs are in /etc/kibana/certs"
    return 1
  fi

  systemctl restart kibana
  if [ $? -ne "0" ]; then
    _err "Could not restart the kibana service but the certificate is copied."
    return 1
  fi
#  _err "Not implemented yet"

}
