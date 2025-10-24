#!/usr/bin/env sh

# Aliyun ESA DNS API
# This plugin uses Aliyun CLI (already configured with AccessKey)
#
# Usage:
#   acme.sh --issue --dns dns_aliesa -d example.com -d *.example.com
#
# Note: Make sure aliyun CLI is installed and configured properly

########  Public functions #####################

#Usage: dns_aliesa_add _acme-challenge.www.domain.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_aliesa_add() {
  fulldomain=$1
  txtvalue=$2
  
  _info "Using Aliyun ESA DNS API"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"
  
  # Check if aliyun CLI is available
  if ! _exists aliyun; then
    _err "Aliyun CLI is not installed or not in PATH"
    _err "Please install and configure aliyun CLI first"
    return 1
  fi
  
  # Extract root domain from fulldomain
  if ! _get_root "$fulldomain"; then
    _err "Failed to detect root domain"
    return 1
  fi
  
  _info "Detected root domain: $_domain"
  _debug "Sub domain: $_sub_domain"
  
  # Get Site ID for this domain
  _info "Getting Site ID for domain: $_domain"
  if ! _get_site_id "$_domain"; then
    _err "Failed to get Site ID for domain: $_domain"
    return 1
  fi
  
  _info "Site ID: $_site_id"
  
  # Create TXT record
  _info "Adding TXT record: $fulldomain"
  if ! _add_txt_record "$fulldomain" "$txtvalue"; then
    _err "Failed to add TXT record"
    return 1
  fi
  
  _info "TXT record added successfully. Record ID: $_record_id"
  
  # Save Record ID with domain-specific key for multi-domain support
  # Replace invalid characters in variable name (-, .)
  _record_key=$(echo "$fulldomain" | tr '.-' '_')
  _savedomainconf "Ali_ESA_RecordId_$_record_key" "$_record_id"
  
  return 0
}

#Usage: dns_aliesa_rm _acme-challenge.www.domain.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_aliesa_rm() {
  fulldomain=$1
  txtvalue=$2
  
  _info "Using Aliyun ESA DNS API"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"
  
  # Check if aliyun CLI is available
  if ! _exists aliyun; then
    _err "Aliyun CLI is not installed or not in PATH"
    return 1
  fi
  
  # Get saved Record ID for this specific domain
  # Replace invalid characters in variable name (-, .)
  _record_key=$(echo "$fulldomain" | tr '.-' '_')
  _record_id="$(_readdomainconf "Ali_ESA_RecordId_$_record_key")"
  
  if [ -z "$_record_id" ]; then
    _err "No Record ID found for domain: $fulldomain"
    _err "You may need to manually delete the record"
    return 1
  fi
  
  _info "Removing TXT record with Record ID: $_record_id"
  if _delete_record "$_record_id"; then
    _info "TXT record removed successfully"
    # Clean up the saved Record ID
    _cleardomainconf "Ali_ESA_RecordId_$_record_key"
    return 0
  else
    _err "Failed to remove TXT record"
    return 1
  fi
}

####################  Private functions below ##################################

# Detect root domain and sub domain
# Sets _domain and _sub_domain
_get_root() {
  domain=$1
  i=1
  p=1
  
  # Get list of all sites from Aliyun ESA
  _debug "Fetching all sites from Aliyun ESA"
  
  response=$(aliyun esa ListSites --PageSize 500 2>&1)
  
  if [ $? -ne 0 ]; then
    _err "Failed to fetch sites list"
    _debug "Response: $response"
    return 1
  fi
  
  _debug2 "ListSites response: $response"
  
  # Extract all site names from response
  # Looking for "SiteName": "example.com"
  site_names=$(echo "$response" | grep -o '"SiteName"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*:[[:space:]]*"\(.*\)"/\1/')
  
  if [ -z "$site_names" ]; then
    _err "No sites found in Aliyun ESA"
    _err "Please add your domain to Aliyun ESA first"
    return 1
  fi
  
  _debug2 "Available sites: $site_names"
  
  # Try to match domain from right to left
  # For example: _acme-challenge.esatest1.rusleep.net
  # Will try: net, rusleep.net, esatest1.rusleep.net, _acme-challenge.esatest1.rusleep.net
  
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-)
    _debug "Checking if $h is a registered site"
    
    if [ -z "$h" ]; then
      # No more parts to check
      _err "Cannot find root domain in Aliyun ESA sites"
      _err "Available sites: $site_names"
      _err "Your domain: $domain"
      return 1
    fi
    
    # Check if this h matches any site name
    if _contains "$site_names" "$h"; then
      _domain="$h"
      
      # Calculate sub_domain
      if [ "$domain" = "$_domain" ]; then
        _sub_domain=""
      else
        _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
      fi
      
      _debug "Found root domain: $_domain"
      _debug "Sub domain: $_sub_domain"
      return 0
    fi
    
    p=$i
    i=$(_math "$i" + 1)
  done
  
  return 1
}

