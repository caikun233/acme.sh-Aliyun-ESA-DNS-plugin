# acme.sh-Aliyun-ESA-DNS-plugin

A plugin for **acme.sh** that provides support for Aliyun ESA proprietary DNS API.

> [!IMPORTANT]  
> This plugin depends on the Aliyun CLI. You must install and configure it first.

## Usage
1. Refer to [Aliyun Help Center - International](https://www.alibabacloud.com/help/cli/) or [阿里云帮助中心-中国站](https://help.aliyun.com/cli/) to download and install and configure the Aliyun CLI.  
2. Download `dns_aliesa.sh` from this repository and place it in acme.sh's `dnsapi` plugin directory, which is usually located at `~/.acme.sh/dnsapi/`. You will see many `.sh` files there; they provide DNSAPI support for acme.sh.  
3. Add execution permission:  

   ```shell
   chmod +x ~/.acme.sh/dnsapi/dns_aliesa.sh
   ```

4. Use it like any other DNSAPI plugin:

   ```shell
   acme.sh --issue -d example.com -d *.example.com --dns dns_aliesa
   ```
