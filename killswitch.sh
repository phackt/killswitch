#! /bin/bash

declare -a IPS_ARRAY

UFW_ENABLED=0
OVPN_FILE=""
DNS_SERVER=""
SSH_RULE=0

# Displays help
function help(){
    echo "[!] Usage: $0 {start|stop} [-i <ip:port:protocol>] [-d <dns_ip>] [-s <keeping ssh conn>]"
    echo "[!] Example: $0 start -i 202.23.56.5:1198:udp -d 208.67.222.222 -s"
    echo "[!] Example: $0 stop"
    exit 1
}

# Checking is root
if [ $(id -u) -ne 0 ]; then
    echo "[!] You'd better be root! Exiting..."
    exit
fi

# Case first argument
case "${1}" in
start)
    shift
    while getopts "i:d:s" OPT;do
        case "${OPT}" in
            i)
                IPS_ARRAY+=(${OPTARG})
                ;;
            d)
                echo "[*] DNS ip: ${OPTARG}"
                DNS_SERVER="${OPTARG}"
                ;;
            s)
                echo "[*] Setting rules for remote SSH"
                SSH_RULE=1
                ;;
            :)
                echo -e "[!] Invalid option ${OPT}"
                help
                ;;
        esac
    done

    # Is ufw enabled
    ufw status | grep active &>/dev/null
    if [ $? -eq 0 ];
    then
        UFW_ENABLED=1
        echo "[*] saving ufw rules"
        cp /etc/ufw/user.rules /etc/ufw/user.rules.killswitch
        cp /etc/ufw/user6.rules /etc/ufw/user6.rules.killswitch
    fi

    echo "[*] resetting rules"
    # reset ufw settings
    ufw --force reset

    echo "[*] denying all"
    # set default behaviour of and enable ufw
    ufw default deny incoming
    ufw default deny outgoing

    # On VPS, keeping SSH conn
    if [ ${SSH_RULE} -eq 1 ];
    then
        echo "[*] allowing remote SSH"
        ip rule add from $(ip route get 1 | grep -Po '(?<=src )(\S+)') table 128
        ip route add table 128 to $(ip route get 1 | grep -Po '(?<=src )(\S+)')/32 dev $(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)')
        ip route add table 128 default via $(ip -4 route ls | grep default | grep -Po '(?<=via )(\S+)')
    fi

    echo "[*] allowing lan traffic"
    # allow local traffic
    ufw allow to 10.0.0.0/8
    ufw allow in from 10.0.0.0/8
    ufw allow to 172.16.0.0/12
    ufw allow in from 172.16.0.0/12
    ufw allow to 192.168.1.0/16
    ufw allow in from 192.168.1.0/16

    # in case of VPS
    ufw allow in 22/tcp

    echo "[*] allowing traffic over VPN interface tun0"
    # allow all traffic over VPN interface
    ufw allow in on tun0
    ufw allow out on tun0

    echo "[*] allowing vpn gateway ip address"
    # allow vpn ip address
    for array in ${IPS_ARRAY[@]}
    do
        ip=$(echo ${array} | cut -d: -f1)
        port=$(echo ${array} | cut -d: -f2)
        protocol=$(echo ${array} | cut -d: -f3)

        echo "[*] ufw allow in/out from/to $ip port $port $protocol"
        ufw allow out to $ip port 1198 proto udp
        ufw allow in from $ip port 1198 proto udp
    done        

    if [ "X" != "X${DNS_SERVER}" ];
    then
        # setting DNS
        echo "[*] setting DNS"
        cp /etc/resolv.conf /etc/resolv.conf.killswitch && echo "nameserver ${DNS_SERVER}" > /etc/resolv.conf
    fi

    ufw enable

    ;;
     
stop)

    echo "[*] resetting rules"
    # reset ufw settings
    ufw --force reset
    ufw disable

    if [ ${UFW_ENABLED} -eq 1 ];
    then
        echo "[*] restoring rules"
        cp /etc/ufw/user.rules.killswitch /etc/ufw/user.rules
        cp /etc/ufw/user6.rules.killswitch /etc/ufw/user6.rules
        ufw enable
    fi

    if [ -f /etc/resolv.conf.killswitch ];
    then
        echo "[*] restoring DNS"
        cp /etc/resolv.conf.killswitch /etc/resolv.conf
        rm -f /etc/resolv.conf.killswitch
    fi

    ;;

*)
    echo "[!] Usage: $0 {start|stop}"
    exit 1

    ;;
esac
