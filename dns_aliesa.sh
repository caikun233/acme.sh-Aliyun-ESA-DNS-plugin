#!/usr/bin/bash
# shellcheck disable=SC2034
dns_aliesa_info='AlibabaCloud.com ESA
Domains: Aliyun.com
Site: AlibabaCloud.com
Docs: https://www.alibabacloud.com/help/en/edge-security-acceleration
Options:
 AliESA_Key API Key
 AliESA_Secret API Secret
'

Ali_ESA_API="https://esa.ap-southeast-1.aliyuncs.com/"

#Usage: dns_aliesa_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_aliesa_add() {
  fulldomain=$1
  txtvalue=$2

  _prepare_ali_credentials || return 1

  _debug "First detect the site"
  if ! _get_site "$fulldomain"; then
    _err "Site not found for $fulldomain"
    return 1
  fi

  _debug "Add record"
  _add_record_query "$_site_id" "$fulldomain" "$txtvalue" && _ali_rest "Add record" "" "POST"
}

dns_aliesa_rm() {
  fulldomain=$1
  txtvalue=$2
  
  _debug "Calling dns_aliesa_rm for domain: $fulldomain"
  
  _prepare_ali_credentials || return 1

  _debug "First detect the site"
  if ! _get_site "$fulldomain"; then
    _err "Site not found for $fulldomain"
    return 1
  fi

  _clean_record
}

####################  Alibaba Cloud common functions below  ####################

_prepare_ali_credentials() {
  AliESA_Key="${AliESA_Key:-$(_readaccountconf_mutable AliESA_Key)}"
  AliESA_Secret="${AliESA_Secret:-$(_readaccountconf_mutable AliESA_Secret)}"
  if [ -z "$AliESA_Key" ] || [ -z "$AliESA_Secret" ]; then
    AliESA_Key=""
    AliESA_Secret=""
    _err "You don't specify aliyun ESA api key and secret yet."
    return 1
  fi

  #save the api key and secret to the account conf file.
  _saveaccountconf_mutable AliESA_Key "$AliESA_Key"
  _saveaccountconf_mutable AliESA_Secret "$AliESA_Secret"
}

# act ign mtd
_ali_rest() {
  act="$1"
  ign="$2"
  mtd="${3:-GET}"

  signature=$(printf "%s" "$mtd&%2F&$(printf "%s" "$query" | _url_encode upper-hex)" | _hmac "sha1" "$(printf "%s" "$AliESA_Secret&" | _hex_dump | tr -d " ")" | _base64)
  signature=$(printf "%s" "$signature" | _url_encode upper-hex)
  url="$endpoint?Signature=$signature"
  
  _debug "Requesting $act..."

  if [ "$mtd" = "GET" ]; then
    url="$url&$query"
    response="$(_get "$url")"
  else
    response="$(_post "$query" "$url" "" "$mtd" "application/x-www-form-urlencoded")"
  fi

  _ret="$?"
  _debug2 response "$response"
  
  # Log raw response for debugging clean issues
  _debug "$act response code: $_ret"
  if [ "$act" = "List records" ] || [ "$act" = "List records retry" ]; then
     _debug2 "$act raw response: $response"
  fi

  if [ "$_ret" != "0" ]; then
    _err "Error <$act>"
    return 1
  fi

  if [ -z "$ign" ]; then
    # ESA error structure might overlap with ALI DNS, checking for "Message" or "Code"
    message="$(echo "$response" | _egrep_o "\"Message\":\"[^\"]*\"" | cut -d : -f 2 | tr -d \")"
    if [ "$message" ]; then
      _err "$message"
      return 1
    fi
  fi
}

_ali_nonce() {
  if [ "$ACME_OPENSSL_BIN" ]; then
    "$ACME_OPENSSL_BIN" rand -hex 16 2>/dev/null && return 0
  fi
  printf "%s" "$(date +%s)$$$(date +%N)" | _digest sha256 hex | cut -c 1-32
}

_ali_timestamp() {
  date -u +"%Y-%m-%dT%H%%3A%M%%3A%SZ"
}

####################  Private functions below  ####################

_get_site() {
  domain=$1
  i=1
  p=1
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    _list_sites_query "$h"
    if ! _ali_rest "Get site" "ignore"; then
      return 1
    fi

    if _contains "$response" "\"TotalCount\""; then
      count=$(echo "$response" | _egrep_o "\"TotalCount\":[0-9]+" | cut -d : -f 2)
      if [ "$count" ] && [ "$count" -gt 0 ]; then
          # Extract SiteId
          _site_id=$(echo "$response" | _egrep_o "\"SiteId\":[0-9]+" | head -n 1 | cut -d : -f 2)
          _debug _site_id "$_site_id"
          return 0
      fi
    fi
    p="$i"
    i=$(_math "$i" + 1)
  done
  return 1
}

