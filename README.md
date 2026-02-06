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

4. Use it like any other DNSAPI plugin:

   ```shell
   acme.sh --issue -d example.com -d *.example.com --dns dns_aliesa
   ```
