#!/bin/sh
random() {
    tr </dev/urandom -dc A-Za-z0-9 | head -c5
    echo
}

array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)
main_interface=$(ip route get 8.8.8.8 | awk -- '{printf $5}')

gen64() {
    ip64() {
        echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
    }
    echo "$1:$(ip64):$(ip64):$(ip64):$(ip64)"
}
gen16() {
    ip16() {
        echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
    }
    echo "$1:$(ip16)"
}
gen_3proxy() {
    cat <<EOF
daemon
maxconn 2000
nserver 1.1.1.1
nserver 8.8.4.4
nserver 2001:4860:4860::8888
nserver 2001:4860:4860::8844
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
stacksize 6291456 
flush
auth strong
users $(awk -F "/" 'BEGIN{ORS="";} {print $1 ":CL:" $2 " "}' ${WORKDATA})
$(awk -F "/" '{print "auth strong\n" \
"allow " $1 "\n" \
"proxy -6 -n -a -p" $4 " -i" $3 " -e"$5"\n" \
"flush\n"}' ${WORKDATA})
EOF
}
gen_proxy_file_for_user() {
    cat >$PROXYDIR <<EOF
$(awk -F "/" '{print $3 ":" $4 ":" $1 ":" $2 }' ${WORKDATA})
EOF
}

gen_data() {
    seq $FIRST_PORT $LAST_PORT | while read port; do
        if [[ "$USERN" != "" ]]; then
            puser=$USERN
        else
            puser=$(random)
        fi
        if [[ "$PASSW" != "" ]]; then
            ppass=$PASSW
        else
            ppass=$(random)
        fi
        if [[ $SUBNETMASK -eq 64 ]]
        then
            echo "$puser/$ppass/$IP4/$port/$(gen64 $EXTERNAL_IP)"
        else
            echo "$puser/$ppass/$IP4/$port/$(gen16 $EXTERNAL_IP)"
        fi        
    done
}

gen_iptables() {
    cat <<EOF
    $(awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 "  -m state --state NEW -j ACCEPT"}' ${WORKDATA}) 
EOF
}

gen_ifconfig() {
    cat <<EOF
$(awk -F "/" '{print "ifconfig '$main_interface' inet6 add " $5 "/'$SUBNETMASK'"}' ${WORKDATA})
EOF
}
echo "working folder = /home/proxy-installer"
WORKDIR="/home/proxy-installer"
WORKDATA="${WORKDIR}/data.txt"
PROXYDIR="${WORKDIR}/proxy.txt"
mkdir $WORKDIR && cd $_

# unlink $WORKDATA
# unlink $PROXYDIR
# unlink $WORKDIR/boot_iptables.sh
# unlink $WORKDIR/boot_ifconfig.sh

IP4=$(curl -4 -s icanhazip.com)
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

echo "Internal ip = ${IP4}. External sub for ip6 = ${IP6}"

echo "Total proxies ? "
read COUNT

echo "Sub metmask ? (16 or 64 only) "
read SUBNETMASK

echo "Enter external ipv6 (None if ip6): "
read EXTERNAL

echo "Enter Proxy Username (None = random): "
read USERN

echo "Enter Proxy Password (None = random): "
read PASSW

echo "Install Proxy."

if [[ "$EXTERNAL" == "" ]]
then
    EXTERNAL_IP=$IP6
else
    EXTERNAL_IP=$EXTERNAL
fi

echo "FIRST PORT: "
read fp

FIRST_PORT=11000
if [[ "$fp" != "" ]]; then
    FIRST_PORT=$fp
fi
LAST_PORT=$(($FIRST_PORT + $COUNT))

gen_data >$WORKDIR/data.txt
gen_iptables >$WORKDIR/boot_iptables.sh
gen_ifconfig >$WORKDIR/boot_ifconfig.sh
chmod +x $WORKDIR/boot_*.sh /etc/rc.local

gen_3proxy >/usr/local/etc/3proxy/3proxy.cfg


bash /etc/rc.local

gen_proxy_file_for_user

echo "Proxy generate done "
echo $PROXYDIR
