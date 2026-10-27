# acme.sh-Aliyun-ESA-DNS-plugin

A plugin for **acme.sh** that provides support for Aliyun ESA proprietary DNS API.

> [!IMPORTANT]  
> The AccessKey used requires the following permissions:
> * `esa:ListSites`
> * `esa:ListRecords`
> * `esa:CreateRecord`
> * `esa:DeleteRecord`

## Usage
1. Download `dns_aliesa.sh` from this repository and place it in acme.sh's `dnsapi` plugin directory, which is usually located at `~/.acme.sh/dnsapi/`. You will see many `.sh` files there; they provide DNSAPI support for acme.sh.  
2. Add execution permission:  

   ```shell
   chmod +x ~/.acme.sh/dnsapi/dns_aliesa.sh
   ```

3. Export your Aliyun ESA API Key and Secret:

   ```shell
   export AliESA_Key="LT******"
   export AliESA_Secret="******"
   ```

   Optionally, set the API endpoint when your ESA sites live outside the default
   (international) region. The value must point to the ESA API endpoint of the
   region your account belongs to, for example:

   ```shell
   export AliESA_Endpoint="https://esa.cn-hangzhou.aliyuncs.com/"
   ```

4. Use it like any other DNSAPI plugin:

   ```shell
   acme.sh --issue -d example.com -d *.example.com --dns dns_aliesa
   ```

## Options

| Variable | Required | Description |
| --- | --- | --- |
| `AliESA_Key` | yes | AccessKey ID. |
| `AliESA_Secret` | yes | AccessKey Secret. |
| `AliESA_Endpoint` | no | API endpoint, defaults to `https://esa.ap-southeast-1.aliyuncs.com/`. |

All values are saved to `account.conf` after the first successful run, so renewals
work unattended.

## Notes
* `dns_aliesa_rm` is implemented: the TXT record is deleted after validation, and a
  record that is already gone is not treated as an error.
* IDN domains are converted to punycode with `_idn`, the `idn` command must be
  installed for them.
* While testing, add `--staging` and `--debug 2` to avoid hitting the production
  rate limits.

