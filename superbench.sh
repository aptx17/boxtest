#!/usr/bin/env bash
#
# Description: Auto system info & I/O test & network to China script
#

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
SKYBLUE='\033[0;36m'
PLAIN='\033[0m'
BrowserUA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36"

about() {
	echo ""
	echo " ========================================================= "
	echo " \                 Superbench.sh  Script                 / "
	echo " \       Basic system info, I/O test and speedtest       / "
	echo " ========================================================= "
	echo ""
	echo ""
}

cancel() {
	echo ""
	next;
	echo " Abort ..."
	echo " Cleanup ..."
	cleanup;
	echo " Done"
	exit
}

trap cancel SIGINT

benchinit() {
	if [ -f /etc/redhat-release ]; then
	    release="centos"
	elif cat /etc/issue | grep -Eqi "debian"; then
	    release="debian"
	elif cat /etc/issue | grep -Eqi "ubuntu"; then
	    release="ubuntu"
	elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
	    release="centos"
	elif cat /proc/version | grep -Eqi "debian"; then
	    release="debian"
	elif cat /proc/version | grep -Eqi "ubuntu"; then
	    release="ubuntu"
	elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
	    release="centos"
	fi

	[[ $EUID -ne 0 ]] && echo -e "${RED}Error:${PLAIN} This script must be run as root!" && exit 1
	
	# determine architecture of host
	ARCH=$(uname -m)
	if [[ $ARCH = *x86_64* ]]; then
		# host is running a 64-bit kernel
		ARCH="x64"
	elif [[ $ARCH = *i?86* ]]; then
		# host is running a 32-bit kernel
		ARCH="x86"
	elif [[ $ARCH = *aarch* || $ARCH = *arm* ]]; then
		KERNEL_BIT=`getconf LONG_BIT`
		if [[ $KERNEL_BIT = *64* ]]; then
			# host is running an ARM 64-bit kernel
			ARCH="aarch64"
		else
			# host is running an ARM 32-bit kernel
			ARCH="arm"
		fi
		echo -e "\nARM compatibility is considered *experimental*"
	else
		# host is running a non-supported kernel
		echo -e "Architecture not supported by Superbench."
		exit 1
	fi

	if  [ "$(command -v curl)" == "" ]; then
		echo " Installing Curl ..."
		if [[ ! -z "$(type -p yum)" ]]; then
			yum -y install curl > /dev/null 2>&1
		else
			apt-get update > /dev/null 2>&1
			apt-get -y install curl > /dev/null 2>&1
		fi
	fi

	if  [ "$(command -v tar)" == "" ]; then
		echo " Installing Tar ..."
		if [[ ! -z "$(type -p yum)" ]]; then
			yum -y install tar > /dev/null 2>&1
		else
			apt-get update > /dev/null 2>&1
			apt-get -y install tar > /dev/null 2>&1
		fi
	fi
	
	if  [ "$(command -v wget)" == "" ]; then
		echo " Installing Wget ..."
		if [[ ! -z "$(type -p yum)" ]]; then
			yum -y install wget > /dev/null 2>&1
		else
			apt-get update > /dev/null 2>&1
			apt-get -y install wget > /dev/null 2>&1
		fi
	fi

	if [ "$(command -v unzip)" == "" ]; then
		echo " Installing UnZip ..."
		if [[ ! -z "$(type -p yum)" ]]; then
			yum -y install unzip > /dev/null 2>&1
		else
			apt-get update > /dev/null 2>&1
			apt-get -y install unzip > /dev/null 2>&1
		fi
	fi

	if  [ ! -e './speedtest-cli/speedtest' ]; then
		echo " Installing Speedtest-cli ..."
		wget --no-check-certificate -qO speedtest.tgz https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-$(uname -m).tgz > /dev/null 2>&1
	fi
	mkdir -p speedtest-cli && tar zxvf speedtest.tgz -C ./speedtest-cli/ > /dev/null 2>&1 && chmod a+rx ./speedtest-cli/speedtest
	
	
	if [[ ! -e './geekbench' ]]; then
		mkdir geekbench
	fi
	GeekbenchVer=6
	if [[ $ARCH = *x86* ]]; then
		download_geekbench4;
		$GeekbenchVer=4
	elif [[ $ARCH != *aarch64* && $ARCH != *arm* ]]; then
		if [ ! -e './geekbench/geekbench6' ]; then
			echo " Installing Geekbench 6..."
			curl -s https://cdn.geekbench.com/Geekbench-6.2.1-Linux.tar.gz  | tar xz --strip-components=1 -C ./geekbench &>/dev/null
		fi
		chmod +x ./geekbench/geekbench6
	else
		if [ ! -e './geekbench/geekbench6' ]; then
			echo " Installing Geekbench 6 ARM..."
			curl -s https://cdn.geekbench.com/Geekbench-6.2.1-LinuxARMPreview.tar.gz  | tar xz --strip-components=1 -C ./geekbench &>/dev/null
		fi
		chmod +x ./geekbench/geekbench6
	fi

	sleep 5

	start=$(date +%s) 
}

