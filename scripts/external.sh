#!/bin/bash  -
#===============================================================================
#
#          FILE: external.sh
#
#         USAGE: ./external.sh
#
#   DESCRIPTION: 
#
#       OPTIONS: ---
#  REQUIREMENTS: ---
#          BUGS: ---
#         NOTES: ---
#        AUTHOR: Morteza Bashsiz (mb), morteza.bashsiz@gmail.com
#  ORGANIZATION: Linux
#       CREATED: 10/30/2022 08:48:41 PM
#      REVISION:  ---
#===============================================================================

set -o nounset                                  # Treat unset variables as an error

_pass=$(< /dev/urandom tr -dc A-Z-a-z-0-9 | head -c"${1:-16}";echo;)
_uuid=$(cat /proc/sys/kernel/random/uuid)
_SHADOWSOCKS_CFG=$(cat << EOF
{
    "server":"$_EXTERNAL_IP",
    "server_port":$_EXTERNAL_VPN_PORT,
    "local_port":1080,
    "password":"$_pass",
    "timeout":300,
    "method":"chacha20-ietf-poly1305",
    "workers":8,
    "plugin":"obfs-server",
    "plugin_opts": "obfs=http;obfs-host=www.google.com",
    "fast_open":true,
    "reuse_port":true
}
EOF
)


_V2RAY_VMESS_CFG=$(cat << EOF
{
  "inbounds": [{
    "listen": "$_EXTERNAL_IP",
    "port": $_EXTERNAL_VPN_PORT,
    "protocol": "vmess",
    "streamSettings": {},
    "settings": {
      "clients": [
        {
          "id": "$_uuid",
          "level": 1,
          "alterId": 64
        }
      ]
    }
  }],
  "outbounds": [{
    "protocol": "freedom",
    "settings": {}
  },{
    "protocol": "blackhole",
    "settings": {},
    "tag": "blocked"
  }]
}
EOF
)

_EXTERNAL_IPTABLES_CFG=$(cat << EOF
*filter
:INPUT ACCEPT [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -d $_EXTERNAL_IP/32 -p udp -m udp --dport $_EXTERNAL_VPN_PORT -j ACCEPT
-A INPUT -d $_EXTERNAL_IP/32 -p tcp -m tcp --dport $_EXTERNAL_VPN_PORT -j ACCEPT
-A INPUT -p tcp -m tcp --dport $_EXTERNAL_SSH_PORT -j ACCEPT
-A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
-A INPUT -i lo -j ACCEPT
-A INPUT -p icmp -j ACCEPT
-A INPUT -j DROP
-A FORWARD -j DROP
-A OUTPUT -j ACCEPT
COMMIT
EOF
)

_FAIL2BAN_CFG=$(cat << EOF
[sshd]
enabled = true
bantime = 15m
findtime = 10m
maxretry = 3
EOF
)

# Function fncSetupExternalCommon
# Setup external host 
function fncSetupExternalCommon {
	scp -r -P "$_EXTERNAL_SSH_PORT" ../tools "$_EXTERNAL_IP":/opt/
	echo "${_EXTERNAL_IPTABLES_CFG}" > /tmp/external_iptables
	scp -r -P "$_EXTERNAL_SSH_PORT" /tmp/external_iptables "$_EXTERNAL_IP":/root/
	fncExecCmd "$_EXTERNAL_IP" "$_EXTERNAL_SSH_PORT" "mv /root/external_iptables /etc/iptables/rules.v4"
	fncExecCmd "$_EXTERNAL_IP" "$_EXTERNAL_SSH_PORT" "systemctl restart iptables.service; systemctl enable iptables.service;"
	echo "${_FAIL2BAN_CFG}" > /tmp/external_fail2ban
	scp -r -P "$_EXTERNAL_SSH_PORT" /tmp/external_fail2ban "$_EXTERNAL_IP":/root/
	fncExecCmd "$_EXTERNAL_IP" "$_EXTERNAL_SSH_PORT" "mv /root/external_fail2ban /etc/fail2ban/jail.d/sshd.conf"
	fncExecCmd "$_EXTERNAL_IP" "$_EXTERNAL_SSH_PORT" "systemctl restart fail2ban.service; systemctl enable fail2ban.service;"
}
# End of Function fncSetupExternalCommon

# Function fncSetupExternalShadowsocks
# Setup external host with Shadowsocks
function fncSetupExternalShadowsocks {
	fncSetupExternalCommon
	echo "${_SHADOWSOCKS_CFG}" > /tmp/external_shadowsocks
	scp -r -P "$_EXTERNAL_SSH_PORT" /tmp/external_shadowsocks "$_EXTERNAL_IP":/root/
	fncExecCmd "$_EXTERNAL_IP" "$_EXTERNAL_SSH_PORT" "mv /root/external_shadowsocks /etc/shadowsocks-libev/config.json"
	fncExecCmd "$_EXTERNAL_IP" "$_EXTERNAL_SSH_PORT" "systemctl restart shadowsocks-libev.service; systemctl enable shadowsocks-libev.service;"
	echo ""
	echo ">External Host is configured"
	echo ">use the following configuration for your android client"
	echo "
		server: $_INTERNAL_IP
		server_port: $_INTERNAL_VPN_PORT
		password: $_pass
		method: chacha20-ietf-poly1305
		plugin_opts: obfs=http;obfs-host=www.google.com
	"
}
# End of Function fncSetupExternalShadowsocks

# Function fncSetupExternalV2rayVmess
# Setup external host with V2rayVmess
function fncSetupExternalV2rayVmess {
	fncSetupExternalCommon
	echo "${_V2RAY_VMESS_CFG}" > /tmp/external_v2rayvmess
	scp -r -P "$_EXTERNAL_SSH_PORT" /tmp/external_v2rayvmess "$_EXTERNAL_IP":/root/
	fncExecCmd "$_EXTERNAL_IP" "$_EXTERNAL_SSH_PORT" "mv /root/external_v2rayvmess /etc/v2ray/config.json"
	fncExecCmd "$_EXTERNAL_IP" "$_EXTERNAL_SSH_PORT" "systemctl restart v2ray.service; systemctl enable v2ray.service;"
	fncExecCmd "$_EXTERNAL_IP" "$_EXTERNAL_SSH_PORT" "python3 /opt/tools/conf2vmess.py -c /etc/v2ray/config.json -s $_INTERNAL_IP -p $_INTERNAL_VPN_PORT -o /opt/tools/output-vmess.json"
	fncExecCmd "$_EXTERNAL_IP" "$_EXTERNAL_SSH_PORT" "python3 /opt/tools/vmess2sub.py /opt/tools/output-vmess.json /opt/tools/output-vmess_v2rayN.html -l /opt/tools/output-vmess_v2rayN.lnk"
	_vmessurl=$(fncExecCmd "$_EXTERNAL_IP" "$_EXTERNAL_SSH_PORT" "cat /opt/tools/output-vmess_v2rayN.lnk")
	echo ""
	echo ">Your VMESS url is as following inport it to your client device"
	echo "$_vmessurl"
}
# End of Function fncSetupExternalV2rayVmess