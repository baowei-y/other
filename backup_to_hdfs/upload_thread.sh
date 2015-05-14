#!/bin/bash


[ -x /bin/basename ] && bn_cmd=/bin/basename
[ -x /usr/bin/basename ] && bn_cmd=/usr/bin/basename
[ -x /usr/bin/dirname ] && dn_cmd=/usr/bin/dirname
[ -x /usr/bin/wc ] && wc_cmd=/usr/bin/wc
[ -x /usr/bin/uniq ] && uq_cmd=/usr/bin/uniq
[ -x /usr/bin/hdfs ] && hdp_cmd="/usr/bin/hdfs dfs"

log_date="/bin/date +%H:%M:%S/%Y-%m-%d"
log_dir=/var/log/backup_to_hdfs

log_file=$log_dir/upload_hdfs.log
put_retry_list=${2:-$log_dir/retry_put.list}
put_black_list=${3:-$log_dir/put_black.list}
timestamp="/bin/date +%s"
now_timestamp=`$timestamp`

[ ! -d $log_dir ] && mkdir -p $log_dir
# 日志记录函数
TEE(){
  /usr/bin/tee -a $log_file
}

# 本地和hdfs的文件大小对比函数
# 此函数需要两个参数 $1 $2
# $1为本地文件大小 $2为hdfs文件路径
HDFS_SIZE_CHECK(){
  if [[ $# -ne 2 ]];then
    echo "`$log_date` $FUNCNAME Error \$#!=2 \$1 or \$2 is empty"|TEE
    return 1
  fi
  local hdfs_size=`$hdp_cmd -du $2|awk '{print $1}'`
  [[ $1 -eq $hdfs_size ]] && return 0 || return 1
}

# 此函数需要三个参数
# $1 : hdfs的文件名
# $2 : 本地的对应文件的大小
# $3 : hdfs文件的目录
HDFS_LOCATION_CHECK(){
  if [[ $# -ne 3 ]];then
    return 2
  fi
  if $hdp_cmd -test -d $3 ;then
    if $hdp_cmd -test -f $1 ;then
       if HDFS_SIZE_CHECK $2 $1 ;then
         $hdp_cmd -rm -r -f -skipTrash $1.tmp
         return 1 
       else
         $hdp_cmd -rm -r -f -skipTrash $1
       fi
    fi
    if $hdp_cmd -test -f $1.tmp ;then
      if HDFS_SIZE_CHECK $2 $1.tmp ;then
        $hdp_cmd -mv $1.tmp $1
        return 1
      else
        $hdp_cmd -rm -r -f -skipTrash $1.tmp
        return 0
      fi
    else
      return 0
    fi
  else
    if $hdp_cmd -mkdir -p $3 ;then
      $hdp_cmd -chmod 777 $3 && return 0 || return 4
    else
      return 3
    fi
  fi
}

# 此函数仅作上传处理，此函数需要五个参数
# $1 需要上传的本地文件
# $2 要上传到hdfs的目标文件
# $3 本地文件的大小byte
# $4 分配的超时时间 
# $5 本地文件的du -sh的统计大小
# $6 是否删除文件关键字
ONLY_UPLOAD(){
  if [[ ! -f $1 ]];then
    echo "`$log_date` $FUNCNAME Error: \$1=$1 no such file"|TEE
    return 1
  fi
  $hdp_cmd -put -f $1 $2.tmp &> /dev/null
  if HDFS_SIZE_CHECK $3 $2.tmp ;then
    $hdp_cmd -mv $2.tmp $2 &> /dev/null
    local nowtime=`$timestamp` ; local costtime=`/usr/bin/expr $nowtime - $now_timestamp`
    echo "`$log_date` $FUNCNAME $2 Upload Success $5 $costtime $4" >> $log_file
    echo "$1 $3" >> $put_black_list
    [[ $6 == "delete" ]] && rm -rf $1
    return 0
  else
    $hdp_cmd -rm -r -f -skipTrash $2.tmp &> /dev/null
    return 1
  fi
}

helpDoc(){
  echo "Usage: $0 [thread_file] [retry_list_file] [black_list_file]"
  echo "  [thread_file]: /[thread/path/and/str]_[num]_[timestamp]_[filesize(bit)]_[timeout(sec)]"
  echo "Exam: $0 /var/log/backup_to_hdfs/threadfile_1_1431587477_361655_100 /var/log/backup_to_hdfs/put_retry.list /var/log/backup_to_hdfs/put_black.list"
  exit 0
}

argCheck(){
  if [[ $# -ne 3 || ! -f $1 ]];then
    helpDoc
  fi
}

# 上传HDFS
PUT_TO_HDFS(){
  if [[ ! -f $1 ]];then
    echo "`$log_date` $FUNCNAME Error: \$1 Invalid File"|TEE
    return 1
  fi

  local list_sum=`cat $1|$wc_cmd -l`
  if [[ $list_sum -ne 2 ]];then
    echo "`$log_date` $FUNCNAME  $1 is invalid pidfile"|TEE
    return 2
  fi

  local file_content=`sed -n "1p" $1`
  local local_file=`echo $file_content|awk '{print $1}'`
  local hdfs_file=`echo $file_content $1|awk '{print $2}'`
  local local_size=`$bn_cmd $1|awk -F_ '{print $4}'`
  local hdfs_dir=`/usr/bin/dirname $hdfs_file`
  local valid_time=`$bn_cmd $1|awk -F_ '{print $NF}'`
  local filesize=`/usr/bin/du -sh $local_file|awk '{print $1}'`

  HDFS_LOCATION_CHECK $hdfs_file $local_size $hdfs_dir ; local hlc_rev=$?
  local nowtime=`$timestamp`
  local costtime=`/usr/bin/expr $nowtime - $now_timestamp`
  case $hlc_rev in
    0)
      ONLY_UPLOAD $local_file $hdfs_file $local_size $valid_time $filesize
      if [[ $? -ne 0 ]] ;then
        echo "$file_content" >> $put_retry_list
        local nowtime=`$timestamp` ; local costtime=`/usr/bin/expr $nowtime - $now_timestamp`
        echo "`$log_date` ONLY_UPLOAD Upload Failed $filesize $costtime $valid_time" >> $log_file
      fi
      ;;
    1)
      echo "$local_file $local_size" >> $put_black_list
      echo "`$log_date` $FUNCNAME $hdfs_file Upload Success $filesize $costtime $valid_time (check size)" >> $log_file ;;
    2)
      echo "$file_content" >> $put_retry_list
      echo "`$log_date` HDFS_LOCATION_CHECK Upload Failed: \$# != 2 $filesize $costtime $valid_time" >> $log_file ;;
    3)
      echo "$file_content" >> $put_retry_list
      echo "`$log_date` HDFS_LOCATION_CHECK Upload Failed: Can't create directory -> $hdfs_dir $filesize $costtime $valid_time" >> $log_file ;;
    4)
      echo "$file_content" >> $put_retry_list
      echo "`$log_date` HDFS_LOCATION_CHECK Upload Failed: Can't chmod 777 $hdfs_dir on the hdfs $filesize $costtime $valid_time" >> $log_file ;;
  esac
  rm -rf $1
}

argCheck $1 $2 $3

echo $$ >> $1
PUT_TO_HDFS $1