download_geekbench4(){
	if [[ ! -d ./geekbench ]]; then
		mkdir geekbench
	fi
	if [[ ! -d ./geekbench/geekbench4 ]]; then
		echo -n -e " Installing Geekbench 4..."
		curl -s https://cdn.geekbench.com/Geekbench-4.4.4-Linux.tar.gz | tar xz --strip-components=1 -C ./geekbench &>/dev/null
	fi
	chmod +x ./geekbench/geekbench4
}

get_opsy() {
    [ -f /etc/redhat-release ] && awk '{print ($1,$3~/^[0-9]/?$3:$4)}' /etc/redhat-release && return
    [ -f /etc/os-release ] && awk -F'[= "]' '/PRETTY_NAME/{print $3,$4,$5}' /etc/os-release && return
    [ -f /etc/lsb-release ] && awk -F'[="]+' '/DESCRIPTION/{print $2}' /etc/lsb-release && return
}

next() {
    printf "%-70s\n" "-" | sed 's/\s/-/g' | tee -a $log
}

calc_size() {
    local raw=$1
    local total_size=0
    local num=1
    local unit="KB"
    if ! [[ ${raw} =~ ^[0-9]+$ ]] ; then
        echo ""
        return
    fi
    if [ "${raw}" -ge 1073741824 ]; then
        num=1073741824
        unit="TB"
    elif [ "${raw}" -ge 1048576 ]; then
        num=1048576
        unit="GB"
    elif [ "${raw}" -ge 1024 ]; then
        num=1024
        unit="MB"
    elif [ "${raw}" -eq 0 ]; then
        echo "${total_size}"
        return
    fi
    total_size=$( awk 'BEGIN{printf "%.1f", '$raw' / '$num'}' )
    echo "${total_size} ${unit}"
}

speed_test(){
	if [[ $1 == '' ]]; then
		speedtest-cli/speedtest -p no --accept-license --accept-gdpr > $speedLog 2>&1
		is_upload=$(cat $speedLog | grep 'Upload')
		result_speed=$(cat $speedLog | awk -F ' ' '/Result/{print $3}')
		if [[ ${is_upload} ]]; then
	        local REDownload=$(cat $speedLog | awk -F ' ' '/Download/{print $3}')
	        local reupload=$(cat $speedLog | awk -F ' ' '/Upload/{print $3}')
	        local relatency=$(cat $speedLog | awk -F ' ' '/Latency/{print $3}')

	        temp=$(echo "$relatency" | awk -F '.' '{print $1}')
        	if [[ ${temp} -gt 50 ]]; then
            	relatency="(*)"${relatency}
        	fi
	        local nodeName=$2

	        temp=$(echo "${REDownload}" | awk -F ' ' '{print $1}')
	        if [[ $(awk -v num1=${temp} -v num2=0 'BEGIN{print(num1>num2)?"1":"0"}') -eq 1 ]]; then
	        	printf "${YELLOW}%-18s${SKYBLUE}%-18s${SKYBLUE}%-20s${GREEN}%-12s${PLAIN}\n" " ${nodeName}" "${reupload} Mbit/s" "${REDownload} Mbit/s" "${relatency} ms" | tee -a $log
	        fi
		else
	        local cerror="ERROR"
		fi
	else
		speedtest-cli/speedtest -p no -s $1 --accept-license --accept-gdpr > $speedLog 2>&1
		is_upload=$(cat $speedLog | grep 'Upload')
		if [[ ${is_upload} ]]; then
	        local REDownload=$(cat $speedLog | awk -F ' ' '/Download/{print $3}')
	        local reupload=$(cat $speedLog | awk -F ' ' '/Upload/{print $3}')
	        local relatency=$(cat $speedLog | awk -F ' ' '/Latency/{print $3}')
	        local nodeName=$2

	        temp=$(echo "${REDownload}" | awk -F ' ' '{print $1}')
	        if [[ $(awk -v num1=${temp} -v num2=0 'BEGIN{print(num1>num2)?"1":"0"}') -eq 1 ]]; then
	        	printf "${YELLOW}%-18s${SKYBLUE}%-18s${SKYBLUE}%-20s${GREEN}%-12s${PLAIN}\n" " ${nodeName}" "${reupload} Mbit/s" "${REDownload} Mbit/s" "${relatency} ms" | tee -a $log
			fi
		else
	        local cerror="ERROR"
		fi
	fi
}

print_china_speedtest() {
	printf "%-18s%-18s%-20s%-12s\n" " Node Name" "Upload Speed" "Download Speed" "Latency" | tee -a $log
        speed_test '' 'Speedtest.net'
        speed_test '3633'  'Shanghai     CT'
	speed_test '23844' 'Wuhan 5G     CT'
	speed_test '27594' 'Guangzhou 5G CT'
        speed_test '26352' 'Nanjing 5G   CT'
	speed_test '5145'  'Beijing      CU'
	speed_test '24447' 'Shanghai 5G  CU'
	speed_test '45170' 'Wu Xi        CU'
	speed_test '26678' 'Guangzhou 5G CU'
	speed_test '25637' 'Shanghai 5G  CM'
	speed_test '27249' 'Nanjing 5G   CM'
	speed_test '15863' 'Nanning      CM'
	speed_test '4575'  'Chengdu      CM'
}

