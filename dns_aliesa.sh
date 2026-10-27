#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_aliesa_info='AlibabaCloud.com ESA
Domains: Aliyun.com
Site: AlibabaCloud.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_aliesa
Options:
 AliESA_Key API Key
 AliESA_Secret API Secret
 AliESA_Endpoint API Endpoint. Default "https://esa.ap-southeast-1.aliyuncs.com/". Optional.
Issues: github.com/acmesh-official/acme.sh/issues/7357
Author: @caikun233
'

Ali_ESA_API_DEFAULT="https://esa.ap-southeast-1.aliyuncs.com/"

#Usage: dns_aliesa_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_aliesa_add() {
  #the API only accepts punycode for IDN domains, and a raw UTF-8 domain
  #also breaks the request signature.
  #the record name must be lower case, and DNS names are case-insensitive.
  fulldomain="$(printf "%s" "$(_idn "$1")" | tr '[:upper:]' '[:lower:]')"
  txtvalue="$2"

  if [ -z "$fulldomain" ]; then
    _err "Cannot convert the domain to punycode: $1"
    return 1
  fi

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
  fulldomain="$(printf "%s" "$(_idn "$1")" | tr '[:upper:]' '[:lower:]')"

  if [ -z "$fulldomain" ]; then
    _err "Cannot convert the domain to punycode: $1"
    return 1
  fi
  txtvalue="$2"

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
  AliESA_Endpoint="${AliESA_Endpoint:-$(_readaccountconf_mutable AliESA_Endpoint)}"
  if [ -z "$AliESA_Key" ] || [ -z "$AliESA_Secret" ]; then
    AliESA_Key=""
    AliESA_Secret=""
    _err "You don't specify aliyun ESA api key and secret yet."
    return 1
  fi

  if [ -z "$AliESA_Endpoint" ]; then
    AliESA_Endpoint="$Ali_ESA_API_DEFAULT"
  fi
  #the endpoint is used as "$endpoint?Signature=...", so it must end with "/"
  case "$AliESA_Endpoint" in
  */) ;;
  *) AliESA_Endpoint="$AliESA_Endpoint/" ;;
  esac
  Ali_ESA_API="$AliESA_Endpoint"

  #save the api key and secret to the account conf file.
  _saveaccountconf_mutable AliESA_Key "$AliESA_Key"
  _saveaccountconf_mutable AliESA_Secret "$AliESA_Secret"
  _saveaccountconf_mutable AliESA_Endpoint "$AliESA_Endpoint"
  return 0
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
  while true; do
    h="$(printf "%s" "$domain" | cut -d . -f "$i"-100)"
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    _list_sites_query "$h"
    if ! _ali_rest "Get site" "ignore"; then
      return 1
    fi

    if _contains "$response" "\"TotalCount\""; then
      count="$(printf "%s" "$response" | _egrep_o "\"TotalCount\":[0-9]+" | cut -d : -f 2)"
      if [ "$count" ] && [ "$count" -gt 0 ]; then
        #extract the SiteId
        _site_id="$(printf "%s" "$response" | _egrep_o "\"SiteId\":[0-9]+" | _head_n 1 | cut -d : -f 2)"
        _debug _site_id "$_site_id"
        return 0
      fi
    fi
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
  i=1
  while [ "$i" -le 3 ]; do
    _debug "Clean check iteration $i"
    _list_records_query "$_site_id" "$fulldomain"
    if _ali_rest "List records" "ignore"; then
      # Robust parsing:
      # 1. Remove all spaces/newlines to handle varying formatting
      clean_json="$(printf "%s" "$response" | tr -d '[:space:]')"

      # 2. Put every record on its own line: in a JSON array of objects the
      #    separator is "},{", so each RecordId stays next to its Value.
      #    A "\n" in a sed replacement is a GNU extension that BSD and busybox
      #    sed print literally, so use an escaped newline instead.
      records_list="$(printf "%s" "$clean_json" | sed 's/},{/},\
{/g')"

      # 3. Find the line containing our TXT value ("-F": match it literally)
      _debug "Searching for value in record list..."
      # ESA API returns "Data":{"Value":"..."} (Capital V) in list response, even if we sent lowercase.
      # Use grep -i to handle both "value" and "Value" keys
      target_record="$(printf "%s" "$records_list" | grep -i -F -- "\"value\":\"$txtvalue\"" | _head_n 1)"

      if [ "$target_record" ]; then
        _debug "Record found: $target_record"
        # 4. Extract RecordId from that specific line
        rec_id="$(printf "%s" "$target_record" | _egrep_o "\"RecordId\":[0-9]+" | cut -d : -f 2 | tr -d '\"')"

        if [ "$rec_id" ]; then
          _debug "Found existing record ID to delete: $rec_id"
          _delete_record_query "$rec_id"
          if ! _ali_rest "Delete record $rec_id" "ignore" "POST"; then
            _err "Failed to delete the TXT record: $rec_id"
            return 1
          fi
          _debug "Deleted record $rec_id"
          return 0
        else
          _debug "Parsing RecordId failed from line."
        fi
      else
        _debug "Target value not found in current record list."
      fi
    fi
    i=$(_math "$i" + 1)
    if [ "$i" -le 3 ]; then
      _debug "Record not found yet, retrying in 3s..."
      _sleep 3
    fi
  done

  #the record may already be gone, which is not an error for the rm hook
  _debug "Record not found, nothing to clean."
  return 0
}
