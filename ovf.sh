#!/bin/bash
mkdir -p "/opt/ovfset"
STATE='/opt/ovfset/interface.state'

log_result () {
    echo "`date` - $1" | tee -a /opt/ovfset/log
}

if [ -e $STATE ]; then
    log_result "$STATE file exists. Doing nothing."
    exit 1
fi

# Generic variables
PRIMARY_NIC_NAME='ens32'
PRIMARY_NIC_CONFIG="/etc/sysconfig/network-scripts/ifcfg-$PRIMARY_NIC_NAME"

# Patterns
IP_PATTERN='([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})'
MAC_PATTERN='([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})'


echo "###########################################"
echo "############ OVF Config script ############"
echo "# System will be rebooted after execution #"
echo "###########################################"

# Fetch the values from VMWare
log_result "Fetching guest info from VMWare"
vmtoolsd --cmd "info-get guestinfo.ovfenv" > /tmp/ovf_env.xml
TMPXML='/tmp/ovf_env.xml'

# Verify contents of XML
if [[ `cat $TMPXML` != *"vCloud"* ]]; then
    log_result "Unable to fetch OVF ENV. Aborting."
    exit 1
fi

# Set hostname
HOSTNAME=`cat $TMPXML | grep 'computerName' | sed -n -e '/value\=/ s/.*\=\" *//p' | sed 's/\"\/>//'`
log_result "Setting hostname = $HOSTNAME"
hostnamectl set-hostname $HOSTNAME --static

# Get list of NICs
INTERFACES=`cat $TMPXML | grep "Adapter ve:mac=" | grep -oP $MAC_PATTERN`
PRIMARY_NIC=`cat $TMPXML | grep "vCloud_primaryNic" | grep -oP '([0-9])'`

# Set up the primary interface first
log_result "Setting up Primary NIC"

IP=`cat $TMPXML | grep "vCloud_ip_$PRIMARY_NIC" | grep -oP $IP_PATTERN`
NETMASK=`cat $TMPXML | grep "vCloud_netmask_$PRIMARY_NIC" | grep -oP $IP_PATTERN`
CIDR=`ipcalc -p 0.0.0.0 $NETMASK | grep -oP "([0-9]{1,2})"`
GATEWAY=`cat $TMPXML| grep "vCloud_gateway_$PRIMARY_NIC" | grep -oP $IP_PATTERN`
DNS1=`cat $TMPXML | grep "vCloud_dns1_$PRIMARY_NIC" | grep -oP $IP_PATTERN`
DNS2=`cat $TMPXML | grep "vCloud_dns2_$PRIMARY_NIC" | grep -oP $IP_PATTERN`

log_result "Setting IPADDR=$IP"
sed -i "s/IPADDR=.*/IPADDR=$IP/" $PRIMARY_NIC_CONFIG

log_result "Setting PREFIX=$CIDR"
sed -i "s/PREFIX=.*/PREFIX=$CIDR/" $PRIMARY_NIC_CONFIG

log_result "Setting GATEWAY=$GATEWAY"
sed -i "s/GATEWAY=.*/GATEWAY=$GATEWAY/" $PRIMARY_NIC_CONFIG

if [ -z "$DNS1" ]; then
    log_result "No DNS1 specified for primary interface."
    sed -i '/^DNS1/d' $PRIMARY_NIC_CONFIG
else
    log_result "Setting DNS1=$DNS1"
    sed -i "s/DNS1=.*/DNS1=$DNS1/" $PRIMARY_NIC_CONFIG
fi

if [ -z "$DNS2" ]; then
    log_result "No DNS2 specified for primary interface."
    sed -i '/^DNS2/d' $PRIMARY_NIC_CONFIG
else
    log_result "Setting DNS2=$DNS2"
    sed -i "s/DNS2=.*/DNS2=$DNS2/" $PRIMARY_NIC_CONFIG
fi

# Set up all other interfaces.
while read -r line; do
    NAME=`ip -o link | grep $line | awk '{print $2}' | grep -oP '([A-Za-z0-9]*)'`
    INTERFACE_NUMBER=`cat $TMPXML | grep $line | grep -oP 'macaddr_([0-9])' | grep -oP '([0-9])'`

    if [[ "$NAME" == "$PRIMARY_NIC_NAME" ]]; then
        continue
    fi

    IP=`cat $TMPXML | grep "vCloud_ip_$INTERFACE_NUMBER" | grep -oP $IP_PATTERN`
    NETMASK=`cat $TMPXML | grep "vCloud_netmask_$INTERFACE_NUMBER" | grep -oP $IP_PATTERN`
    CIDR=`ipcalc -p 0.0.0.0 $NETMASK | grep -oP "([0-9]{1,2})"`
    GATEWAY=`cat $TMPXML| grep "vCloud_gateway_$INTERFACE_NUMBER" | grep -oP $IP_PATTERN`
    DNS1=`cat $TMPXML | grep "vCloud_dns1_$INTERFACE_NUMBER" | grep -oP $IP_PATTERN`
    DNS2=`cat $TMPXML | grep "vCloud_dns2_$INTERFACE_NUMBER" | grep -oP $IP_PATTERN`

    if [ -z ${IP+x} ] || [ -z ${NETMASK+x} ] || [ -z ${GATEWAY+x} ]; then
        echo "`date` - Missing either IP, Netmask or Gateway. Failed to configure $NAME"
        continue
    fi

    log_result "Creating interface $NAME: $IP/$NETMASK via $GATEWAY"
    nmcli con add con-name "$NAME" ifname $NAME type ethernet ip4 $IP/$CIDR gw4 $GATEWAY
    sed -i "s/DEFROUTE=yes/DEFROUTE=no/" /etc/sysconfig/network-scripts/ifcfg-$NAME

    if [[ -n $DNS1 ]] && [[ -n $DNS2 ]]; then
        log_result "Setting DNS1=$DNS1, DNS2=$DNS2"
        nmcli con mod "$NAME" ipv4.dns "$DNS1,$DNS2"
    fi
done <<< $INTERFACES

# Finish
log_result '---------------------------------------------------------------------------------------------------------'
log_result "This script will not be executed on next boot if $STATE exists"
log_result "If you want to execute this configuration on next boot, delete $STATE"
log_result "Creating $STATE and rebooting"
cp /opt/ovfset/log /opt/ovfset/log.latest

date > $STATE

sleep 10
reboot