# Sorted alphabetically by parameter name:
# AccessKeyId, Action, Format, SignatureMethod, SignatureNonce, SignatureVersion, SiteName, SiteSearchType, Timestamp, Version
_list_sites_query() {
  endpoint=$Ali_ESA_API
  query=''
  query=$query'AccessKeyId='$AliESA_Key
  query=$query'&Action=ListSites'
  query=$query'&Format=json'
  query=$query'&SignatureMethod=HMAC-SHA1'
  query=$query"&SignatureNonce=$(_ali_nonce)"
  query=$query'&SignatureVersion=1.0'
  query=$query'&SiteName='$1
  query=$query'&SiteSearchType=exact'
  query=$query'&Timestamp='$(_ali_timestamp)
  query=$query'&Version=2024-09-10'
}

# Sorted alphabetically by parameter name:
# AccessKeyId, Action, Data, Format, RecordName, SignatureMethod, SignatureNonce, SignatureVersion, SiteId, Timestamp, Ttl, Type, Version
_add_record_query() {
  endpoint=$Ali_ESA_API
  query=''
  query=$query'AccessKeyId='$AliESA_Key
  query=$query'&Action=CreateRecord'
  
  # Data needs to be URL encoded if it contains special chars
  # We construct it locally then encode
  data_val="{\"value\":\"$3\"}"
  data_enc=$(printf "%s" "$data_val" | _url_encode upper-hex) 
  
  query=$query'&Data='$data_enc
  query=$query'&Format=json'
  query=$query'&RecordName='$2
  query=$query'&SignatureMethod=HMAC-SHA1'
  query=$query"&SignatureNonce=$(_ali_nonce)"
  query=$query'&SignatureVersion=1.0'
  query=$query'&SiteId='$1
  query=$query'&Timestamp='$(_ali_timestamp)
  query=$query'&Ttl=30'
  query=$query'&Type=TXT'
  query=$query'&Version=2024-09-10'
}

# Sorted alphabetically by parameter name:
# AccessKeyId, Action, Format, RecordId, SignatureMethod, SignatureNonce, SignatureVersion, Timestamp, Version
_delete_record_query() {
  endpoint=$Ali_ESA_API
  query=''
  query=$query'AccessKeyId='$AliESA_Key
  query=$query'&Action=DeleteRecord'
  query=$query'&Format=json'
  query=$query'&RecordId='$1
  query=$query'&SignatureMethod=HMAC-SHA1'
  query=$query"&SignatureNonce=$(_ali_nonce)"
  query=$query'&SignatureVersion=1.0'
  query=$query'&Timestamp='$(_ali_timestamp)
  query=$query'&Version=2024-09-10'
}

# Sorted alphabetically by parameter name:
# AccessKeyId, Action, Format, RecordName, SignatureMethod, SignatureNonce, SignatureVersion, SiteId, Timestamp, Type, Version
_list_records_query() {
  endpoint=$Ali_ESA_API
  query=''
  query=$query'AccessKeyId='$AliESA_Key
  query=$query'&Action=ListRecords'
  query=$query'&Format=json'
  query=$query'&RecordName='$2
  query=$query'&SignatureMethod=HMAC-SHA1'
  query=$query"&SignatureNonce=$(_ali_nonce)"
  query=$query'&SignatureVersion=1.0'
  query=$query'&SiteId='$1
  query=$query'&Timestamp='$(_ali_timestamp)
  query=$query'&Type=TXT'
  query=$query'&Version=2024-09-10'
}

_clean_record() {
  _debug "Starting record cleanup for TXT value: $txtvalue"
  # Retry loop to handle syncing delay
  for i in 1 2 3; do
    _debug "Clean check iteration $i"
    _list_records_query "$_site_id" "$fulldomain"
    if _ali_rest "List records" "ignore"; then
      # Robust parsing:
      # 1. Remove all spaces/newlines to handle varying formatting
      clean_json=$(echo "$response" | tr -d '[:space:]')
      
      # 2. Split records by "},{" which is the standard object separator in JSON arrays
      #    We replace "},{" with "}\n{" to put each record on a new line
      #    This ensures we don't mix up RecordIds and Values from different records
      records_list=$(echo "$clean_json" | sed 's/},{/}\n{/g')
      
      # 3. Find the line containing our specific TXT value
      #    We must escape special chars in txtvalue if any, but acme challenge is usually safe
      _debug "Searching for value in record list..."
      # ESA API returns "Data":{"Value":"..."} (Capital V) in list response, even if we sent lowercase.
      # Use grep -i to handle both "value" and "Value" keys
      target_record=$(echo "$records_list" | grep -i "\"value\":\"$txtvalue\"")
      
      if [ "$target_record" ]; then
         _debug "Record found: $target_record"
         # 4. Extract RecordId from that specific line
         rec_id=$(echo "$target_record" | _egrep_o "\"RecordId\":[0-9]+" | cut -d : -f 2)
         
         if [ "$rec_id" ]; then
             _debug "Found existing record ID to delete: $rec_id"
             _delete_record_query "$rec_id"
             _ali_rest "Delete record $rec_id" "ignore" "POST"
             return 0
         else
             _debug "Parsing RecordId failed from line."
         fi
      else
         _debug "Target value not found in current record list."
      fi
    fi
    _debug "Record not found for cleanup, retrying in 3s..."
    _sleep 3
  done
  
  _debug "Failed to find record to clean after retries. Manual cleanup may be required."
}
