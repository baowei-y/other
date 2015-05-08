#!/bin/bash

[ -x /bin/basename ] && bn_cmd=/bin/basename
[ -x /usr/bin/basename ] && bn_cmd=/usr/bin/basename
[ -x /usr/bin/dirname ] && dn_cmd=/usr/bin/dirname
[ -x /usr/bin/wc ] && wc_cmd=/usr/bin/wc
[ -x /usr/bin/uniq ] && uq_cmd=/usr/bin/uniq
[ -x /usr/bin/hdfs ] && hdp_cmd="/usr/bin/hdfs dfs"

# 检查是否有本脚本pid
pid_file=/tmp/`$bn_cmd $0`_ftp_op.pid
if [[ -f $pid_file ]];then
 ps -p `cat $pid_file` &> /dev/null
 [[ "$?" -eq "0" ]] && echo "`$log_date` : $0 exist." && exit 0
fi
echo $$ > $pid_file 

log_date="/bin/date +%H:%M:%S/%Y-%m-%d"
log_dir=/var/log/backup_to_hdfs
log_file=$log_dir/crtl.log

threads=${1:-10}
thread_script=${2:-/opt/upload_thread.sh}
check_period=5
timestamp="/bin/date +%s"
thread_file_pre=$log_dir/threadfile
max_threads=32
# 5242880 = 5M/s
network_speed=5242880
net_speed=`echo $network_speed $threads|awk '{printf("%.0lf",$1/$2)}'`

if [[ ! -d $log_dir ]];then
  mkdir -p $log_dir ; mkdir_res=$?
  [[ $mkdir_res -ne 0 ]] && echo "$log_dir : Can't create directory" && exit 1
fi

put_invalid_list=$log_dir/put_hdfs_invalid.list
put_hdfs_list=$log_dir/put_hdfs.list
put_retry_list=$log_dir/put_retry.list
put_black_list=$log_dir/put_black.list

final_dir=${3:-/opt/localfiles}
hdfs_dir=${4:-/logs_backup}
retention_day=${5:-10}
del_str=${6:-hdfs-ok}

# 日志记录函数
TEE(){
  /usr/bin/tee -a $log_file
}

