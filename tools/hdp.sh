#!/bin/bash
# Script name: hdp.sh
# Date & Time: 2013-04-18/21:06:08
# Description:
# Author: MOS
#. $HOME/.bash_profile
 
[ -f /etc/sysconfig/hdp.conf ] && . /etc/sysconfig/hdp.conf
 
# IP
Ne=${Ne:-eth0}
Bp=${Bp:-static}
Ip=${Ip:-192.168.189.162}
Gw=${Gw:-192.168.189.2}
Nk=${Nk:-255.255.255.0}
Ds1=${Ds1:-192.168.189.2}
Ds2=${Ds2:-8.8.8.8}
 
Px=${Px:-hdp}
Epe=${Epe:-sgm.com}
Oip=${Oip:-192.168.1.144}
Rpm_Sum=${Rpm_Sum:-1160}
Mlog=${Mlog:-/var/log/mos.log}
Run_Node=${Run_Node:-ALL}
T_Server=${T_Server:-$Ip}
SDIR=${SDIR:-/storage/disk}
 
# 系统平台判断(ubuntu/centos),仅用于磁盘部分函数
if [ -x /bin/awk ];then
    AWK=/bin/awk
    CUT=/bin/cut
elif [ -x /usr/bin/awk ];then
    AWK=/usr/bin/awk
    CUT=/usr/bin/cut
fi
 
Date="/bin/date +%H:%M:%S/%Y-%m-%d"
Hnb=`echo $Ip|$AWK -F\. '{print $NF}'`
Hn="$Px"$Hnb.$Epe
HF=/etc/hosts_sh
NUL=/dev/null
YRD=/etc/yum.repos.d
MD5=/usr/bin/md5sum
 
Hnc=/etc/sysconfig/network
Dec=/etc/sysconfig/network-scripts/ifcfg-$Ne
 
SCP="/usr/bin/scp -r -p -o StrictHostKeyChecking=no"
YUM="/usr/bin/yum -y install"
PING="/bin/ping -c 3 -W 1"
SYNC="/usr/bin/rsync -a"
SSH="/usr/bin/ssh -q -o StrictHostKeyChecking=no"
 
RSYNC(){
    $SYNC -e "$SSH" $1 $2
}
 
H_lc=`/sbin/ifconfig $Ne|grep Bcast|$AWK '{print $2}'|$AWK -F: '{print $2}'`
Gme=`uname -n`
A_cmd=(`grep $Epe $HF|grep -vE "\<$Gme\>|\<$H_lc\>"|$AWK '{print $1}'`)
 
TEE(){
    /usr/bin/tee -a $Mlog
}
 
HDP_CONF(){
    H_lc=`/sbin/ifconfig $Ne|grep Bcast|$AWK '{print $2}'|$AWK -F: '{print $2}'`
    Gme=`uname -n`
    A_cmd=(`grep $Epe $HF|grep -vE "\<$Gme\>|\<$H_lc\>"|$AWK '{print $1}'`)
    LCF=/etc/sysconfig/hdp.conf
    TCF=/tmp/hdp.conf
    for i in ${A_cmd[@]};do
        $SYNC $LCF $TCF
        RNE=`$SSH $i /sbin/ip a|grep $i|$AWK '{print $NF}'`
        RNK=`$SSH $i /sbin/ifconfig $RNE|grep 'Mask:'|$AWK '{print $NF}'|$CUT -d: -f2`
        RGW=`$SSH $i /sbin/route|grep $RNE|grep default.*UG.*$eth|$AWK '{print $2}'`
        RGW=${RGW:-$Gw} ; RNK=${RNK:-$Nk}
        sed -i "s@\(^Ne=\).*@\1$RNE@g" $TCF
        sed -i "s@\(^Nk=\).*@\1$RNK@g" $TCF
        sed -i "s@\(^Gw=\).*@\1$RGW@g" $TCF
        sed -i "s@\(^Ip=\).*@\1$i@g" $TCF
        RSYNC $TCF $i:$LCF &> $NUL
        $SSH $i /bin/hhdp -i &> $NUL
    done
}
 
 
Func_cmd(){
    F_cmd=${F_cmd:-"/bin/uname -n && grep IPADDR $Dec && date +%Y-%m-%d~%k:%M:%S"}
    if [ "$TAG" == "-cl" ];then
        for i in ${A_cmd[@]};do
                $SSH $i $F_cmd &>> $Mlog &
            echo "`$Date` : $F_cmd done in $i"
        done
        if [[ "$Run_Node" == "ALL" ]];then
            $SSH $H_lc $F_cmd &>> $Mlog &
            echo "`$Date` :  $F_cmd done in local"
        fi
    else
        for i in ${A_cmd[@]};do
                $SSH $i $F_cmd
        done
        if [[ "$Run_Node" == "ALL" ]];then
            $SSH $H_lc $F_cmd
        fi
    fi
}
 
C_fe(){
    [[ ! -f "$L_file" && ! -d "$L_file"  ]] && echo "`$Date` $L_file invalid." >> $Mlog && exit 1
    for i in ${A_cmd[@]};do
        if [[ -d "$L_file" ]];then
            L_file=$L_file/
            D_file=$D_file/
            $SSH $i mkdir -p $D_file
        fi
        RSYNC $L_file $i:$D_file
    done   
}
 
HOSTS(){
    if [[ ! -f /var/www/html/local_dvd/other/hdp.sh ]];then
        echo "`$Date` Error,this cmd can only excute on yum server."|TEE
        return 0
    fi
    for i in ${HT[@]};do
            /bin/ping -c 2 -W 1 $i &> $NUL
        R_1=$?
        [ "$R_1" -ne 0 ] && echo "`$Date` $i Offline!" >> $Mlog
        R_2=`/bin/grep $i $HF`
        if [ -z "$R_2" ];then
                PX_IP=`echo $i|$AWK -F. '{print $NF}'`
                Npx="$Px""$PX_IP"
        if $SSH $i test -f /var/www/html/local_dvd/other/hdp.sh;then
                    echo -en "$i\t$Npx.$Epe\t$Npx\tpublic-repo-1.hortonworks.com\n" >> $HF
            continue
        fi
                echo -en "$i\t$Npx.$Epe\t$Npx\n" >> $HF
        else
                echo "`$Date` $i exist in $HF." >> $Mlog
        fi
    done
}
 
