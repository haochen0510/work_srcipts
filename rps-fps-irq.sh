
#!/bin/bash
# This is the default setting of networking multiqueue and RPS/XPS/RFS on ECS.
# 1.启用多队列（如果可用，旧的内核版本不支持网卡多队列）
# 2.启用RPS/XPS优化
# 3.启用RFS优化
# 4.irqbalance服务
# author: hao.chen
# Programmer who writing code without remarks is Wild.

# 检查并设置支持的网卡队列
function set_check_multiqueue()
{
    eth=$1
    log_file=$2
#GET system支持的队列数目queue_num
    queue_num=$(ethtool -l $eth | grep -iA5 'pre-set' | grep -i combined | awk {'print $2'})

#如果是多队列网卡就直接设置网卡目前的对列数为系统支持的队列数目


	if [ $queue_num -gt 1 ]; then
		# set multiqueue
		ethtool -L $eth combined $queue_num
		# check multiqueue setting
		cur_q_num=$(ethtool -l $eth | grep -iA5 current | grep -i combined | awk {'print $2'})
		if [ "X$queue_num" != "X$cur_q_num" ]; then
			echo "Failed to set $eth queue size to $queue_num" >> $log_file
			echo "after setting, pre-set queue num: $queue_num , current: $cur_q_num" >> $log_file
			return 1
		else
			echo "OK. set $eth queue size to $queue_num" >> $log_file
		fi
	#如果是单一队列网卡，不需要设置
	else
		echo "only support $queue_num queue; no need to enable multiqueue on $eth" >> $log_file
	fi
}

