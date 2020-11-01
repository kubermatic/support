#!/bin/sh

# The script dumps node info out suitable for debugging and diagnosing cluster problems.
# It dumps everything to a file

log_time=$(date +%s)
host_name=$(hostname)
tmp_dir=/tmp/${host_name}-info-${log_time}
output_file=/tmp/${host_name}-info.tar.gz


cleanup() {
    exit_code=$?

    if [ $exit_code -eq "0" ]; then
        if [ -d "${tmp_dir}" ]; then
            rm -rf "${tmp_dir}"
        fi
        exit 0
    fi

    echo "Exiting without cleanup as script...collected logs at" $tmp_dir
}

trap cleanup EXIT
trap cleanup INT

setupLogDirectory() {
    rm -rf $tmp_dir
    rm -rf $output_file
    echo "Temp directory where the logs are stored $tmp_dir"
    echo "Support collection Name: $output_file"
    mkdir -p ${tmp_dir}
}

colletOSLogs() {
    echo "Collect OS Logs"
# Collect OS Version
    sudo cat /etc/lsb-release > ${tmp_dir}/lsb-release.txt
    sudo cat /etc/os-release > ${tmp_dir}/os-release.txt
# Collect hostname 
    sudo hostname > ${tmp_dir}/hostname.txt
}

colletRunTimeLogs() {
    echo "Collect Run Time Logs"
# Collect run time info of the node
    sudo dmesg > ${tmp_dir}/dmesg.txt
    sudo free > ${tmp_dir}/free.txt
    sudo uptime > ${tmp_dir}/uptime.txt
    sudo date > ${tmp_dir}/date.txt
    sudo bash -c "ulimit -a" > ${tmp_dir}/bash-c-ulimit-a.txt
    sudo bash -c "umask" > ${tmp_dir}/bash-c-umask.txt
    sudo cat /proc/meminfo > ${tmp_dir}/meminfo.txt
    sudo cat /proc/cpuinfo > ${tmp_dir}/cpuinfo.txt
    sudo cat /proc/vmstat > ${tmp_dir}/vmstat.txt
    sudo cat /proc/swaps > ${tmp_dir}/swaps.txt
    sudo cat /proc/mounts > ${tmp_dir}/mounts.txt
    sudo cat /proc/sys/net/ipv4/ip_forward > ${tmp_dir}/ip_forward.txt
# Information for NTP
    sudo cat /etc/systemd/timesyncd.conf > ${tmp_dir}/timesyncd.conf.txt
# Environment information
    sudo env > ${tmp_dir}/env.txt
# Check for active/listening sockets
    sudo lsof -i -n > ${tmp_dir}/lsof-i-n.txt
}

colletProcessesLogs() {
    echo "Collect Processes Logs"
# Information on Linux processes
    sudo ps auwwx --sort -rss > ${tmp_dir}/ps-auwwx--sort-rss.txt
    sudo top -d 5 -n 5 -b > ${tmp_dir}/top-d-5-n-5-b.txt
}

colletNetworkLogs() {
    echo "Collect Network Logs"
    sudo ifconfig -a > ${tmp_dir}/ifconfig-a.txt
    sudo netstat -anp > ${tmp_dir}/netstat-anp.txt
    sudo netstat -aens > ${tmp_dir}/netstat-aens.txt
    sudo route > ${tmp_dir}/route.txt
# Information about ARP cache
    sudo arp -a > ${tmp_dir}/arp-a.txt
# Check local firewall rules
    sudo iptables -L -n > ${tmp_dir}/iptables-L-n.txt
    sudo iptables-save > ${tmp_dir}/iptables-save.txt
# Collect network interfaces
    sudo ip link show > ${tmp_dir}/ip-link-show.txt
# Collect DNS config
    sudo cat /etc/resolv.conf > ${tmp_dir}/resolv.conf.txt
# Check conntrack limits
    sudo cat /proc/sys/net/netfilter/nf_conntrack_max > ${tmp_dir}/nf_conntrack_max.txt
}

colletContainerLogs() {
    echo "Collect Container Logs"
# Check docker 
    sudo systemctl status docker > ${tmp_dir}/systemctl-status-docker.txt
    sudo docker ps -a > ${tmp_dir}/docker-ps-a.txt
    sudo docker info > ${tmp_dir}/docker-info.txt
    sudo docker images > ${tmp_dir}/docker-images.txt
# Check containerd
    sudo crictl ps -a > ${tmp_dir}/crictl-ps-a.txt
    sudo crictl info > ${tmp_dir}/crictl-info.txt
    sudo crictl images > ${tmp_dir}/crictl-images.txt
# Check for containerd free space
    sudo df -h /var/lib/containerd > ${tmp_dir}/df-h-containerd.txt
# Test containerd socket
    sudo test -S /var/run/containerd/containerd.sock; echo $? > ${tmp_dir}/containerd.sock.txt
# Output of systemd script that loads containers
    sudo journalctl -u load-gc-containers > ${tmp_dir}/journalctl-u-load-gc-containers.txt
}

colletK8sLogs() {
    echo "Collect Kubelet Logs"
# Check if kubelet is running and collect logs
    sudo systemctl status kubelet > ${tmp_dir}/systemctl-status-kubelet.txt
    sudo journalctl -xeu kubelet > ${tmp_dir}/journalctl-xeu-kubelet.txt
}

colletCloudInitLogs() {
    echo "Collect Cloud-Init Logs"
# Collecting cloud-init logs
    sudo cat /var/log/cloud-init-output.txt > ${tmp_dir}/cloud-init-output.txt
}

colletFileLogs() {
    echo "Collect File Logs"
    sudo df > ${tmp_dir}/df.txt
    sudo df -i > ${tmp_dir}/df-i.txt
    sudo mount > ${tmp_dir}/mount.txt
# Check file descriptor availability
    sudo sysctl fs.file-nr > ${tmp_dir}/sysctl-fs.file-nr.txt
# Check that swap is disabled
    sudo swapon -s > ${tmp_dir}/swapon-s.txt
# Check open file limits
    sudo cat /proc/sys/fs/file-max > ${tmp_dir}/file-max.txt
}

createLogFile() {
    echo "Create log-file: ${output_file}"
    tar -czf ${output_file} ${tmp_dir}
}

pause(){
 read -s -n 1 -p "Press any key to continue . . ."

}
 

setupLogDirectory
colletOSLogs
colletRunTimeLogs
colletProcessesLogs
colletNetworkLogs
colletContainerLogs
colletK8sLogs
colletCloudInitLogs
colletFileLogs
createLogFile
## Pause it ##
pause
