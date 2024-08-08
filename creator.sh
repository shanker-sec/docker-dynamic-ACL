#!/bin/bash

knockd_conf='knockd.conf'
bash_script='DACL.sh'
ipset_path='/usr/sbin/ipset'
knock_path='/usr/sbin/knockd'
iptables_path='/usr/sbin/iptables'
j=0

# overwriting files.
echo  ''> $knockd_conf
echo "#!/bin/bash" > $bash_script

create_str () {
    i=1
    str=$port_number
    while [[ $i != $repeat_number ]]; do
	str=${str}','${port_number}
	((i++))
    done

}

check_is_number() {
case $1 in
    ''|*[!0-9]*) echo "error: $1 - not a number, exit" >&2; exit 1 ;;
esac
}

check_max() {
    if (( $1 > 2147483 )); then
        echo "error: timeout more than 2147483, exit" >&2; exit 1
    fi
}


check_port_number() {
    if (( $1 > 65535 )); then
        echo "error: port number more than 65535, exit" >&2; exit 1
    fi
}


# creating rules for ipset and iptables.
create_bash_script () {
    
    echo "# Rules for port $port_number." >> $bash_script
    echo "$iptables_path -A INPUT -p tcp -m tcp --dport $port_number -j DROP &&" >> $bash_script
    echo "$ipset_path create whitelist_$j hash:ip timeout 10 &&" >> $bash_script
    echo "$iptables_path -I INPUT 1  -p tcp --dport $port_number -m set --match-set whitelist_$j src -j ACCEPT &&" >> $bash_script
    echo "" >> $bash_script
}

# creating rule for knockd.
create_knockd_conf() {
    echo "["$task_name"]" >> $knockd_conf
    echo "    sequence = $str"  >> $knockd_conf
    echo "    seq_timeout = $timeout_1"  >> $knockd_conf
    echo "    command = $ipset_path -q add whitelist_$j %IP% timeout $timeout_2"  >> $knockd_conf
    echo "    tcpflags = syn"  >> $knockd_conf
    ((j++))
}


while true; do
    read -p "Enter rule name (for knockd): " task_name
    read -p "Enter port number (max 65535): " port_number
    read -p "Enter the number of times the port repeats (for knockd): " repeat_number
    read -p "Enter the connection timeout in seconds (for knockd): " timeout_1
    read -p "Enter the connection timeout in seconds (for ipset, 2147483 max): " timeout_2

# Check that the values consist only of digits.
check_is_number $port_number
check_is_number $repeat_number
check_is_number $timeout_1
check_is_number $timeout_2

# Check maximum value.
check_max $timeout_2
check_port_number $port_number

create_str

create_bash_script

create_knockd_conf

    read -p "Add another rule? (yes/no): " answer

    if [[ $answer != "yes" ]]; then
        echo "$knock_path&" >> $bash_script
        echo "exit"
        break
    fi
       
done