print_global_speedtest() {
	printf "%-18s%-18s%-20s%-12s\n" " Node Name" "Upload Speed" "Download Speed" "Latency" | tee -a $log
        speed_test '1536'  'Hong Kong    CN'
        speed_test '33250' 'Macau        CN'
	speed_test '29106' 'Taiwan       TW'
	speed_test '40508' 'Singapore    SG'
	speed_test '21569' 'Tokyo        JP'
	speed_test '6527'  'Seoul        KR'
        speed_test '18229' 'Los Angeles  US'
	speed_test '41248' 'London       UK'
	speed_test '10010' 'Frankfurt    DE'
	speed_test '24215' 'Paris        FR'
	speed_test '28922' 'Amsterdam    NL'
}

print_speedtest_fast() {
	printf "%-18s%-18s%-20s%-12s\n" " Node Name" "Upload Speed" "Download Speed" "Latency" | tee -a $log
        speed_test '' 'Speedtest.net'
        speed_test '3633'  'Shanghai     CT'
	speed_test '27594' 'Guangzhou 5G CT'
	speed_test '26678' 'Guangzhou 5G CU'
	speed_test '9484'  'Changchun    CU'
	speed_test '45170' 'Wu Xi        CU'
	speed_test '25637' 'Shanghai 5G  CM'
	speed_test '15863' 'Nanning      CM'
	speed_test '5505'  'Beijing      BN'
	 
	rm -rf speedtest*
}

io_test() {
    (LANG=C dd if=/dev/zero of=test_file_$$ bs=512K count=$1 conv=fdatasync && rm -f test_file_$$ ) 2>&1 | awk -F, '{io=$NF} END { print io}' | sed 's/^[ \t]*//;s/[ \t]*$//'
}

calc_disk() {
    local total_size=0
    local array=$@
    for size in ${array[@]}
    do
        [ "${size}" == "0" ] && size_t=0 || size_t=`echo ${size:0:${#size}-1}`
        [ "`echo ${size:(-1)}`" == "K" ] && size=0
        [ "`echo ${size:(-1)}`" == "M" ] && size=$( awk 'BEGIN{printf "%.1f", '$size_t' / 1024}' )
        [ "`echo ${size:(-1)}`" == "T" ] && size=$( awk 'BEGIN{printf "%.1f", '$size_t' * 1024}' )
        [ "`echo ${size:(-1)}`" == "G" ] && size=${size_t}
        total_size=$( awk 'BEGIN{printf "%.1f", '$total_size' + '$size'}' )
    done
    echo ${total_size}
}

power_time() {

	result=$(smartctl -a $(result=$(cat /proc/mounts) && echo $(echo "$result" | awk '/data=ordered/{print $1}') | awk '{print $1}') 2>&1) && power_time=$(echo "$result" | awk '/Power_On/{print $10}') && echo "$power_time"
}

install_smart() {
	if  [ ! -e '/usr/sbin/smartctl' ]; then
		echo "Installing Smartctl ..."
	    if [ "${release}" == "centos" ]; then
	    	yum update > /dev/null 2>&1
	        yum -y install smartmontools > /dev/null 2>&1
	    else
	    	apt-get update > /dev/null 2>&1
	        apt-get -y install smartmontools > /dev/null 2>&1
	    fi      
	fi
}

ip_info4(){
    local org="$(wget -q -T10 -O- ipinfo.io/org)"
    local city="$(wget -q -T10 -O- ipinfo.io/city)"
    local country="$(wget -q -T10 -O- ipinfo.io/country)"
    local region="$(wget -q -T10 -O- ipinfo.io/region)"
	if [[ -n "$org" ]]; then
		echo -e " Organization         : ${YELLOW}$org${PLAIN}" | tee -a $log
	fi
	if [[ -n "$city" && -n "country" ]]; then
		echo -e " Location             : ${SKYBLUE}$city / ${YELLOW}$country${PLAIN}" | tee -a $log
	fi
	if [[ -n "$region" ]]; then
		echo -e " Region               : ${SKYBLUE}$region${PLAIN}" | tee -a $log
	fi
}

virt_check(){
	if hash ifconfig 2>/dev/null; then
		eth=$(ifconfig)
	fi

	virtualx=$(dmesg) 2>/dev/null

    if  [ $(which dmidecode) ]; then
		sys_manu=$(dmidecode -s system-manufacturer) 2>/dev/null
		sys_product=$(dmidecode -s system-product-name) 2>/dev/null
		sys_ver=$(dmidecode -s system-version) 2>/dev/null
	else
		sys_manu=""
		sys_product=""
		sys_ver=""
	fi
	
	if grep docker /proc/1/cgroup -qa; then
	    virtual="Docker"
	elif grep lxc /proc/1/cgroup -qa; then
		virtual="Lxc"
	elif grep -qa container=lxc /proc/1/environ; then
		virtual="Lxc"
	elif [[ -f /proc/user_beancounters ]]; then
		virtual="OpenVZ"
	elif [[ "$virtualx" == *kvm-clock* ]]; then
		virtual="KVM"
	elif [[ "$cname" == *KVM* ]]; then
		virtual="KVM"
	elif [[ "${sys_product}" == *KVM* ]]; then
		virtual="KVM"
	elif [[ "$cname" == *QEMU* ]]; then
		virtual="KVM"
	elif [[ "$virtualx" == *"VMware Virtual Platform"* ]]; then
		virtual="VMware"
	elif [[ "$virtualx" == *"Parallels Software International"* ]]; then
		virtual="Parallels"
	elif [[ "$virtualx" == *VirtualBox* ]]; then
		virtual="VirtualBox"
	elif [[ -e /proc/xen ]]; then
		virtual="Xen"
	elif [[ "$sys_manu" == *"Microsoft Corporation"* ]]; then
		if [[ "$sys_product" == *"Virtual Machine"* ]]; then
			if [[ "$sys_ver" == *"7.0"* || "$sys_ver" == *"Hyper-V" ]]; then
				virtual="Hyper-V"
			else
				virtual="Microsoft Virtual Machine"
			fi
		fi
	else
		virtual="Dedicated"
	fi
}

