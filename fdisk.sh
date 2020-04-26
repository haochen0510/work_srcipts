#!/bin/bash
##date:2020-04-15
#!/bin/bash
disk_list=( /dev/sdb /dev/sdc /dev/sdd /dev/sde /dev/sdf /dev/sdg /dev/sdh )
function fenqu(){
echo "n
p
1


w" |fdisk $1
sleep 3
mkfs.ext4 $2
mkdir -p /data/ES$3
echo $2               /data/ES$3                   "ext4    defaults        0 0" >> /etc/fstab

}

function main (){
    n=1
    for i in ${disk_list[*]};
    do
        #echo $i
        Check_one=`fdisk -l |grep $i`
        Check_two=`echo $i"1"`
        Check_one1=`fdisk -l |grep $Check_two`
        echo $Check_one1
        if [[ -z ${Check_one} ]];then
            echo "Disk" $i "not exist!!!!"
            exit 1
        fi
    if [[ ! -z ${Check_one1} ]];then
        echo "Disk" $Check_one1 " exist,please check!!!!"
            exit 1
    fi
        fenqu $i $Check_two $n
        let n++
    done
    mount -a
    df -h
    #rm -f $0
    exit 0
}
main