Help(){
    GH="\033[0m"
    while :;do
        RDM=`echo $(($RANDOM%7))`
        [[ "$RDM" -ne 0 ]] && break
    done
    GQ="\033[3"$RDM"m"
    echo "Usage: $0 [OPTION] [arguments1] [arguments2] [...]"
    echo -en "\t$GQ"Any"$GH : help\n"
    echo -en "\t$GQ-a$GH : Install Ambari-server.\n"
    echo -en "\t$GQ-i$GH : Config localhost IP,DNS and Hostname.\n"
    echo -en "\t$GQ-r$GH : Cluster file sync.\n"
    echo -en "\t$GQ-s$GH : Identify and use effective disk.\n"
    echo -en "\t$GQ-m$GH : Init cluster system environment [equal to use command like -n,-s,-r,-i,etc].\n"
    echo -en "\t$GQ-n$GH : Write cluster node info to $HF, first you need to config /etc/sysconfig/hdp.conf.\n"
    echo -en "\t$GQ-C$GH : Modify hdp.conf on every node and make it effective .\n "
    echo -en "\t$GQ-e /dev/disk$GH : Specify disk.\n"
    echo -en "\t$GQ-c/cl shell_cmd ... $GH: The shell_cmd will be excuted on all nodes of the cluster. Use -cl to excute in parallel mode\n"
    echo -en "\t$GQ-f /local/path/file1 /target/path/file2$GH : Custom sync file.\n"
    echo -en "\t$GQ-M /local/path/file node1..node^n$GH : MD5 file check.(Supports all the formats defined in /etc/hosts.)\n"
    echo -en "\t$GQ--auto-nic$GH :Test environment modification udev name nic.\n"
    echo -en "\t$GQ--remove$GH : Remove local ambari.\n"
            echo -en "\t$GQ--storm-master start/stop$GH :Need to start on the storm master node.\n"
        echo -en "\t$GQ--storm-slave start/stop$GH :Need to start on the storm slave node.\n"
}
 
Rtime(){
    sed -i "s@\(^[[:space:]]\{1,\}disable[[:space:]]\{1,\}= \)yes@\1no@g" /etc/xinetd.d/time-stream
}
 
AMBARI_INSTALL(){   
    echo -en "\033[32m `$Date` Ambari server Installing, please wait ...\033[0m\n"|TEE
    while :;do
        S_RUN1=`netstat -tnlp|grep 8080`
        S_RUN2=`ps aux|grep ambari-server|grep -v grep`
        ALIAS=
        if [[ -n "$S_RUN1" && -n "$S_RUN2" ]];then
            echo -en "\033[32m `$Date` Ambari server install done. \n User/Passwd: admin/admin\n Web: http://`hostname -s`:8080 or http://`uname -n`:8080 or http://$Ip:8080 \033[0m\n"|TEE
            RSYNC $Yum_IP:/var/www/html/downloads/logo* /usr/lib/ambari-server/web/img/ &> $NUL
            chmod -R 755 /usr/lib/ambari-server/web/img/logo* &> $NUL
            break
        else
            Absr=`rpm -qa|grep ambari-server`
            Yum_IP=`grep baseurl /etc/yum.repos.d/ambari.repo|$AWK -F\/ '{print $3}'|/usr/bin/uniq`
            if [ -z "$Absr" ];then
                $YUM ambari-server &> $NUL
            fi
            if [ -d /var/lib/ambari-server/resources/ ];then
                RSYNC $Yum_IP:/var/www/html/ARTIFACTS/jdk* /var/lib/ambari-server/resources/  &> $NUL
            else
                echo "`$Date` copy JDK error. Check ambari-server install status!!!" >> $Mlog
            fi
            if [ -x /usr/sbin/ambari-server ];then
                echo -en "\n\n\n\n\n"|/usr/sbin/ambari-server setup >> $Mlog
                sleep 5
                /usr/sbin/ambari-server start &> $NUL
                sleep 5
            else
                echo "`$Date` ambari-server install fail !" >> $Mlog
            fi
            let BRD++
            [ "$BRD" -eq 3 ] && echo "`$Date` Ambari-server setup failed." >> $Mlog && exit 5
            sleep 5
        fi
    done
}
 
Copy(){
    [[ ! -d /var/www/html/ ]] && /bin/mkdir -p /var/www/html/{local_dvd,downloads} &> $NUL
    $SYNC /mnt/other/html/ /var/www/html/ &> $NUL
    $SYNC --exclude=other /mnt/ /var/www/html/local_dvd/ &> $NUL
    [[ ! -d /var/www/html/local_dvd/other ]] && /bin/mkdir -p /var/www/html/local_dvd/other &> $NUL
    $SYNC --exclude=html /mnt/other/ /var/www/html/local_dvd/other/ &> $NUL
    HOSTS
}
 
Mount(){
    Sr=(`ls /dev/sr*`)
    Test="/mnt/other/hdp.sh"
    for c in ${Sr[@]};do
        [ -f "$Test" ] && break
            /bin/umount /mnt &> $NUL
            /bin/mount -r $c /mnt
        if [ -d /mnt/other ] ;then
            RPM_SUM=`find /mnt/ -name "*.rpm"|/usr/bin/wc -l`
            if [ -f /etc/sysconfig/hdp.conf ];then
                /bin/sed -i "s@Rpm_Sum=.*@Rpm_Sum=$RPM_SUM@g" /etc/sysconfig/hdp.conf
                . /etc/sysconfig/hdp.conf
            else
                echo "`$Date` War: /etc/sysconfig/hdp.conf not exist!" >> $Mlog
            fi
        fi
    done
}
 
Repo(){
    Mount
    for i in ${REPO[@]};do
        /bin/cp -a /mnt/other/$i $YRD/$i
        /bin/chmod 644 $YRD/$i
    done
}
 
Umt(){
    NOW_DISK=(`df|grep $SDIR|$AWK '{print $1}'`)
    for disk in ${NOW_DISK[@]};do
        RES_DISK=`/sbin/blkid|grep "$disk"`
        if [ -z "$RES_DISK" ];then
            /bin/umount -l $disk
        fi
    done
    Ut=(`grep $SDIR /etc/fstab|$AWK '{print $2}'`)
    Ud=(`grep $SDIR /etc/fstab|$AWK -F\" '{print $2}'`)
    for d in ${Ut[@]};do
        if [ -d $d ];then
            #Dk=`df $d|$AWK '{print $1}'|/usr/bin/tail -1`
            Dk=`mount|grep "$d\>"|$AWK '{print $1}'`
            Ud=`/sbin/blkid $Dk|$AWK -F\" '{print $2}'`
            Td=`grep $d /etc/fstab|$AWK -F\" '{print $2}'`
            [ -b "$Dk" ] && Uft=`/sbin/parted $Dk print|/usr/bin/tail -2|/usr/bin/head -1|$AWK '{print $5}'`
            Tft=`grep $d /etc/fstab|$AWK '{print $3}'`
            if [[ $Ud != $Td || $Uft != $Tft ]];then
                /bin/umount $d &> $NUL
                /bin/sed -i "/$d/d" /etc/fstab &> $NUL
            fi     
        fi
    done
    for d in ${Ud[@]};do
        Unull=`/sbin/blkid|grep $d`
        if [[ -z $Unull ]];then
            Mpit=`grep $d /etc/fstab|$AWK '{print $2}'`
            /bin/umount $Mpit &> $NUL
            /bin/sed -i "/$d/d" /etc/fstab &> $NUL
        fi
    done
 
}
 