# 根据核心数目生成cpu掩码
function count_cpuset()
{
    cpu_num=$(grep -c processor /proc/cpuinfo)
    quotient=$((cpu_num/4))
#如果核心数目大于32
    if [ $quotient -gt 8 ]; then
        quotient=8
#小于4个核心
    elif [ $quotient -lt 1 ]; then
        quotient=1
    fi
#cpu掩码的规律 4--f 8--ff 12--fff 16--ffff 32--ffffffff
#根据核心数目生成cpu掩码
	for i in $(seq $quotient)
    do
        cpuset="${cpuset}f"
    done
#小于4个核心
    if [ $cpu_num -lt 4 ]; then
        for i in $(seq $cpu_num)
        do
            bin_mask="${bin_mask}1"
        done
        ((cpuset=2#${bin_mask}))
    fi
    echo $cpuset
}

#配置 RPS/XPS 
function set_rps_xps()
{
    eth=$1
    cpuset=$2
    for rps_file in $(ls /sys/class/net/${eth}/queues/rx-*/rps_cpus)
    do
        echo $cpuset > $rps_file
    done
    for xps_file in $(ls /sys/class/net/${eth}/queues/tx-*/xps_cpus)
    do
        echo $cpuset > $xps_file
    done
}

# 检查 RPS/XPS 是否与计算得到的掩码一致 
function check_rps_xps()
{
    eth=$1
	#exp_cpus是mask
    exp_cpus=$2
    log_file=$3
    ((exp_cpus=16#$exp_cpus))
    ret=0
    for rps_file in $(ls /sys/class/net/${eth}/queues/rx-*/rps_cpus)
    do
        ((cur_cpus=16#$(cat $rps_file | tr -d ",")))
        if [ "X$exp_cpus" != "X$cur_cpus" ]; then
            echo "Failed to check RPS setting on $rps_file" >> $log_file
            echo "expect: $exp_cpus, current: $cur_cpus" >> $log_file
            ret=1
        else
            echo "OK. check RPS setting on $rps_file" >> $log_file
        fi
    done
    for xps_file in $(ls /sys/class/net/${eth}/queues/tx-*/xps_cpus)
    do
        ((cur_cpus=16#$(cat $xps_file | tr -d ",")))
        if [ "X$exp_cpus" != "X$cur_cpus" ]; then
            echo "Failed to check XPS setting on $xps_file" >> $log_file
            echo "expect: $exp_cpus, current: $cur_cpus" >> $log_file
            ret=1
        else
            echo "OK. check XPS setting on $xps_file" >> $log_file
        fi
    done
    return $ret
}

# 配置 RFS 方法1
function set_check_rfs1()
{
    log_file=$1
    total_queues=0
    rps_flow_cnt_num=4096
    rps_flow_entries_file="/proc/sys/net/core/rps_sock_flow_entries"
    ret=0
    for j in $(cd /sys/class/net/ && ls)
    do
        eth=$(basename $j)
        queues=$(ls -ld /sys/class/net/$eth/queues/rx-* | wc -l)
        total_queues=$(($total_queues + $queues))
        for k in $(ls /sys/class/net/$eth/queues/rx-*/rps_flow_cnt)
        do
            echo $rps_flow_cnt_num > $k
            if [ "X$rps_flow_cnt_num" != "X$(cat $k)" ]; then
                echo "Failed to set $rps_flow_cnt_num to $k" >> $log_file
                ret=1
            else
                echo "OK. set $rps_flow_cnt_num to $k" >> $log_file
            fi
        done
    done
    total_flow_entries=$(($rps_flow_cnt_num * $total_queues))
    if [ $total_flow_entries -gt 65536 ]; then
        total_flow_entries=65536
    fi
    echo $total_flow_entries > $rps_flow_entries_file
    if [ "X$total_flow_entries" != "X$(cat $rps_flow_entries_file)" ]; then
        echo "Failed to set $total_flow_entries to $rps_flow_entries_file" >> $log_file
        ret=1
    else
        echo "OK. set $total_flow_entries to $rps_flow_entries_file" >> $log_file
    fi
    return $ret
}

# 配置 RFS 方法2
function set_check_rfs()
{
    log_file=$1
    total_queues=0
    rps_flow_entries_file="/proc/sys/net/core/rps_sock_flow_entries"
    ret=0
    total_flow_entries=32768
    for j in $(cd /sys/class/net/ && ls)
    do
        eth=$(basename $j)
        queues=$(ls -ld /sys/class/net/$eth/queues/rx-* | wc -l)
        total_queues=$(($total_queues + $queues))
    done
	rps_flow_cnt_num=$(($total_flow_entries / $total_queues))
	for k in $(ls /sys/class/net/$eth/queues/rx-*/rps_flow_cnt)
        do
            echo $rps_flow_cnt_num > $k
            if [ "X$rps_flow_cnt_num" != "X$(cat $k)" ]; then
                echo "Failed to set $rps_flow_cnt_num to $k" >> $log_file
                ret=1
            else
                echo "OK. set $rps_flow_cnt_num to $k" >> $log_file
            fi
        done
    echo $total_flow_entries > $rps_flow_entries_file
    if [ "X$total_flow_entries" != "X$(cat $rps_flow_entries_file)" ]; then
        echo "Failed to set $total_flow_entries to $rps_flow_entries_file" >> $log_file
        ret=1
    else
        echo "OK. set $total_flow_entries to $rps_flow_entries_file" >> $log_file
    fi
    return $ret
}

# start irqbalance service
#not use at this script
function start_irqblance()
{
    log_file=$1
    ret=0
    cpu_num=$(grep -c processor /proc/cpuinfo)
    if [ $cpu_num -lt 2 ]; then
        echo "No need to start irqbalance" >> $log_file
        echo "found $cpu_num processor in /proc/cpuinfo" >> $log_file
        return $ret
    fi
    if [ "X" = "X$(ps -ef | grep irqbalance | grep -v grep)" ]; then
        systemctl start irqbalance
        sleep 1
        systemctl status irqbalance &> /dev/null
        if [ $? -ne 0 ]; then
            echo "Failed to start irqbalance" >> $log_file
            ret=1
        else
            echo "OK. irqbalance started." >> $log_file
        fi
    else
        echo "irqbalance is running, no need to start it." >> $log_file
    fi
    return $ret
}

#建议关闭irqbalance服务，自己配置smp_affinity
#注意:smp_affinity对单队列网卡不生效
function set_smp_affinity()
{
	log_file=$1
		ret=0
	cpu_num=$(grep -c processor /proc/cpuinfo)
		if [ $cpu_num -lt 2 ]; then
			echo "No need to change irqbalance" >> $log_file
			echo "found $cpu_num processor in /proc/cpuinfo" >> $log_file
			return $ret
		fi
		
	#设置irqbalance服务开机默认关闭
	sed -i '/^ENABLED=/c ENABLED=0' /etc/default/irqbalance
	if [ "X" != "X$(ps -ef | grep irqbalance | grep -v grep)" ]; then
		systemctl stop irqbalance
		sleep 1
		systemctl status irqbalance &> /dev/null
		if [ $? -eq 0 ]; then
			echo "Failed to stop irqbalance" >> $log_file
			ret=1
		else
			echo "OK. irqbalance stopped." >> $log_file
		fi
	else
		echo "irqbalance is not running, no need to stop it." >> $log_file
	fi

	irq_number=`cat /proc/interrupts |grep -i pci |awk -F ':' '{print $1}'`
	echo "中断号是${irq_number}" >>$log_file
    bitmask=$(irq_bitmask)
	echo "irq掩码是$bitmask">>$log_file
	for n in $irq_number
		do
			echo "$bitmask" >/proc/irq/$n/smp_affinity
			if [ $? -eq 0 ]; then 
				echo "Success, set $bitmask to /proc/irq/$n/smp_affinity" >>$log_file
			else
				echo "Falied, set $bitmask to /proc/irq/$n/smp_affinity" >>$log_file
			fi
		done
	return $ret 
}
function irq_bitmask()
{
    mask_txt=/tmp/mask_2.txt
    cpu_num=$(cat /proc/cpuinfo|grep processor|wc -l)
    #cpu_num=8
    cpu_num1=$((cpu_num-1))
    #bitmask=0
    echo 1 >/tmp/mask_2.txt
            for i in $(seq $cpu_num1)
                    do
                            numberset="${numberset}0"
                            mask_2="1${numberset}"
                            echo ${mask_2}>>$mask_txt
               done
    for bitmask in `cat $mask_txt`
    do
            rel_bitmask=$(($rel_bitmask+$bitmask))
    done

	tmp1=`echo $((2#$rel_bitmask))` 
	rel_bitmask_16=$(echo "obase=16;$tmp1"|bc )
	
	echo "cpu的核数是$cpu_num,对应的irq_mask是$rel_bitmask，转换成16进制是 $rel_bitmask_16">>$log_file
	echo $rel_bitmask_16>>$log_file
	echo $rel_bitmask_16
}

# main logic


function main()
{
    network_log=/var/log/network_log
    echo "脚本执行日志在$network_log"
    sleep 2
    ret_value=0
    rps_xps_cpus=$(count_cpuset)
    echo -e '\n\n\n\n\n\n\n'>>$network_log
    echo "新的一次执行脚本" >>$network_log
    echo "running $0" >> $network_log
    # we assume your NIC interface(s) is/are like eno*
    eth_dirs=$(cd /sys/class/net/ && ls)
    echo "========  network setting starts $(date +'%Y-%m-%d %H:%M:%S') ========" >> $network_log
    for i in $eth_dirs
    do
        cur_eth=$(basename $i)
        echo "set and check multiqueue on $cur_eth" >> $network_log
		ethtool -l $cur_eth 
		if [ $? -eq 0 ]; then
			set_check_multiqueue $cur_eth $network_log
			if [ $? -ne 0 ]; then
				echo "Failed to set multiqueue on $cur_eth" >> $network_log
				ret_value=1
			fi
		else 
			echo "网卡$cur_eth不支持多队列"	
		fi 
        echo "enable RPS/XPS on $cur_eth" >> $network_log
        set_rps_xps $cur_eth $rps_xps_cpus
        echo "check RPS/XPS on $cur_eth" >> $network_log
        check_rps_xps $cur_eth $rps_xps_cpus $network_log
        if [ $? -ne 0 ]; then
            echo "Failed to enable RPS/XPS on $cur_eth" >> $network_log
            ret_value=1
        fi
    done
    echo "set and check RFS" >> $network_log
    set_check_rfs $network_log
    if [ $? -ne 0 ]; then
        ret_value=1
    fi
    echo "stop irqbalance service" >> $network_log
    #start_irqblance $network_log
	set_smp_affinity $network_log
    if [ $? -ne 0 ]; then
        ret_value=1
    fi
    echo "========  ECS network setting END $(date +'%Y-%m-%d %H:%M:%S')  ========" >> $network_log
    return $ret_value
}

# program starts here
main
exit $?


