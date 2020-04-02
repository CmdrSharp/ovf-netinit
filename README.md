# OVF NetInit Script
Bash Script for initializing OVF Parameters in VMWare for CentOS Machines

## Installation
1. Place the script in /opt/ovfset/ovf.sh.
2. `chmod +x /opt/ovfset/ovh.sh`
3. `chmod u+x /etc/rc.d/rc.local`
4. `echo 'bash /opt/ovfset/ovf.sh 2>&1' >> /etc/rc.d/rc.local`

### Credits
Inspired by [TheVirtualist](https://thevirtualist.org/creating-customizable-linux-ovf-template/)