Mmu(){
    declare -i P=1
    Tb=/etc/fstab
    Ftb(){
        Sft=`/sbin/blkid $Fph|$AWK -F\" '{print $2}'`
        Ft=`grep "\<disk$P\>" $Tb`
        Gud=`grep "\<$Sft\>" $Tb`
        [[ -n $Ft ]] && /bin/sed -i "/\<disk$P\>/"d $Tb
        [[ -n $Gud ]] && /bin/sed -i "/\<$Sft\>/"d $Tb
    }
    Add(){
        Ef=`/sbin/blkid $Fph`
        [[ -z $Ef ]] && /bin/echo y|/sbin/mkfs.ext4 $Fph &> $NUL
        Uuid=`/sbin/blkid -s UUID $Fph|$AWK '{print $2}'`
        #Fs=`/sbin/parted  $Fph print|/usr/bin/tail -2|/usr/bin/head -1|$AWK '{print $5}'`
        Fs=`/sbin/blkid -s TYPE $Fph|$AWK -F\" '{print $2}'`
        Fr="defaults,noatime,data=writeback,barrier=0,nobh"
        echo -en "$Uuid\t$SDIR$P\t$Fs\t$Fr\t0 0\n" >> $Tb
        /bin/mount -a &> $NUL
        break
    }
    Fe(){
        Mtp=`mount|grep "$SDIR$P\>"`
        if [[ -n "$Mtp" ]];then
            echo "`$Date` $Mp is used." >> $Mlog
        else
            Ftb
            Add
        fi
    }
    while : ;do
        if [[ -d "$SDIR$P" ]];then
            Fe
        else
            /bin/mkdir -p "$SDIR$P" && Ftb
            Add
        fi
 
        P=P+1
    done
}

# 此函数用于通知内核重新读取磁盘设备
RELOAD_STORAGE(){
	/etc/init.d/haldaemon restart &> $NUL
#	/etc/init.d/messagebus restart &> $NUL
	[ -x /sbin/partprobe ] && /sbin/partprobe &> $NUL
} 

Check_disk(){
    RELOAD_STORAGE
    Umt
    /bin/mount -a &> $NUL
    for b in ${Exist[@]};do
        Fph="$Dph$b"
 
        [[ ! -b "$Fph" ]] && echo "`$Date` $Fph is not block device !!!" >> $Mlog && continue
 
        CTE=`ls "$Fph"*|/usr/bin/wc -l`
        [[ "$CTE" -ne 1 ]] && echo "`$Date` $Fph mismatches." >> $Mlog && continue
 
        DFM=`mount|$AWK '{print $1}'|grep "^$Fph$" 2>$NUL`
        [[ -n "$DFM" ]]  && echo "`$Date` $Fph is used." >> $Mlog && continue
 
        Ugd=`/sbin/parted $Fph print|/usr/bin/wc -l`
        [[ "$Ugd" -ge 8 &&  -n "$DFM" ]] && echo "`$Date` parted $Fph >= 8 ." >> $Mlog && continue
 
        Lvm=`/sbin/blkid $Fph|grep -E "LVM2_member|swap"`
        [[ -n "$Lvm" ]] && echo "`$Date` $Fph is LVM or swap." >> $Mlog && continue
 
        Fgd=`/sbin/fdisk -l $Fph|/usr/bin/wc -l`
        [[ "$Fgd" -ge 10 ]] && echo "`$Date` fdisk -l $Fph >=10 ." >> $Mlog && continue       
 
        Mmu
    done
}
 
NFS_SUPPORT(){
    if [[ "$NNN" == True &&  "$TAG" != "-k" ]] ;then
        NFS_IP=${NFS_IP:-192.168.1.144}
        NFS_Dir=${NFS_Dir:-/hdp_disk}
        NN_N=${NN_N:-hdp198.wd.com}
        NN_MP=${NN_MP:-/storage/nfs}
        P_CMD="/bin/ping -c 3 -W 1"
        while :;do
            if $P_CMD $NFS_IP &> $NUL && $P_CMD $NN_N &> $NUL;then
                if ! $SSH $NN_N test -d $NN_MP &>$NUL;then
                    $SSH $NN_N  mkdir -p $NN_MP
                fi
                if ! $SSH $NFS_IP test -d $NFS_Dir &>$NUL;then
                    $SSH $NFS_IP mkdir -p $NFS_Dir
                fi
                if /usr/sbin/showmount -e $NFS_IP 2> $NUL|grep "$NFS_Dir" &> $NUL;then
                    if ! $SSH $NN_N "mount|grep $NFS_IP" &>$NUL && ! $SSH $NN_N "mount|grep $NN_MP" &>$NUL;then
                        if $SSH $NN_N /sbin/ip a|grep -E "$Phy_IP|$Slave_IP" &>$NUL;then
                            $SSH $VIP /etc/init.d/network restart &>$NUL
                            sleep 10
                            $SSH $NN_N mount -t nfs -o vers=3,rw,soft,nolock $NFS_IP:$NFS_Dir $NN_MP &> $NUL
                        else
                            $SSH $NN_N mount -t nfs -o vers=3,rw,soft,nolock $NFS_IP:$NFS_Dir $NN_MP &> $NUL
                        fi
                    fi
                else
                    TMP_DIR=`/bin/mktemp /tmp/nfs.XXXXXX`
                    echo -en "$NFS_Dir\t*(rw,sync,no_root_squash)\n" >> $TMP_DIR
                    RSYNC $TMP_DIR $NFS_IP:/etc/exports &> $NUL
                    $SSH $NFS_IP /sbin/service nfs restart &> $NUL
                    $SSH $NN_N mkdir -pv $NN_MP &> $NUL
                    $SSH $NFS_IP /sbin/chkconfig nfs on
                    if $SSH $NN_N /sbin/ip a|grep -E "$Phy_IP|$Slave_IP" &>$NUL;then
                        $SSH $VIP /etc/init.d/network restart &>$NUL
                        sleep 10
                        $SSH $NN_N mount -t nfs -o vers=3,rw,soft,nolock $NFS_IP:$NFS_Dir $NN_MP &> $NUL
                    else
                        $SSH $NN_N mount -t nfs -o vers=3,rw,soft,nolock $NFS_IP:$NFS_Dir $NN_MP &> $NUL
                    fi
                fi
                $SSH $VIP /etc/init.d/network restart &> /dev/null &
                echo "`$Date` : NameNode and NFS OK."|TEE
                break
            else
                echo "`$Date` War: NFS or NameNode_Master Offline!!."|TEE
        echo "Please check network the NFS or Namenode_Master. (yes[Check OK after]/ignore[Not use HA]): "
                read -p "yes/ignore : " NNN
                [[ "$NNN" == "ignore" || "$NNN" = "I" ]] && echo "`$Date`: Ignore HA config."|TEE && break
            fi
            sleep 1
        done
    fi
}
 