power_time_check(){
	echo -ne " Power time of disk   : "
	install_smart
	ptime=$(power_time)
	echo -e "${SKYBLUE}$ptime Hours${PLAIN}"
}

freedisk() {
	freespace=$( df -m . | awk 'NR==2 {print $4}' )
	if [[ $freespace == "" ]]; then
		$freespace=$( df -m . | awk 'NR==3 {print $3}' )
	fi
	if [[ $freespace -gt 1024 ]]; then
		printf "%s" $((1024*2))
	elif [[ $freespace -gt 512 ]]; then
		printf "%s" $((512*2))
	elif [[ $freespace -gt 256 ]]; then
		printf "%s" $((256*2))
	elif [[ $freespace -gt 128 ]]; then
		printf "%s" $((128*2))
	else
		printf "1"
	fi
}

print_io() {
	if [[ $1 == "fast" ]]; then
		writemb=$((128*2))
	else
		writemb=$(freedisk)
	fi
	
	writemb_size="$(( writemb / 2 ))MB"
	if [[ $writemb_size == "1024MB" ]]; then
		writemb_size="1GiB"
	fi

	if [[ $writemb != "1" ]]; then
		echo -n " I/O Speed ($writemb_size)     : " | tee -a $log
		io1=$( io_test $writemb )
		echo -e "${YELLOW}$io1${PLAIN}" | tee -a $log
		echo -n " I/O Speed ($writemb_size)     : " | tee -a $log
		io2=$( io_test $writemb )
		echo -e "${YELLOW}$io2${PLAIN}" | tee -a $log
		echo -n " I/O Speed ($writemb_size)     : " | tee -a $log
		io3=$( io_test $writemb )
		echo -e "${YELLOW}$io3${PLAIN}" | tee -a $log
		echo -n " I/O Speed ($writemb_size)     : " | tee -a $log
		io4=$( io_test $writemb )
		echo -e "${YELLOW}$io4${PLAIN}" | tee -a $log
		ioraw1=$( echo $io1 | awk 'NR==1 {print $1}' )
		[ "`echo $io1 | awk 'NR==1 {print $2}'`" == "GB/s" ] && ioraw1=$( awk 'BEGIN{print '$ioraw1' * 1024}' )
		ioraw2=$( echo $io2 | awk 'NR==1 {print $1}' )
		[ "`echo $io2 | awk 'NR==1 {print $2}'`" == "GB/s" ] && ioraw2=$( awk 'BEGIN{print '$ioraw2' * 1024}' )
		ioraw3=$( echo $io3 | awk 'NR==1 {print $1}' )
		[ "`echo $io3 | awk 'NR==1 {print $2}'`" == "GB/s" ] && ioraw3=$( awk 'BEGIN{print '$ioraw3' * 1024}' )
		ioraw4=$( echo $io4 | awk 'NR==1 {print $1}' )
		[ "`echo $io4 | awk 'NR==1 {print $2}'`" == "GB/s" ] && ioraw4=$( awk 'BEGIN{print '$ioraw4' * 1024}' )
		ioall=$( awk 'BEGIN{print '$ioraw2' + '$ioraw3' + '$ioraw4'}' )
		ioavg=$( awk 'BEGIN{printf "%.1f", '$ioall' / 3}' )
		echo -e " Average I/O Speed    : ${YELLOW}$ioavg MB/s${PLAIN}" | tee -a $log
	else
		echo -e " ${RED}Not enough space!${PLAIN}"
	fi
}

print_system_info() {
	echo -e " CPU Model            : ${SKYBLUE}$cname${PLAIN}" | tee -a $log
	echo -e " BIOS Model           : ${SKYBLUE}$cname2${PLAIN}" | tee -a $log
	echo -e " CPU Cores            : ${YELLOW}$cores Cores ${SKYBLUE}$freq MHz $arch${PLAIN}" | tee -a $log
	echo -e " L3 Cache             : ${SKYBLUE}$corescache ${PLAIN}" | tee -a $log
	echo -e " AES-NI               : $aes" | tee -a $log
	echo -e " VM-x/AMD-V           : $virt" | tee -a $log
	echo -e " Virtualization       : ${YELLOW}$virtual${PLAIN}" | tee -a $log
	echo -e " OS                   : ${SKYBLUE}$opsy ($lbit Bit)${PLAIN}" | tee -a $log
	echo -e " Kernel               : ${SKYBLUE}$kern${PLAIN}" | tee -a $log
	echo -e " Total Space          : ${SKYBLUE}$disk_used_size GB / ${YELLOW}$disk_total_size GB ${PLAIN}" | tee -a $log
	echo -e " Total RAM            : ${SKYBLUE}$uram / ${YELLOW}$tram ${SKYBLUE}($bram MB Buff)${PLAIN}" | tee -a $log
	echo -e " Total SWAP           : ${SKYBLUE}$uswap MB / $swap MB${PLAIN}" | tee -a $log
	echo -e " Uptime               : ${SKYBLUE}$up${PLAIN}" | tee -a $log
	echo -e " Load Average         : ${SKYBLUE}$load${PLAIN}" | tee -a $log
	echo -e " TCP CC               : ${YELLOW}$tcpctrl${PLAIN}" | tee -a $log
}