# 文件删除策略; 此函数需要提供三个参数
# $1 : 文件有效路径
# $2 : 删除文件关键字，可以通过 # echo filename|awk -F_ '{print $(NF-1)}' 则有效
# $3 : 文件保留天数
DEL_FUC(){
  if [[ $# -ne 3 ]];then 
    echo "`$log_date` $FUNCNAME Error: \$# != 2" >> $log_file
    return 1 
  fi
  if [[ ! -f $1 ]];then
    #echo "`$log_date` $FUNCNAME $1 No such file" >> $log_file
    return 2 
  fi
  if [[ -z $2 ]];then
    echo "`$log_date` $FUNCNAME $2 Invalid String" >> $log_file
    return 3 
  fi
  local str=`echo $1|awk -F_ '{print $(NF-1)}'`
  if [[ "$str" == "$2" ]];then
    local oldtime=`echo $1|awk -F_ '{print $NF}'`
    local nowtime=`$timestamp`
    local periodtime=`echo $oldtime $3|awk '{print $1+$2*86400}'`
    if [[ $periodtime -lt $nowtime ]];then
      rm -rf $1
      echo "`$log_date` $FUNCNAME $1 Deleted" >> $log_file
    fi 
  else
#    echo "`$log_date` $FUNCNAME $2 Invalid File" >> $log_file
    return 0
  fi
}

# 重试列表追加入当前列表
# 如果检测到重试列表不为空，追加进上传列表
# 此函需要两个参数 $1 $2
# $1 : 重试列表文件
# $2 : 标准处理列表
RETRY_LIST(){
  if [ -f $1 ];then
    retry_sum=`cat $1|/usr/bin/wc -l`
    if [[ $retry_sum -ne 0 ]];then
      cat $1 >> $2
      rm -rf $1
    fi
  fi
}

# 线程个数策略，此函数需要提供两个参数
# $1 : 原始上传列表文件
# $2 : 用户提供的线程个数
THREAD_POLICY(){
  if [[ $# -ne 2 ]];then 
    echo "`$log_date` $FUNCNAME Error: \$# 1= 2" >> $log_file
    return 1 
  fi
  if [[ ! -f $1 ]];then
    echo "`$log_date` $FUNCNAME $1 No such file" >> $log_file
    return 2 
  fi
  echo "$2"|grep -q '^[-]\?[0-9]\+$'
  if [[ $? -ne 0 ]];then
    echo "`$log_date` $FUNCNAME $2 Invalid number" >> $log_file 
    return 3 
  fi
  local list_sum=`cat $1|$wc_cmd -l`
  if [[ $list_sum -eq 0 ]];then
    #echo "`$log_date` $FUNCNAME $1 is empty" >> $log_file
    return 0
  else
    if [[ $2 -ge $max_threads ]];then
      [[ "$list_sum" -le "$max_threads" ]] && echo $list_sum || echo $max_threads
    else
      [[ "$list_sum" -le "$2" ]] && echo $list_sum || echo $2
    fi
  fi
}

# 超时失败处理，此函数需要提供一个参数
# $1 : 超时线程的pid标识文件
TIMEOUT_HANDLE(){
  if [[ ! -f $1 ]];then
    echo "`$log_date` $FUNCNAME $1 no such file" >> $log_file 
    return 1 
  fi
  local old_pid=`/usr/bin/tail -1 $1`
  ps -p $old_pid &> /dev/null
  if [[ $? -eq 0 ]];then 
    kill $old_pid &> /dev/null
    if [[ $? -eq 0 ]];then
      sed -n "1p" $1 >> $put_retry_list
      rm -rf $1
      return 0
    else
      echo "`$log_date` $FUNCNAME $2 kill $old_pid fail." >> $log_file
      local file_dir=`$dn_cmd $1`  ; local file_name=`$bn_cmd $1`
      sed -n "1p" $1 >> $put_retry_list
      mv -f $1 $file_dir/fail_kill_$file_name
      ps -p $old_pid &> /dev/null
      if [[ $? -eq 0 ]];then
        echo "`$log_date` $FUNCNAME $2 kill $old_pid fail." >> $log_file 
        return 1
      else
        return 0
      fi
    fi
  else
    sed -n "1p" $1 >> $put_retry_list
    rm -rf $1
  fi
# $put_hdfs_list $put_retry_list $threads
}

# 创建线程执行脚本所需文件,此函数需要两个参数
# $1 : 线程执行脚本id号
# $2 : 要处理的具体文件的绝对路径 
CREATE_THREAD_FILE(){
  if [[ $# -ne 2 ]];then
    echo "`$log_date` $FUNCNAME Error \$#!=2" >> $log_file
    return 1 
  fi
  if [[ -z $1 ]];then
    echo "`$log_date` $FUNCNAME $1 is empty" >> $log_file
    return 0 
  fi
  if [[ ! -f $2 ]];then
    echo "`$log_date` $FUNCNAME $2 no such file" >> $log_file 
    return 2 
  fi
  local file_size=`/usr/bin/du -b $2|awk '{print $1}'`
  local time_out=`echo $file_size $net_speed|awk '{printf("%.0lf",$1/$2+100)}'`
  local thread_file="$thread_file_pre"_"$1"_`$timestamp`_"$file_size"_"$time_out"
  echo $2 > $thread_file
  if [[ $? -eq 0 ]];then
    echo $thread_file 
    return 0
  else
    echo "`$log_date` $FUNCNAME $thread_file Can't create file" >> $log_file
    return 3 
  fi
}

# 超时策略,此函数需要提供两个参数
# $1 : 当前需要创建的线程个数id
# $2 : 要处理文件的绝对路径
THREAD_FILE_POLICY(){
  if [[ $# -ne 2 ]];then
    echo "`$log_date` $FUNCNAME Error \$#!=2" >> $log_file
    return 1 
  fi
  if [[ -z $1 ]];then
    echo "`$log_date` $FUNCNAME $1 is empty" >> $log_file
    return 0 
  fi
  if [[ ! -f $2 ]];then
    echo "`$log_date` $FUNCNAME $2 no such file" >> $log_file 
    return 2 
  fi
  local old_file=`/bin/ls "$thread_file_pre"_"$1"_* 2> /dev/null`
  if [[ -f $old_file ]];then
    local now_time=`$timestamp`
    local old_time=`$bn_cmd $old_file|awk -F_ '{print $3}'`
    local file_timeout=`$bn_cmd $old_file|awk -F_ '{print $NF}'`
    local now_timeout=`echo $now_time $old_time|awk '{printf("%.0lf",$1-$2)}'`
    if [[ $now_timeout -le $file_timeout ]];then
      return 0 
    else
      if TIMEOUT_HANDLE $old_file ;then
        echo `CREATE_THREAD_FILE $1 $2`
      fi
    fi 
  else
    echo `CREATE_THREAD_FILE $1 $2`
  fi
}

# 删除周期控制，多久执行一次删除操作
# 此函可接受两个参数
# $1 ：周期时间，单位小时，例如 24  (参数为空时走默认值 24)
# $2 : 删除标识文件，用于存放上次上次处理的时间戳，便于计算
PERIOD_CHECK(){
  local period_time=${1:-24}
  local del_tag_file=${2:-/tmp/ftp_tag_to_delete}
  [[ ! -f $del_tag_file ]] && echo `$timestamp` > $del_tag_file
  local old_time=`cat $del_tag_file`
  local now_time=`$timestamp` 
  local valid_lease=`echo "$period_time $old_time"|awk '{print $1*60*60+$2}'`
  if [[ $valid_lease -lt $now_time ]];then
    echo $now_time > $del_tag_file
    return 0
  else
    return 1
  fi
}

# 找出某个目录下匹配指定策略的文件追加入文件列表
# 
HDFS_LIST_CHECK(){
  [[ ! -d $1 ]] && return 1
  [[ -z $2 ]] && return 2
  [[ $# -ne 2 ]] && return 3
  for f in `/bin/find $1 -type f -a ! -name "*_hdfs-ok_*"`;do
    [[ -f $f ]] && echo $f >> $2
  done
}

# 主控进程函数
MASTER_CTRL(){
  if [[ $# -ne 5 ]];then
    echo "`$log_date` $FUNCNAME Error \$#!=4" >> $log_file
    return 1 
  fi
     
  while :;do
    RETRY_LIST $2 $1
    local final_threads=`THREAD_POLICY $1 $4`
    [[ -z $final_threads ]] && break
    for t in `/usr/bin/seq 1 $final_threads`;do
      local file_path=`sed -n "1p" $1`
      echo $file_path|grep -q $final_dir
      if [[ $? -ne 0 ]];then
        echo "`$log_date` $FUNCNAME $file_path invalid file" >> $log_file
        echo $file_path >> $put_invalid_list 
        sed -i "1d" $1
        continue
      fi
      local thread_file=`THREAD_FILE_POLICY $t $file_path`
      if [[ -f $thread_file ]];then
        /bin/bash $3 $thread_file $final_dir $hdfs_dir $2 $5 &
        sed -i "1d" $1
      else
        ls "$file_path"_"$5"_* &> /dev/null ; local rev=$?
        if [[ $rev -eq 0 ]];then
          sed -i "1d" $1
        else
          echo "$file_path" >> $2
          sed -i "1d" $1
        fi
      fi
    done
    [[ ! -z $final_threads ]] && sleep $check_period 
  done
  rm -rf $pid_file
}

MASTER_CTRL $put_hdfs_list $put_retry_list $thread_script $threads $put_black_list 