TIME_AND_YUM_AND_NFS(){
    Pkg[0]=httpd
    Pkg[1]=xinetd
    Lo=/etc/yum.repos.d/localhost.repo
 
    for i in ${Pkg[@]};do
        Rt=`rpm -qa|grep "^\<$i\>"`
        if [ -z "$Rt" ];then
            [ ! -f "$Lo" ] && Mount && /bin/cp /mnt/other/localhost.repo $Lo
            [ ! -f "$Lo" ] && echo "`$Date` $Lo copy fail." >> $Mlog && exit 1
            $YUM $i &> $NUL
            if [ "$i" == httpd ];then
                [[ ! -d /var/www/html/local_dvd ]] && Copy
                /sbin/chkconfig $i on &> $NUL
                /sbin/service $i restart &> $NUL
            elif [ "$i" == xinetd ];then
                /sbin/chkconfig $i on &> $NUL
                Te=`grep disable /etc/xinetd.d/time-stream|grep yes`
                [ -n "$Te" ] && Rtime
                /sbin/service $i restart &> $NUL
            fi
        fi
    done
    Repo
    for i in ${Pkg[@]};do
        Rt=`rpm -qa|grep $i`
        if [[ -n "$Rt" ]];then
            Sts=`/sbin/service $i status 2> $NUL|grep pid|grep running`
            [ -z "$Sts" ] && /sbin/service $i restart &> $NUL
            Sts=`/sbin/service $i status 2> $NUL|grep pid|grep running`
            [ -z "$Sts" ] && echo "`$Date` $i start error!" >> $Mlog
            if [ "$i" == httpd ];then
                if [[ ! -d /var/www/html/local_dvd || ! -d /var/www/html/downloads ]];then
                    echo "`$Date`. Error,no such source directory." >> $Mlog
                    echo "`$Date`. Restart sync file. Please wait......" >> $Mlog
                    Mount
                    Copy
                fi
                Sum=`find /var/www/html/ -name "*.rpm"|/usr/bin/wc -l`
                if [[ "$Sum" -ne "$Rpm_Sum" ]] ;then
                    echo "`$Date`. Source count error! " >> $Mlog
                    Mount
                    Copy
                fi
            elif [ "$i" == xinetd ];then
                Tport=`netstat -tnlp|grep $i|grep 37`
                [ -z "$Tport" ] && Rtime && /sbin/service $i restart &> $NUL
                Tport=`netstat -tnlp|grep $i|grep 37`
                [ -z "$Tport" ] && echo "`$Date` Rdate port 37 error!." >> $Mlog
            fi
        fi
    done   
    [[ "$TAG" == "-k" ]] && $YUM tftp-server syslinux-tftpboot dhcp &> $NUL
    [[ -f "$Lo" ]] && /bin/rm -rf $Lo &> $NUL
    [[ -f "/mnt/other/hdp.sh" ]] && /bin/umount /mnt &> $NUL
#    /usr/sbin/eject
}
 
WEB_TIME_CHECK(){
    while :;do
        Dhp=`netstat -tnlp|grep 80|grep httpd`
        Dxp=`netstat -tnlp|grep 37|grep xinetd`
        if [[ -n "$Dhp" && -n "$Dxp" ]];then
            echo -e "\033[32m `$Date` Basic environment install done.\033[0m"|TEE
            [[ $TAG != "-k" ]] && Cluster_sync
            return 0
        else
            TIME_AND_YUM_AND_NFS   
            sleep 5
            let EXIT++
            [ "$EXIT" -eq 5 ] && echo "`$Date` Yum or Time-server install failed." >> $Mlog && exit 5
        fi
    done
}
 
MD5_CHECK(){
    [ ! -f "$D_FILE" ] && echo "`$Date` Error! Invalid file. $D_FILE." >> $Mlog && exit 1
    if [ "$Run_Node" == ALL ];then
        echo -en "`uname -n`\t"
        $MD5 $D_FILE
        echo ""
    fi
    for i in ${FILE_ARY[@]} ;do
        if [[ ! -f "$i" && "$i" != "-M" ]];then
            echo -en "$i\t"
            $SSH $i $MD5 $D_FILE
            echo ""
        fi
    done
 
}
 
TIME_NOW_CHECK(){
        N_TIME=`date +%s`
        if [ "$N_TIME" -lt "$TIME" ];then
                NEW_TIME=`date -d "1970-01-01 UTC $TIME seconds" +%m%d%H%M%Y.%S`
                date $NEW_TIME &> $NUL
                /sbin/hwclock -w &> $NUL
        fi
}
 
NAMENODE_MASTER(){
    Phy_IP=${Phy_IP:-192.168.9.10}
    Slave_IP=${Slave_IP:-192.168.9.11}
    M_IP_Hosts=`grep $Phy_IP $HF`
    S_IP_Hosts=`grep $Slave_IP $HF`
 
    HTNM=`/bin/hostname`
    NAD=`grep $HTNM $HF|$AWK '{print $1}'`
    [[ $NAD != $Phy_IP && $NAD != $Slave_IP && $NAD != $VIP ]] && echo "`$Date` Error: Invalid node."|TEE && return
 
    if [[ -z $M_IP_Hosts ]];then
        PX_IP=`echo $Phy_IP|$AWK -F. '{print $NF}'`
        Npx="$Px""$PX_IP"
        echo -en "$Phy_IP\t$Npx.$Epe\t$Npx\n" >> $HF
    fi
 
    if [[ -z $S_IP_Hosts ]];then
        PX_IP=`echo $Slave_IP|$AWK -F. '{print $NF}'`
        Npx="$Px""$PX_IP"
        echo -en "$Slave_IP\t$Npx.$Epe\t$Npx\n" >> $HF
    fi
 
    #RSYNC $HF $Slave_IP:$HF &> $NUL
    #RSYNC /etc/yum.repos.d/*.repo $Slave_IP:/etc/yum.repos.d/ &> $NUL
    #RSYNC /var/spool/cron/root $Slave_IP:/var/spool/cron/ &> $NUL
 
    [ ! -d /storage/nfs/hadoop_conf/ ] && mkdir -p /storage/nfs/hadoop_conf/
    $SYNC /etc/hadoop/conf.empty/ /storage/nfs/hadoop_conf/ &> $NUL
    [ ! -d /etc/hadoop/conf.empty.bak ] && mv /etc/hadoop/conf.empty /etc/hadoop/conf.empty.bak
    [ -d /etc/hadoop/conf.empty ] && /bin/rm -rf /etc/hadoop/conf.empty
    [ ! -L /etc/hadoop/conf.empty ] && /bin/ln -s  /storage/nfs/hadoop_conf/ /etc/hadoop/conf.empty
 
    RSYNC /storage/ $Slave_IP:/storage/ &> $NUL
 
    #VIP=`ifconfig $Ne|grep Bcast|$AWK '{print $2}'|$AWK -F: '{print $2}'`
 
    [[ "$VIP" == "$Phy_IP" ]] && echo "`$Date` Error! Please phy IP and VIP .." >> $Mlog && exit 1
 
    Stop_if=`ps aux|grep java|grep -v grep`
    if [ -n "$Stop_if" ];then
    /usr/bin/sudo -u hdfs /usr/lib/hadoop/bin/hadoop-daemon.sh --config /usr/lib/hadoop/conf/ stop namenode &>$NUL
        KILL_NN=(`ps aux|grep java|grep -v grep|$AWK '{print $2}'`)
        for KILL in ${KILL_NN[@]};do
            kill -9 $KILL &> $NUL
        done
        umount $NN_MP &> $NUL
    fi
 
    sed -i "s@$VIP@$Phy_IP@g" $Dec
 
    M_Phy_IP=`grep IPADDR $Dec |$AWK -F= '{print $2}'`
    [[ $M_Phy_IP != $Phy_IP ]] && echo "`$Date` Ip edit invalid..!!" >> $Mlog && exit 1
 
    /sbin/service network restart &> $NUL
    echo -en "\033[32m `$Date` Install master node OK. \033[0m\n" |TEE
    #/sbin/init 6 &> $NUL
}
 
