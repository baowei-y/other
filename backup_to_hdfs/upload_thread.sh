#!/bin/bash

[[ ! -f $1 ]] && echo "Error, Invalid File" && exit 1
[[ ! -d $2 ]] && echo "Error, Invalid Directory" && exit 1
echo $$ >> $1

[ -x /bin/basename ] && bn_cmd=/bin/basename
[ -x /usr/bin/basename ] && bn_cmd=/usr/bin/basename
[ -x /usr/bin/dirname ] && dn_cmd=/usr/bin/dirname
[ -x /usr/bin/wc ] && wc_cmd=/usr/bin/wc
[ -x /usr/bin/uniq ] && uq_cmd=/usr/bin/uniq
[ -x /usr/bin/hdfs ] && hdp_cmd="/usr/bin/hdfs dfs"

log_date="/bin/date +%H:%M:%S/%Y-%m-%d"
log_dir=/var/log/backup_to_hdfs
log_file=$log_dir/put.log
put_retry_list=${5:-$log_dir/retry_put.list}
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
  if [[ $# -ne 6 ]];then
    echo "`$log_date` $FUNCNAME Error: \$# != 5"|TEE
    return 1
  fi
  if [[ ! -f $1 ]];then
    echo "`$log_date` $FUNCNAME Error: \$1=$1 no such file"|TEE
    return 1
  fi
  $hdp_cmd -put -f $1 $2.tmp &> /dev/null
  if HDFS_SIZE_CHECK $3 $2.tmp ;then
    $hdp_cmd -mv $2.tmp $2 &> /dev/null
    local nowtime=`$timestamp` ; local costtime=`/usr/bin/expr $nowtime - $now_timestamp`
    echo "`$log_date` $FUNCNAME $2 Upload Success $5 $costtime $4" >> $log_file
    [[ $6 == "delete" ]] && rm -rf $1
    return 0
  else
    $hdp_cmd -rm -r -f -skipTrash $2.tmp &> /dev/null
    return 1
  fi
}

# 上传HDFS
PUT_TO_HDFS(){
  if [[ $# -ne 3 ]];then
    echo "`$log_date` $FUNCNAME Error: \$# 1= 3"|TEE
    return 1
  elif [[ ! -f $1 ]];then
    echo "`$log_date` $FUNCNAME Error: \$1 Invalid File"|TEE
    return 1
  elif [[ ! -d $2 ]];then
    echo "`$log_date` $FUNCNAME Error: \$2 Invalid Directory"|TEE
    return 1
  elif [[ -z $3 ]];then
    echo "`$log_date` $FUNCNAME Error: \$3 is Empty"|TEE
    return 1
  fi

  local list_sum=`cat $1|$wc_cmd -l`
  if [[ $list_sum -ne 2 ]];then
    echo "`$log_date` $FUNCNAME  $1 is invalid pidfile"|TEE
    return 2
  fi

  local local_file=`sed -n "1p" $1|awk '{print $1}'`
  local file_str=`sed -n "1p" $1|awk '{print $2}'`
  local file_str=${file_str:-nnnnnno}
  local local_size=`$bn_cmd $1|awk -F_ '{print $4}'`
  local hdfs_file=`echo $local_file|sed "s@$2@$3@1"`
  local hdfs_dir=`/usr/bin/dirname $hdfs_file`

  local valid_time=`$bn_cmd $1|awk -F_ '{print $NF}'`
  local filesize=`/usr/bin/du -sh $local_file|awk '{print $1}'`

  HDFS_LOCATION_CHECK $hdfs_file $local_size $hdfs_dir ; hlc_rev=$?
  local nowtime=`$timestamp`
  local costtime=`/usr/bin/expr $nowtime - $now_timestamp`
  case $hlc_rev in
    0)
      ONLY_UPLOAD $local_file $hdfs_file $local_size $valid_time $filesize
      if [[ $? -ne 0 ]] ;then
        sed -n "1p" $1 >> $put_retry_list
        local nowtime=`$timestamp` ; local costtime=`/usr/bin/expr $nowtime - $now_timestamp`
        echo "`$log_date` ONLY_UPLOAD Upload Failed $filesize $costtime $valid_time" >> $log_file
      fi
      ;;
    1)
      [[ $file_str == "delete" ]] && rm -rf $local_file 
      echo "`$log_date` $FUNCNAME $hdfs_file Upload Success $filesize $costtime $valid_time (check size)" >> $log_file ;;
    2)
      sed -n "1p" $1 >> $put_retry_list
      echo "`$log_date` HDFS_LOCATION_CHECK Upload Failed: \$# != 2 $filesize $costtime $valid_time" >> $log_file ;;
    3)
      sed -n "1p" $1 >> $put_retry_list
      echo "`$log_date` HDFS_LOCATION_CHECK Upload Failed: Can't create directory -> $hdfs_dir $filesize $costtime $valid_time" >> $log_file ;;
    4)
      sed -n "1p" $1 >> $put_retry_list
      echo "`$log_date` HDFS_LOCATION_CHECK Upload Failed: Can't chmod 777 $hdfs_dir on the hdfs $filesize $costtime $valid_time" >> $log_file ;;
  esac
  rm -rf $1
}

PUT_TO_HDFS $1 $2 $3