_get_site_id() {
  domain=$1
  
  _debug "Querying Site ID for domain: $domain"
  
  # Call aliyun CLI to get site list
  response=$(aliyun esa ListSites --SiteName "$domain" 2>&1)
  
  if [ $? -ne 0 ]; then
    _err "Failed to call aliyun CLI"
    _debug "Response: $response"
    return 1
  fi
  
  _debug2 "ListSites response: $response"
  
  # Extract Site ID using grep and sed
  # Looking for "SiteId": 572217942623808
  _site_id=$(echo "$response" | grep -o '"SiteId"[[:space:]]*:[[:space:]]*[0-9]*' | head -n 1 | sed 's/.*:[[:space:]]*//')
  
  if [ -z "$_site_id" ]; then
    _err "Could not find Site ID in response"
    _debug "Response: $response"
    return 1
  fi
  
  _debug "Found Site ID: $_site_id"
  
  # Cache the Site ID for this domain
  _record_key=$(echo "$domain" | tr '.-' '_')
  _savedomainconf "Ali_ESA_SiteId_$_record_key" "$_site_id"
  
  return 0
}

_add_txt_record() {
  domain=$1
  txtvalue=$2
  
  _debug "Creating TXT record for: $domain"
  _debug "TXT value: $txtvalue"
  
  # Create the record using aliyun CLI
  response=$(aliyun esa CreateRecord \
    --SiteId "$_site_id" \
    --RecordName "$domain" \
    --Type TXT \
    --Ttl 30 \
    --Data "{\"Value\":\"$txtvalue\"}" 2>&1)
  
  if [ $? -ne 0 ]; then
    _err "Failed to create TXT record"
    _debug "Response: $response"
    return 1
  fi
  
  _debug2 "CreateRecord response: $response"
  
  # Extract Record ID
  # Looking for "RecordId": 3865110073780544
  _record_id=$(echo "$response" | grep -o '"RecordId"[[:space:]]*:[[:space:]]*[0-9]*' | head -n 1 | sed 's/.*:[[:space:]]*//')
  
  if [ -z "$_record_id" ]; then
    _err "Could not find Record ID in response"
    _debug "Response: $response"
    return 1
  fi
  
  _debug "Record created with ID: $_record_id"
  
  # Wait a moment for DNS propagation
  _sleep 2
  
  # Verify the record was created correctly
  if ! _verify_txt_record "$_record_id" "$txtvalue"; then
    _err "Record verification failed"
    return 1
  fi
  
  return 0
}

_verify_txt_record() {
  record_id=$1
  expected_value=$2
  
  _debug "Verifying TXT record: $record_id"
  
  response=$(aliyun esa GetRecord --RecordId "$record_id" 2>&1)
  
  if [ $? -ne 0 ]; then
    _err "Failed to get record details"
    _debug "Response: $response"
    return 1
  fi
  
  _debug2 "GetRecord response: $response"
  
  # Extract the Value from response
  # Looking for "Value": "abcdef123456"
  actual_value=$(echo "$response" | grep -o '"Value"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n 1 | sed 's/.*:[[:space:]]*"\(.*\)"/\1/')
  
  _debug "Expected value: $expected_value"
  _debug "Actual value: $actual_value"
  
  if [ "$actual_value" = "$expected_value" ]; then
    _info "Record verified successfully"
    return 0
  else
    _err "Record value mismatch"
    return 1
  fi
}

_delete_record() {
  record_id=$1
  
  _debug "Deleting record: $record_id"
  
  # Delete the record using aliyun CLI (only RecordId needed)
  response=$(aliyun esa DeleteRecord --RecordId "$record_id" 2>&1)
  
  if [ $? -ne 0 ]; then
    _err "Failed to delete record"
    _debug "Response: $response"
    return 1
  fi
  
  _debug2 "DeleteRecord response: $response"
  
  # Check if RequestId exists in response (indicates success)
  if echo "$response" | grep -q '"RequestId"'; then
    _debug "Record deleted successfully"
    return 0
  else
    _err "Unexpected response from DeleteRecord"
    _debug "Response: $response"
    return 1
  fi
}

_sleep() {
  secs=$1
  _debug "Sleep $secs seconds"
  sleep "$secs"
}

_exists() {
  cmd="$1"
  command -v "$cmd" >/dev/null 2>&1
}

_contains() {
  _str="$1"
  _sub="$2"
  echo "$_str" | grep -F -- "$_sub" >/dev/null 2>&1
}

_math() {
  _m_opts="$@"
  printf "%s" "$(($_m_opts))"
}
