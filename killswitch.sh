#! /bin/bash

declare -a IPS_ARRAY

OVPN_FILE=""
DNS_SERVER=""
SSH_RULE=0
SCRIPT_DIR=$(dirname $(readlink -f $0))
ALLOW_SSH=0

# Displays help
function help(){
    echo "[!] Usage: $0 {start|stop} [-i <ip:port:protocol>] [-d <dns_ip>] [-r (keep ssh conn)] [-s (allow ssh)]"
    echo "[!] Example: $0 start -i 202.23.56.5:1198:udp -d 208.67.222.222 -r -s"
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
    while getopts "i:d:rs" OPT;do
        case "${OPT}" in
            i)
                IPS_ARRAY+=(${OPTARG})
                ;;
            d)
                echo "[*] DNS ip: ${OPTARG}"
                DNS_SERVER="${OPTARG}"
                ;;
            r)
                echo "[*] Setting rules for remote SSH"
                SSH_RULE=1
                ;;
            s)
                echo "[*] Allowing SSH service"
                ALLOW_SSH=1
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
        echo "[*] saving ufw rules"
        touch "${SCRIPT_DIR}/.ufw_status" &> /dev/null
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
        ip rule add table 128 from $(ip route get 1 | grep -Po '(?<=src )(\S+)')
        interface=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)')
        mask=$(ip addr show ${interface} | grep 'inet ' | awk '{print $2}' | cut -d'/' -f2)
        ip route add table 128 to $(ip route get 1 | grep -Po '(?<=src )(\S+)')/${mask} dev ${interface}
        ip route add table 128 default via $(ip -4 route ls | grep default | grep -Po '(?<=via )(\S+)')
    fi

    # in case of VPS
    if [ ${ALLOW_SSH} -eq 1 ];
    then
        ufw allow ssh
    fi

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
        ufw allow out to $ip port $port proto $protocol

        # finally allow every traffic from vpn server
        # ufw allow in from $ip port $port proto $protocol
        ufw allow in from $ip
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

    if [ -f "${SCRIPT_DIR}/.ufw_status" ];
    then
        echo "[*] restoring rules"
        cp /etc/ufw/user.rules.killswitch /etc/ufw/user.rules
        cp /etc/ufw/user6.rules.killswitch /etc/ufw/user6.rules
        rm -f "${SCRIPT_DIR}/.ufw_status" &> /dev/null
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
    help
    ;;
esac