RM(){
    echo -en "\033[32m `$Date` Ambari deleting. \033[0m\n" |TEE
    /etc/rc.d/init.d/ambari-server stop &> $NUL
    /etc/rc.d/init.d/ambari-agent stop &> $NUL
    /usr/bin/yum -y remove ambari-agent ambari-server postgresql postgresql-libs postgresql-server &> $NUL
    RM_F[0]=/etc/ambari-agent
    RM_F[1]=/var/ambari-agent
    RM_F[2]=/var/lib/ambari-agent
    RM_F[3]=/usr/lib/ambari-agent
    RM_F[4]=/usr/run/ambari-agent
    RM_F[5]=/etc/ambari-server
    RM_F[6]=/var/lib/ambari-server
    RM_F[7]=/var/run/ambari-server
    RM_F[8]=/usr/run/ambari-server
    RM_F[9]=/var/lib/pgsql
    for i in ${RM_F[@]};do
        [ -d "$i" ] && rm -rf $i &> $NUL
    done
    echo -en "\033[32m `$Date` Remove ambari done. \033[0m\n" |TEE
}
 
NAMENODE_SLAVE(){   
 
    HTNM=`/bin/hostname`
    NAD=`grep $HTNM $HF|$AWK '{print $1}'`
    [[ $NAD != $Phy_IP && $NAD != $Slave_IP && $NAD != $VIP ]] && echo "`$Date` Error: Invalid node."|TEE && return
 
    MF[0]=/etc/passwd
    MF[1]=/etc/group
    MF[2]=/usr/share/man/man1/hadoop.1.gz
    MF[3]=/etc/default/hadoop
    MF[5]=/etc/hadoop/
    MF[6]=/usr/lib/hadoop/
    MF[7]=/usr/bin/hadoop
    MF[8]=/usr/jdk/
    MF[9]=/var/log/hadoop/
    MF[10]=/var/run/hadoop/
    MF[11]=/storage/hadoop/
    MF[12]=/etc/snmp/
    MF[13]=/etc/alternatives/hadoop-default
    MF[14]=/etc/alternatives/hadoop-etc
    MF[15]=/etc/alternatives/hadoop-log
    MF[16]=/etc/alternatives/hadoop-man
    MF[17]=/etc/alternatives/hadoop-conf
    MF[18]=/etc/hadoop/conf
    MF[19]=/etc/ganglia/
    MF[20]=/etc/init.d/hdp-gmond
    MF[21]=/etc/init.d/hdp-gmetad
    MF[22]=/usr/libexec/hdp/
    MF[23]=/var/run/ganglia/
    MF[24]=/etc/ambari-agent/conf/ambari-agent.ini
    MF[25]=/var/lib/ambari-agent/keys/
#    MF[26]=/etc/rc.d/rc.local
 
    Native_Name=`uname -n`
    M_rpm=`$SSH $Phy_IP rpm -qa|grep -E "cman|rgmanager"`
    S_rpm=`rpm -qa|grep -E "cman|rgmanager|ambari"`
    RCPD=${RCPD:-admin}
    if [ -z "$M_rpm" ];then
        $SSH $Phy_IP $YUM cman rgmanager &> $NUL
        $SSH $Phy_IP /sbin/chkconfig cman on &> $NUL
        $SSH $Phy_IP /sbin/chkconfig rgmanager on &> $NUL
        $SSH $Phy_IP /sbin/chkconfig ricci on &> $NUL
        $SSH $Phy_IP /sbin/chkconfig modclusterd on &> $NUL
        $SSH $Phy_IP "echo $RCPD|/usr/bin/passwd --stdin ricci" &> $NUL
    fi
    if [ -z "$S_rpm" ];then
        $YUM cman rgmanager ambari-agent &> $NUL
        /sbin/chkconfig cman on &> $NUL
        /sbin/chkconfig rgmanager on &> $NUL
        /sbin/chkconfig ricci on &> $NUL
        /sbin/chkconfig modclusterd on &> $NUL
        echo $RCPD|/usr/bin/passwd --stdin ricci &> $NUL
    fi
    Dld=`grep baseurl /etc/yum.repos.d/HDP-epel.repo|$AWK -F= '{print $2}'`/other
    if [[ $Master_Name != $Native_Name ]];then
        sed -i "s@$Native_Name@$Master_Name@g" /etc/sysconfig/network
        /bin/hostname $Master_Name
        if [ ! -f /etc/cluster/cluster.conf ];then
            /usr/bin/wget "$Dld/cluster.conf" -P /etc/cluster/ &> $NUL
            HA_conf=/etc/cluster/cluster.conf
            Old_M=`grep "priority=\"1\"" $HA_conf|$AWK -F\" '{print $2}'`
            Old_S=`grep "priority=\"2\"" $HA_conf|$AWK -F\" '{print $2}'`
            Old_VIP=`grep "ip address" $HA_conf|$AWK -F\" '{print $2}'`
            Local_IP=`ifconfig $Ne|grep Bcast|$AWK '{print $2}'|$AWK -F: '{print $2}'`
            New_VIP=`grep $Master_Name /etc/hosts|$AWK '{print $1}'`
            New_M=`grep $Phy_IP /etc/hosts|$AWK '{print $2}'`
            New_S=`grep $Local_IP /etc/hosts|$AWK '{print $2}'`
            sed -i "s@$Old_M@$New_M@g" $HA_conf
            sed -i "s@$Old_S@$New_S@g" $HA_conf
            sed -i "s@$Old_VIP@$New_VIP@g" $HA_conf
            Old_NFS_d=`grep netfs $HA_conf|$AWK -F\" '{print $2}'|grep -v "^$"`
            Old_NFS_IP=`grep netfs $HA_conf|$AWK -F\" '{print $8}'|grep -v "^$"`
            Old_NFS_MP=`grep netfs $HA_conf|$AWK -F\" '{print $10}'|grep -v "^$"`
            sed -i "s@$Old_NFS_IP@$NFS_IP@g" $HA_conf
            sed -i "s@$Old_NFS_d@$NFS_Dir@g" $HA_conf
            sed -i "s@$Old_NFS_MP@$NN_MP@g" $HA_conf
            if [[ "$PRI_M" == "$PRI_S" ]];then
                sed -i "s/priority=\".*\"/priority=\"1\"/g" $HA_conf
            else
                sed -i "s/\(^.*$New_M.*priority=\)\".*\"\(.*$\)/\1\"$PRI_M\"\2/g" $HA_conf
                sed -i "s/\(^.*$New_S.*priority=\)\".*\"\(.*$\)/\1\"$PRI_S\"\2/g" $HA_conf
            fi
            RSYNC $HA_conf $Phy_IP:$HA_conf &> $NUL
        fi
    fi
    IP_SH=/etc/sysconfig/ip_loop.sh
    AR=/etc/rc.d/rc.local
    if [ -x "$IP_SH" ];then
        if ! grep "^$IP_SH" $AR &> $NUL ;then
            echo '/etc/sysconfig/ip_loop.sh' >> $AR
            [ ! -x "$AR" ] && chmod 755 $AR
            RSYNC $AR $Phy_IP:$AR &> $NUL
        fi
        SCREEN=/usr/bin/screen       
        IP_SN=ip_mon
        CREAT_SN=`ps aux|grep $IP_SN|grep -v grep|/usr/bin/wc -l`
        CREAT_SN_R=`$SSH $Phy_IP ps aux|grep $IP_SN|grep -v grep|/usr/bin/wc -l`
        if [ "$CREAT_SN" -eq 0 ];then
            $SCREEN -dmS $IP_SN
        fi
        if [ "$CREAT_SN_R" -eq 0 ];then
            $SSH $Phy_IP $SCREEN -dmS $IP_SN
        fi
        if ! ps aux|grep -v grep|grep $IP_SH &> $NUL;then
            $SCREEN -S $IP_SN -X screen $IP_SH
        fi
        if ! $SSH $Phy_IP ps aux|grep -v grep|grep $IP_SH &> $NUL;then
            $SSH $Phy_IP $SCREEN -S $IP_SN -X screen $IP_SH
        fi
    else
        echo "`$Date` War: /etc/sysconfig/ip_loop.sh not exist or permission error!" >> $Mlog
    fi
    Hm=`$SSH $Phy_IP rpm -qa|grep hmonitor|/usr/bin/wc -l`
    if [ $Hm -ne 2 ];then
        $SSH $Phy_IP $YUM hmonitor hmonitor-resource-agent &> $NUL
    fi
    CM=`rpm -qa|grep net-snmp-5.5`
    if [ -z "$CM" ];then
        $YUM net-snmp &> $NUL
    fi
    Ga=`rpm -qa |grep ganglia`
    if [ -z "$Ga" ];then
        $YUM libconfuse libganglia ganglia-gmond &> $NUL
    fi
    for i in ${MF[@]};do
        RSYNC $Phy_IP:$i $i &> $NUL
        [ ! -e "$i" ] && echo "`$Date` $i transfer error!. Check $i on the HA master." >> $Mlog
    done
    LHM=`rpm -qa|grep hmonitor|/usr/bin/wc -l`
    if [ $LHM -ne 2 ];then
        $YUM hmonitor hmonitor-resource-agent &> $NUL
    fi
    SER_P=/etc/init.d
    $SER_P/snmpd restart &> $NUL
    $SER_P/hdp-gmond restart &> $NUL
    $SSH $Phy_IP $SER_P/cman start  &> $NUL
    $SSH $Phy_IP $SER_P/rgmanager start  &> $NUL
    $SSH $Phy_IP $SER_P/ricci start &> $NUL
    $SSH $Phy_IP $SER_P/modclusterd start &> $NUL
    $SSH $Phy_IP $SER_P/ambari-agent restart &> $NUL
    $SER_P/cman start &> $NUL
    $SER_P/rgmanager start &> $NUL
    $SER_P/ricci start &> $NUL
    $SER_P/modclusterd start &> $NUL
    $SER_P/ambari-agent restart &> $NUL
    HA_S[0]=snmpd
    HA_S[1]=ambari-agent
    HA_S[2]=hdp-gmond
    HA_S[3]=gmond
    CHK=/sbin/chkconfig
    for CK in ${HA_S[@]};do
        $SSH $Phy_IP $CHK --add $CK &> $NUL
        $SSH $Phy_IP $CHK $CK off  &> $NUL
        $CHK --add $CK &> $NUL
        $CHK $CK off  &> $NUL
    done
    echo -en "\033[32m `$Date` Install slave node OK. \033[0m\n" |TEE
}
 
