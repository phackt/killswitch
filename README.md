# UFW killswitch

**killswitch.sh** - Forces traffic through VPN thanks to UFW.  

You can use this killswitch on your **VPS** to avoid some network leakage if your VPN shuts down.  
It will save your user rules, add the route to keep your remote SSH, set up a DNS server, and allow traffic only to your VPN server.  

Example:
```
killswitch.sh start -i 202.23.56.5:1198:udp -d 208.67.222.222 -s
killswitch.sh stop
```

Options:  
 - **start/stop**: set up the ufw rule/restore previous rules and DNS configuration
 - **-i**: [vpn server ip]:[remote port]:[protocol]
 - **-d**: [dns ip] - update /etc/resolv.conf
 - **-s**: add the route to keep remote SSH