print_end_time() {
	end=$(date +%s) 
	time=$(( $end - $start ))
	if [[ $time -gt 60 ]]; then
		min=$(expr $time / 60)
		sec=$(expr $time % 60)
		echo -ne " Finished in  : ${min} min ${sec} sec" | tee -a $log
	else
		echo -ne " Finished in  : ${time} sec" | tee -a $log
	fi

	printf '\n' | tee -a $log

	bj_time=$(curl -s http://cgi.im.qq.com/cgi-bin/cgi_svrtime)

	if [[ $(echo $bj_time | grep "html") ]]; then
		bj_time=$(date -u +%Y-%m-%d" "%H:%M:%S -d '+8 hours')
	fi
	echo " Timestamp    : $bj_time GMT+8" | tee -a $log
	echo " Results      : $log"
}

get_system_info() {
	cname=$( lscpu | grep 'Model name' | head -1 | sed 's/Model name: *//g' )
        cname2=$( lscpu | grep 'BIOS Model name' | head -1 | sed 's/BIOS Model name: *//g' )
	cores=$( awk -F: '/processor/ {core++} END {print core}' /proc/cpuinfo )
	freq=$( awk -F'[ :]' '/cpu MHz/ {print $4;exit}' /proc/cpuinfo )
	corescache=$( lscpu | grep 'L3' | head -1 | sed 's/L3 cache: *//g' )
	aes=$(grep -i 'aes' /proc/cpuinfo)
	[[ -z "$aes" ]] && aes="${RED}Disabled ${PLAIN}" || aes="${YELLOW}Enabled ${PLAIN}"
	virt=$( grep -Ei 'vmx|svm' /proc/cpuinfo )
	[[ -z "$virt" ]] && virt="${RED}Disabled ${PLAIN}" || virt="${YELLOW}Enabled ${PLAIN}"
	tram=$( LANG=C; free | awk '/Mem/ {print $2}' )
        tram=$( calc_size $tram )
        uram=$( LANG=C; free | awk '/Mem/ {print $3}' )
        uram=$( calc_size $uram )
	bram=$( free -m | awk '/Mem/ {print $6}' )
	swap=$( free -m | awk '/Swap/ {print $2}' )
	uswap=$( free -m | awk '/Swap/ {print $3}' )
	up=$( awk '{a=$1/86400;b=($1%86400)/3600;c=($1%3600)/60} {printf("%d days %d hour %d min\n",a,b,c)}' /proc/uptime )
	load=$( w | head -1 | awk -F'load average:' '{print $2}' | sed 's/^[ \t]*//;s/[ \t]*$//' )
	opsy=$( get_opsy )
	arch=$( uname -m )
	lbit=$( getconf LONG_BIT )
	kern=$( uname -r )

	disk_size1=$( LANG=C df -hPl | grep -wvE '\-|none|tmpfs|overlay|shm|udev|devtmpfs|by-uuid|chroot|Filesystem' | awk '{print $2}' )
	disk_size2=$( LANG=C df -hPl | grep -wvE '\-|none|tmpfs|overlay|shm|udev|devtmpfs|by-uuid|chroot|Filesystem' | awk '{print $3}' )
	disk_total_size=$( calc_disk ${disk_size1[@]} )
	disk_used_size=$( calc_disk ${disk_size2[@]} )

	tcpctrl=$( sysctl net.ipv4.tcp_congestion_control | awk -F ' ' '{print $3}' )

	virt_check
}

geekbench() {
	echo -e " Geekbench v${GeekbenchVer} CPU Benchmark:" | tee -a $log
	
	if test -f "geekbench.license"; then
		./geekbench/geekbench$GeekbenchVer --unlock `cat geekbench.license` > /dev/null 2>&1
	fi
	
	GEEKBENCH_TEST=$(./geekbench/geekbench$GeekbenchVer --upload 2>/dev/null | grep "https://browser")
	
	if [[ -z "$GEEKBENCH_TEST" ]]; then
		echo -e " ${RED}Geekbench v${GeekbenchVer} test failed. Run manually to determine cause.${PLAIN}" | tee -a $log
		GEEKBENCH_URL=''
		if [[ $GeekbenchVer == *6* && $ARCH = *x86* ]]; then
			rm -rf geekbench
			download_geekbench4;
			echo -n -e "\r" | tee -a $log
			GeekbenchVer=4;
			geekbench;
		fi
	else
		GEEKBENCH_URL=$(echo -e $GEEKBENCH_TEST | head -1)
		GEEKBENCH_URL_CLAIM=$(echo $GEEKBENCH_URL | awk '{ print $2 }')
		GEEKBENCH_URL=$(echo $GEEKBENCH_URL | awk '{ print $1 }')
		sleep 6
		[[ $GeekbenchVer == *6* ]] && GEEKBENCH_SCORES=$(curl -s $GEEKBENCH_URL | grep "div class='score'") || GEEKBENCH_SCORES=$(curl -s $GEEKBENCH_URL | grep "span class='score'")
		GEEKBENCH_SCORES_SINGLE=$(echo $GEEKBENCH_SCORES | awk -v FS="(>|<)" '{ print $3 }')
		GEEKBENCH_SCORES_MULTI=$(echo $GEEKBENCH_SCORES | awk -v FS="(>|<)" '{ print $7 }')
		
		echo -e "       Single Core    : ${YELLOW}$GEEKBENCH_SCORES_SINGLE  $grank${PLAIN}"  | tee -a $log
		echo -e "        Multi Core    : ${YELLOW}$GEEKBENCH_SCORES_MULTI${PLAIN}" | tee -a $log
		[ ! -z "$GEEKBENCH_URL_CLAIM" ] && echo -e "$GEEKBENCH_URL_CLAIM" >> geekbench_claim.url 2> /dev/null
	fi
	rm -rf geekbench
}

function UnlockNetflixTest() {
    local result1=$(curl --user-agent "${BrowserUA}" -fsL --write-out %{http_code} --output /dev/null --max-time 10 "https://www.netflix.com/title/81215567" 2>&1)
	
    if [[ "$result1" == "404" ]];then
        echo -e " Netflix              : ${YELLOW}Originals Only${PLAIN}" | tee -a $log
	elif  [[ "$result1" == "403" ]];then
        echo -e " Netflix              : ${RED}No${PLAIN}" | tee -a $log
	elif [[ "$result1" == "200" ]];then
		local region=`tr [:lower:] [:upper:] <<< $(curl --user-agent "${BrowserUA}" -fs --max-time 10 --write-out %{redirect_url} --output /dev/null "https://www.netflix.com/title/80018499" | cut -d '/' -f4 | cut -d '-' -f1)` ;
		if [[ ! -n "$region" ]];then
			region="US";
		fi
		echo -e " Netflix              : ${GREEN}Yes (Region: ${region})${PLAIN}" | tee -a $log
	elif  [[ "$result1" == "000" ]];then
		echo -e " Netflix              : ${RED}Network connection failed${PLAIN}" | tee -a $log
    fi   
}

function UnlockYouTubePremiumTest() {
    local tmpresult=$(curl --max-time 10 -sS -H "Accept-Language: en" "https://www.youtube.com/premium" 2>&1 )
    local region=$(curl --user-agent "${BrowserUA}" -sL --max-time 10 "https://www.youtube.com/premium" | grep "countryCode" | sed 's/.*"countryCode"//' | cut -f2 -d'"')
	if [ -n "$region" ]; then
        sleep 0
	else
		isCN=$(echo $tmpresult | grep 'www.google.cn')
		if [ -n "$isCN" ]; then
			region=CN
		else	
			region=US
		fi	
	fi	
	
    if [[ "$tmpresult" == "curl"* ]];then
        echo -e " YouTube Premium      : ${RED}Network connection failed${PLAIN}"  | tee -a $log
        return;
    fi
    
    local result=$(echo $tmpresult | grep 'Premium is not available in your country')
    if [ -n "$result" ]; then
        echo -e " YouTube Premium      : ${RED}No${PLAIN} ${PLAIN}${GREEN} (Region: $region)${PLAIN}" | tee -a $log
        return;
		
    fi
    local result=$(echo $tmpresult | grep 'YouTube and YouTube Music ad-free')
    if [ -n "$result" ]; then
        echo -e " YouTube Premium      : ${GREEN}Yes (Region: $region)${PLAIN}" | tee -a $log
        return;
	else
		echo -e " YouTube Premium      : ${RED}Failed${PLAIN}" | tee -a $log
    fi
}

function UnlockBilibiliTest() {
	#Test Mainland
    local randsession="$(cat /dev/urandom | head -n 32 | md5sum | head -c 32)";
    local result=$(curl --user-agent "${BrowserUA}" -fsSL --max-time 10 "https://api.bilibili.com/pgc/player/web/playurl?avid=82846771&qn=0&type=&otype=json&ep_id=307247&fourk=1&fnver=0&fnval=16&session=${randsession}&module=bangumi" 2>&1);
	if [[ "$result" != "curl"* ]]; then
        result="$(echo "${result}" | grep '"code"' | awk -F 'code":' '{print $2}' | awk -F ',' '{print $1}')";
        if [ "${result}" = "0" ]; then
            echo -e " BiliBili China       : ${GREEN}Yes (Region: Mainland Only)${PLAIN}" | tee -a $log
			return;
        fi
    else
        echo -e " BiliBili China       : ${RED}Network connection failed${PLAIN}" | tee -a $log
		return;
    fi
	
	#Test Hongkong/Macau/Taiwan
	randsession="$(cat /dev/urandom | head -n 32 | md5sum | head -c 32)";
	result=$(curl --user-agent "${BrowserUA}" -fsSL --max-time 10 "https://api.bilibili.com/pgc/player/web/playurl?avid=18281381&cid=29892777&qn=0&type=&otype=json&ep_id=183799&fourk=1&fnver=0&fnval=16&session=${randsession}&module=bangumi" 2>&1);
    if [[ "$result" != "curl"* ]]; then
        result="$(echo "${result}" | grep '"code"' | awk -F 'code":' '{print $2}' | awk -F ',' '{print $1}')";
        if [ "${result}" = "0" ]; then
            echo -e " BiliBili China       : ${GREEN}Yes (Region: HongKong/Macau/Taiwan Only)${PLAIN}" | tee -a $log
			return;
        fi
    else
        echo -e " BiliBili China       : ${RED}Network connection failed${PLAIN}" | tee -a $log
		return;
    fi
	
	#Test Taiwan
	randsession="$(cat /dev/urandom | head -n 32 | md5sum | head -c 32)";
	result=$(curl --user-agent "${BrowserUA}" -fsSL --max-time 10 "https://api.bilibili.com/pgc/player/web/playurl?avid=50762638&cid=100279344&qn=0&type=&otype=json&ep_id=268176&fourk=1&fnver=0&fnval=16&session=${randsession}&module=bangumi" 2>&1);
	if [[ "$result" != "curl"* ]]; then
		result="$(echo "${result}" | grep '"code"' | awk -F 'code":' '{print $2}' | awk -F ',' '{print $1}')";
		if [ "${result}" = "0" ]; then
            echo -e " BiliBili China       : ${GREEN}Yes (Region: Taiwan Only)${PLAIN}" | tee -a $log
			return;
		fi
	else
		echo -e " BiliBili China       : ${RED}Network connection failed${PLAIN}" | tee -a $log
		return;
	fi
	echo -e " BiliBili China       : ${RED}No${PLAIN}" | tee -a $log
}

function UnlockTiktokTest() {
	local result=$(curl --user-agent "${BrowserUA}" -fsSL --max-time 10 "https://www.tiktok.com/" 2>&1);
    if [[ "$result" != "curl"* ]]; then
        result="$(echo ${result} | grep 'region' | awk -F 'region":"' '{print $2}' | awk -F '"' '{print $1}')";
		if [ -n "$result" ]; then
			if [[ "$result" == "The #TikTokTraditions"* ]] || [[ "$result" == "This LIVE isn't available"* ]]; then
				echo -e " TikTok               : ${RED}No${PLAIN}" | tee -a $log
			else
				echo -e " TikTok               : ${GREEN}Yes (Region: ${result})${PLAIN}" | tee -a $log
			fi
		else
			echo -e " TikTok               : ${RED}Failed${PLAIN}" | tee -a $log
			return
		fi
    else
		echo -e " TikTok               : ${RED}Network connection failed${PLAIN}" | tee -a $log
	fi
}

function UnlockiQiyiIntlTest() {
	curl --user-agent "${BrowserUA}" -s -I --max-time 10 "https://www.iq.com/" >/tmp/iqiyi
    if [ $? -eq 1 ]; then
        echo -e " iQIYI International  : ${RED}Network connection failed${PLAIN}" | tee -a $log
        return
    fi

    local result="$(cat /tmp/iqiyi | grep 'mod=' | awk '{print $2}' | cut -f2 -d'=' | cut -f1 -d';')";
	rm -f /tmp/iqiyi

    if [ -n "$result" ]; then
        if [[ "$result" == "ntw" ]]; then
            result=TW
            echo -e " iQIYI International  : ${GREEN}Yes (Region: ${result})${PLAIN}" | tee -a $log
            return
        else
            result=$(echo $result | tr [:lower:] [:upper:])
            echo -e " iQIYI International  : ${GREEN}Yes (Region: ${result})${PLAIN}" | tee -a $log
            return
        fi
    else
        echo -e " iQIYI International  : ${RED}Failed${PLAIN}" | tee -a $log
        return
    fi
}

function UnlockChatGPTTest() {
	if [[ $(curl --max-time 10 -sS https://chat.openai.com/ -I | grep "text/plain") != "" ]]
	then
        echo -e " ChatGPT              : ${RED}IP is BLOCKED${PLAIN}" | tee -a $log
        return
	fi
    local countryCode="$(curl --max-time 10 -sS https://chat.openai.com/cdn-cgi/trace | grep "loc=" | awk -F= '{print $2}')";
	if [ $? -eq 1 ]; then
        echo -e " ChatGPT              : ${RED}Network connection failed${PLAIN}" | tee -a $log
        return
    fi
	if [ -n "$countryCode" ]; then
        support_countryCodes=(T1 XX AL DZ AD AO AG AR AM AU AT AZ BS BD BB BE BZ BJ BT BA BW BR BG BF CV CA CL CO KM CR HR CY DK DJ DM DO EC SV EE FJ FI FR GA GM GE DE GH GR GD GT GN GW GY HT HN HU IS IN ID IQ IE IL IT JM JP JO KZ KE KI KW KG LV LB LS LR LI LT LU MG MW MY MV ML MT MH MR MU MX MC MN ME MA MZ MM NA NR NP NL NZ NI NE NG MK NO OM PK PW PA PG PE PH PL PT QA RO RW KN LC VC WS SM ST SN RS SC SL SG SK SI SB ZA ES LK SR SE CH TH TG TO TT TN TR TV UG AE US UY VU ZM BO BN CG CZ VA FM MD PS KR TW TZ TL GB)
		if [[ "${support_countryCodes[@]}"  =~ "${countryCode}" ]];  then
            echo -e " ChatGPT              : ${GREEN}Yes (Region: ${countryCode})${PLAIN}" | tee -a $log
            return
        else
			echo -e " ChatGPT              : ${RED}No${PLAIN}" | tee -a $log
            return
        fi
    else
        echo -e " ChatGPT              : ${RED}Failed${PLAIN}" | tee -a $log
        return
    fi
}

function StreamingMediaUnlockTest(){
	echo -e " Stream Media Unlock  :" | tee -a $log
	UnlockNetflixTest
	UnlockYouTubePremiumTest
	UnlockBilibiliTest
	UnlockTiktokTest
	UnlockiQiyiIntlTest
	UnlockChatGPTTest
}

sharetest() {
	echo " Share result:" | tee -a $log
	echo " · $GEEKBENCH_URL" | tee -a $log
	echo " · $result_speed" | tee -a $log
	log_preupload
	case $1 in
	'ubuntu')
		share_link="https://paste.ubuntu.com"$( curl -v --data-urlencode "content@$log_up" -d "poster=superbench.sh" -d "syntax=text" "https://paste.ubuntu.com" 2>&1 | \
			grep "Location" | awk '{print $3}' );;
	'haste' )
		share_link=$( curl -X POST -s -d "$(cat $log)" https://hastebin.com/documents | awk -F '"' '{print "https://hastebin.com/"$4}' );;
	'clbin' )
		share_link=$( curl -sF 'clbin=<-' https://clbin.com < $log );;
	'ptpb' )
		share_link=$( curl -sF c=@- https://ptpb.pw/?u=1 < $log );;
	esac

	echo " · $share_link" | tee -a $log
	next
	echo ""
	rm -f $log_up

}

log_preupload() {
	log_up="$HOME/superbench_upload.log"
	true > $log_up
	$(cat superbench.log 2>&1 | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g" > $log_up)
}

cleanup() {
	rm -f test_file_*
	rm -rf speedtest*
	rm -rf geekbench*
	rm -rf wget-log*
}

bench_all(){
	mode_name="Standard"
	about;
	benchinit;
	clear
	next;
	get_system_info;
	print_system_info;
	ip_info4;
	next;
	StreamingMediaUnlockTest;
	next;
	print_io;
	next;
	print_china_speedtest;
	next;
	print_global_speedtest;
	next;
	geekbench;
	next;
	print_end_time;
	next;
	cleanup;
	sharetest ubuntu;
}

fast_bench(){
	mode_name="Fast"
	about;
	benchinit;
	clear
	next;
	print_intro;
	next;
	get_system_info;
	print_system_info;
	ip_info4;
	next;
	StreamingMediaUnlockTest;
	next;
	print_io fast;
	next;
	print_speedtest_fast;
	next;
	print_end_time;
	next;
	cleanup;
}

log="./superbench.log"
true > $log
speedLog="./speedtest.log"
true > $speedLog

case $1 in
	'info'|'-i'|'--i'|'-info'|'--info' )
		about;sleep 3;next;get_system_info;print_system_info;next;;
    'version'|'-v'|'--v'|'-version'|'--version')
		next;about;next;;
   	'io'|'-io'|'--io'|'-drivespeed'|'--drivespeed' )
		next;print_io;next;;
	'speed'|'-speed'|'--speed'|'-speedtest'|'--speedtest'|'-speedcheck'|'--speedcheck' )
		about;benchinit;next;print_china_speedtest;next;cleanup;;
	'ip'|'-ip'|'--ip'|'geoip'|'-geoip'|'--geoip' )
		about;benchinit;next;ip_info4;next;cleanup;;
	'bench'|'-a'|'--a'|'-all'|'--all'|'-bench'|'--bench' )
		bench_all;;
	'about'|'-about'|'--about' )
		about;;
	'fast'|'-f'|'--f'|'-fast'|'--fast' )
		fast_bench;;
	'geekbench'|'-g'|'--geekbench' )
		geekbench;;
	'media'|'-m'|'--media' )
		StreamingMediaUnlockTest;;
	'share'|'-s'|'--s'|'-share'|'--share' )
		bench_all;
		is_share="share"
		if [[ $2 == "" ]]; then
			sharetest ubuntu;
		else
			sharetest $2;
		fi
		;;
	'debug'|'-d'|'--d'|'-debug'|'--debug' )
		get_ip_whois_org_name;;
*)
    bench_all;;
esac

if [[  ! $is_share == "share" ]]; then
	case $2 in
		'share'|'-s'|'--s'|'-share'|'--share' )
			if [[ $3 == '' ]]; then
				sharetest ubuntu;
			else
				sharetest $3;
			fi
			;;
	esac
fi