AUTO_NIC(){
    Ip=`/sbin/ip link show eth1|grep "link/ether"|$AWK '{print $2}'`
    Udev="/etc/udev/rules.d/70-persistent-net.rules"
    Ifg=(`cat $Udev|$AWK -F\" '{print $8}'|grep -v "^$"`)
 
    for i in ${Ifg[@]};do
            if [ "$i" != "$Ip" ] ;then
                       /bin/sed -i "/$i/d" $Udev
            elif [ "$i" == "$Ip" ];then
                    /bin/sed -i "s@eth1@eth0@g" $Udev
            fi
    done
}
 
STORM_INSTALL(){
    HTNM=`/bin/hostname`
    NAD=`grep $HTNM $HF|$AWK '{print $1}'`
    if [[ $NAD != $SOM ]];then
        for I in ${SOMS[@]};do
            [[ "$I" == "$NAD" ]] && STAG=OK && break
        done
        if [[ $STAG != "OK" ]];then
            echo "`$Date` Error: Invalid node."|TEE && return
        fi
    fi
    if [[ "$action" = stop ]];then
        KID=(`ps aux|grep -v grep|grep storm|$AWK '{print $2}'`)
        for K in "${KID[@]}";do
            kill $K &> $NUL
        done
            exit 0
    fi
    TAR_GZ=`grep baseurl /etc/yum.repos.d/hdp-util.repo|grep local_dvd|$AWK -F= '{print $2}'`/other
    [ ! -f /tmp/storm.rgz ] && /usr/bin/wget "$TAR_GZ/storm.tgz" -O /tmp/storm.tgz &> $NUL
    if [[ ! -d /usr/lib/jzmq && ! -d /usr/lib/zeromq && ! -d /usr/lib/storm && ! -d /usr/lib/src_tar_gz ]];then
        if [ "$TAG" == master ];then
            echo -en "\033[32m `$Date` Storm master installing, please wait ...\033[0m\n"|TEE
        elif [ "$TAG" == slave ];then
            echo -en "\033[32m `$Date` Storm slave installing, please wait ...\033[0m\n"|TEE
        fi
        YUM_IP=`grep baseurl /etc/yum.repos.d/hdp-util.repo|$AWK -F\/ '{print $3}'|/usr/bin/uniq`
        SFILE=/var/www/html/local_dvd/other/storm.yaml
        #if [[ ${#SOMS[@]} -gt 2 ]];then
        #    for SS in ${SOMS[@]:2};do
        #        if ! $SSH $YUM_IP grep $SS $SFILE &>$NUL;then
        #            $SSH $YUM_IP "sed -i '/192.168.1.219/a\ \ \ \ \ -\ \"$SS\"' $SFILE"
        #        fi
        #    done
        #fi
        #$SSH $YUM_IP sed -i "s@$SDIR1/storm/workdir@$SPATH@g" $SFILE
        #$SSH $YUM_IP sed -i "s@192.168.1.166@$SOM@g" $SFILE
        #$SSH $YUM_IP sed -i "s@192.168.1.214@"${SOMS[0]}"@g" $SFILE
        #$SSH $YUM_IP sed -i "s@192.168.1.219@"${SOMS[1]}"@g" $SFILE
            #echo -en 'export JAVA_HOME=/usr/jdk/jdk1.6.0_31\nexport PATH=$JAVA_HOME/bin:$PATH' > /etc/profile.d/java.sh
            . /etc/profile.d/java.sh
        tar xf /tmp/storm.tgz -C /usr/lib/ &> $NUL
        cd /usr/lib/zeromq
        /usr/lib/zeromq/configure &> $NUL
            /usr/bin/make &> $NUL
            /usr/bin/make install &> $NUL
            cd /usr/lib/jzmq
            /usr/lib/jzmq/autogen.sh &> $NUL
            /usr/lib/jzmq/configure &> $NUL
            /usr/bin/make &> $NUL
            /usr/bin/make install &> $NUL
            rm -rf /usr/lib/storm/conf/storm.yaml
            /usr/bin/wget "$TAR_GZ/storm.yaml" -O /usr/lib/storm/conf/storm.yaml &> $NUL
    fi
    echo 'export PATH=$PATH:/usr/lib/storm/bin/' > /etc/profile.d/storm.sh
    . /etc/profile.d/storm.sh
    if [[ "$TAG" == master ]];then
        /usr/lib/storm/bin/storm nimbus >/dev/null 2>&1 &
        /usr/lib/storm/bin/storm ui >/dev/null 2>&1 &
        /usr/lib/storm/bin/storm supervisor >/dev/null 2>&1 &
        while : ;do
            sleep 1
            if netstat -tnlp|$AWK '{print $4}'|grep 8080 &> $NUL;then
                echo -en "\033[32m `$Date` Storm server install done. \n Web: http://`hostname -s`:8080 or http://`uname -n`:8080 or http://$Ip:8080 \033[0m\n"|TEE
                exit 0
            fi
            let EX++
            if [[ "$EX" -eq 30 ]];then
                echo "`$Date` Storm master start failed."|TEE
                exit 1
            fi
        done
    elif [[ "$TAG" == slave ]];then
        /usr/lib/storm/bin/storm supervisor >/dev/null 2>&1 &
        echo -en "\033[32m `$Date` Storm slave install done. \033[0m\n"|TEE
    fi
}
 
KICKSTART_INSTALL(){
    RESULT=`rpm -qa|grep -E "tftp-server|syslinux-tftpboot|dhcp"|/usr/bin/wc -l`
    [[ $RESULT -lt 4 ]] && $YUM tftp-server syslinux-tftpboot dhcp &> $NUL   
    /sbin/chkconfig dhcpd on
    H_lc=`/sbin/ifconfig $Ne|grep Bcast|$AWK '{print $2}'|$AWK -F: '{print $2}'`
    DHCPCONF=/etc/dhcp/dhcpd.conf
    $SYNC /var/www/html/ks/dhcpd.conf $DHCPCONF
    sed -i "s@202.96.209.5@$Ds1@g" $DHCPCONF
    sed -i "s@8.8.8.8@$Ds2@g" $DHCPCONF
    sed -i "s@hypers.com@$Epe@g" $DHCPCONF
    sed -i "s@255.255.255.0@$Nk@g" $DHCPCONF
    sed -i "s@\([[:space:]]option routers \).*;@\1$Gw;@g" $DHCPCONF
    sed -i "s@\([[:space:]]next-server \).*;@\1$H_lc;@g" $DHCPCONF
    sed -i "s@192.168.6.0@$SUBNET@g" $DHCPCONF
    sed -i "s@192.168.6.10@$RANGE_MIN@g" $DHCPCONF
    sed -i "s@192.168.6.200@$RANGE_MAX@g" $DHCPCONF
    $SYNC /var/www/html/ks/tftp /etc/xinetd.d/tftp
    $SYNC /var/www/html/ks/tftpboot/ /var/lib/tftpboot/   
    $SYNC /etc/hosts /var/www/html/local_dvd/other/
    $SYNC /etc/yum.repos.d/*.repo /var/www/html/local_dvd/other/
    $SYNC /etc/sysconfig/hdp.conf /var/www/html/local_dvd/other/
    chmod 644 /var/www/html/local_dvd/other/hdp.conf
    KS_LIST=(`ls /var/www/html/ks/*.cfg /var/lib/tftpboot/pxelinux.cfg/default`)
    for i in ${KS_LIST[@]};do
        sed -i "s@192.168.6.30@$H_lc@g" $i &> $NUL
    done
    /sbin/service xinetd restart &> $NUL
    /sbin/service dhcpd restart &> $NUL
    RESULT=`netstat -unlp|$AWK '{print $4}'|$AWK -F: '{print $2}'|grep -E "\<67\>|\<69\>"|/usr/bin/wc -l`
    [[ $RESULT -ne 2 ]] && echo -en "\033[32m `$Date` Error: dhcp or tftp start failed. \033[0m\n"|TEE || echo -en "\033[32m `$Date` Kickstart: dhcp and tftp started. \033[0m\n"|TEE
}
 
USE_DISK(){
    echo "`$Date` Format and mount all disk, Plesae wait."|TEE
    A_cmd=(`grep $Epe $HF|$AWK '{print $1}'`)
    for S in ${A_cmd[@]};do
        $SSH $S "/bin/hhdp -s" &
    done
    sleep 10
    for C in ${A_cmd[@]};do   
        while :;do
            CRS=`$SSH $C "ps aux|grep -v grep|grep mkfs.ext4|/usr/bin/wc -l"`
            sleep 1
            CRS=`$SSH $C "ps aux|grep -v grep|grep mkfs.ext4|/usr/bin/wc -l"`
            [ "$CRS" -eq 0 ] && echo "`$Date` Disk: $C OK"|TEE && break
            sleep 2
        done
    done
}
 
SETUP_ABI(){
    while :;do
        echo "Now, Setup ambari-server.(yes[local install.]/quit[Quit,login other node,run cmd -> hhdp -a])"
        read -p "yes/quit: " ABI
        [[ "$ABI" == Y || "$ABI" == yes ]] && break
        [[ "$ABI" == Q || "$ABI" == quit ]] && return
    done
    AMBARI_INSTALL
}
 
Cluster_sync(){
    H_lc=`/sbin/ifconfig $Ne|grep Bcast|$AWK '{print $2}'|$AWK -F: '{print $2}'`
    Gme=`uname -n`
    A_cmd=(`grep $Epe $HF|grep -vE "$Gme|$H_lc"|$AWK '{print $1}'`)
    Cf=/var/spool/cron/root
    echo "*/5    *    *    *    *    /usr/bin/rdate -s $T_Server &>$NUL && /sbin/hwclock -w " > $Cf
    SSf[0]=$HF
    SSf[1]=$Cf
    REPO_F=(`ls /etc/yum.repos.d/*.repo`)
    Sf=(${SSf[@]} ${REPO_F[@]})
    for s in ${Sf[@]};do
        for f in ${A_cmd[@]};do
            while :;do
                ping -c 1 -W 1 $f &> $NUL
                RES=$?
                if [ "$RES" -ne 0 ];then
                    echo "Please check network -> $f ,(yes[Check OK after]/ignore[Ignore node])."
                    read -p "yes/ignore: " AA
                    [[ "$AA" == "ignore" || "$AA" == "I" ]] && break
                fi
                RSYNC $s $f:$s &> $NUL
                MD5_L=`$MD5 $s|$AWK '{print $1}'`
                MD5_R=`$SSH $f $MD5 $s|$AWK '{print $1}'`
                if [[ "$MD5_L" == "$MD5_R" ]] ;then
                     echo "`$Date` : $f File sync OK."|TEE
                    break
                fi
            done
        done
    done
    if [[ "$TAG" != "-k" || "$TAG" != "asdf" ]] ;then
        HDP_CONF
        USE_DISK
        SETUP_ABI
    fi
}
 
 
USE_STORM(){
    while :;do
        if $PING $SOM &>$NUL && $PING ${SOMS[0]} &>$NUL && $PING ${SOMS[1]} &>$NUL;then
            break
        else
            echo "Please network -> $SOM ${SOMS[@]} <-, (yes[Check OK]/quit[Quit,Quit install storm])."
            read -p "yes/quit : " VSM
            [[ "$VSM" ==  quit ]] && return
        fi
    done
    $SSH $SOM "/bin/hhdp --storm-master" &
    $SSH ${SOMS[0]} "/bin/hhdp --storm-slave" &
    $SSH ${SOMS[1]} "/bin/hhdp --storm-slave" &
    if [[ ${#SOMS[@]} -gt 2 ]];then
        for SS in ${SOMS[@]:2};do
            $SSH $SS "/bin/hhdp --storm-slave" &
        done
    fi
}
 
LHOSTNAME(){
    /bin/hostname $Hn
    echo -en "NETWORKING=yes\nHOSTNAME=$Hn" > $Hnc
    echo -en "DEVICE=$Ne\nONBOOT=yes\nTYPE=Ethernet\nBOOTPROTO=$Bp\nNM_CONTROLLED=no\nIPADDR=$Ip\nNETMASK=$Nk\nGATEWAY=$Gw\nDNS1=$Ds1\nDNS2=$Ds2" > $Dec
    /sbin/service network restart &> $NUL
    echo -en "\nHostname:\t`uname -n`\nNic:\t\t"$Ne"\nIP:\t\t`/sbin/ifconfig $Ne|grep Bcast|$AWK '{print $2}'|$CUT -d: -f2`\n\n"
}
 
if [[ "$1" == "-i" && -z "$2" ]];then
    LHOSTNAME
elif [[ "$1" == "-M" ]];then
    D_FILE="$2"
    FILE_ARY=($@)
    MD5_CHECK
elif [[ "$1" == "-c" || "$1" == "-cl" ]];then
    TAG=$1
    F_cmd=`echo $*|sed "s@^$TAG\(.*\)@\1@g"`
    Func_cmd
elif [[ "$1" == "-f" && -n "$2" && -z "$4" ]];then
    L_file=$2
    D_file=${3:-$2}
    C_fe
elif [[ "$1" == "-s" && -z "$2" ]];then
    if [[ -b /dev/cciss/c0d0 ]];then
        Ah=hp
        Dph=/dev/cciss/
        Exist=(`ls /dev/cciss/|grep "^\<c0d[0-9][0-9]\{0,1\}\>"`)
        Check_disk
    else
        Exist=(`ls /dev/|grep -E "^\<sd[a-z]{0,1}\>|^\<sd[a-z]{0,1}1\>|^\<hd[a-z]{0,1}\>|^\<vd[a-z]{0,1}\>"`)
        Dph=/dev/
        Check_disk
    fi
#elif [[ "$1" == "-m" && -z "$2" ]];then
#    echo -en "\033[32m `$Date` Initialization is cluster system environment, please wait ...\033[0m\n"|TEE
#    [[ -n "$SUBNET" && -n "$RANGE_MAX" && -n "$RANGE_MIN" ]] && TAG=-k
#    LHOSTNAME
#    TIME_NOW_CHECK
#    WEB_TIME_CHECK
#    if [[ "$TAG" == "-k" ]];then
#        echo -en "\033[32m `$Date` Kickstart Installing, Please wait ...\033[0m\n"|TEE
#        KICKSTART_INSTALL
#    fi
#elif [[ "$1" == "-a" && -z "$2" ]];then
#    AMBARI_INSTALL
elif [[ "$1" == "-n" && -z "$2" ]];then
    HOSTS
#elif [[ "$1" == "--remove" && -z "$2" ]];then
#    RM
#elif [[ "$1" == "--auto-nic" && -z "$2" ]];then
#    AUTO_NIC
#elif [[ "$1" == "-C" && -z "$3" ]];then
#    [[ "$2" == "-d" ]] && TAG=DNS
#    HDP_CONF
#elif [[ "$1" == "-r" && -z "$2" ]];then
#    [ -z "$2" ] && TAG=asdf
#    Cluster_sync
elif [[ "$1" == "-e" && -n "$2" && -z "$3" ]];then
    Fph=$2
    if [ -b $Fph ];then
        Mmu
    else
        echo "\$2 --> $2 invaild path!" >> $Mlog
    fi
else
    Help
fi
