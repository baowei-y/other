#!/bin/bash

[ -x /bin/basename ] && bn_cmd=/bin/basename
[ -x /usr/bin/basename ] && bn_cmd=/usr/bin/basename
[ -x /usr/bin/dirname ] && dn_cmd=/usr/bin/dirname
[ -x /usr/bin/wc ] && wc_cmd=/usr/bin/wc
[ -x /usr/bin/uniq ] && uq_cmd=/usr/bin/uniq
[ -x /usr/bin/hdfs ] && hdp_cmd="/usr/bin/hdfs dfs"

put_hdfs_py="/opt/backup_to_hdfs/http_put.py"

log_date="/bin/date +%H:%M:%S/%Y-%m-%d"
log_dir=/var/log/backup_to_hdfs

log_file=$log_dir/upload_hdfs.log
put_retry_list=${2:-$log_dir/retry_put.list}
put_black_list=${3:-$log_dir/put_black.list}
timestamp="/bin/date +%s"
now_timestamp=`$timestamp`

op_user=root
curl_cmd="/usr/bin/curl"
tail_cmd="/usr/bin/tail"
nn[0]="hdp1.bw-y.com"
nn[1]="hdp3.bw-y.com"

fetchStatus(){
  [[ -z $1 ]] && return 1
  local nn_page="http://$1:50070/dfshealth.jsp"
  local status=$($curl_cmd -s $nn_page --connect-timeout 3|grep "$1:8020"|/usr/bin/tail -1|awk -F\( '{print $2}'|awk -F\) '{print $1}')
  echo "$1 $status"
}

activeNn(){
  for n in ${nn[@]};do
    local now_result=$(fetchStatus $n)
    [[ -z $now_result ]] && exit 1
    local nn_name=$(echo $now_result|awk '{print $1}')
    local nn_status=$(echo $now_result|awk '{print $2}')
    if [[ $nn_status == "active" ]];then
      echo $nn_name
    fi
  done
}

now_nn=$(activeNn)


[ ! -d $log_dir ] && mkdir -p $log_dir
# 日志记录函数
TEE(){
  /usr/bin/tee -a $log_file
}

# 本地和hdfs的文件大小对比函数
# 此函数需要两个参数 $1 $2
# $1为本地文件大小 $2为hdfs文件路径
hdfs_size_check(){
  if [[ $# -ne 2 ]];then
    echo "`$log_date` $FUNCNAME Error \$#!=2 \$1 or \$2 is empty"|TEE
    return 1
  fi
  local page_path="http://$now_nn:50070/webhdfs/v1$2?op=GETFILESTATUS&user.name=$op_user"
  local hdfs_size=$($curl_cmd -s -i "$page_path"|$tail_cmd -1|awk -F: '{print $8}'|awk -F, '{print $1}')
  #local hdfs_size=`$hdp_cmd -du $2|awk '{print $1}'`
  [[ $1 -eq $hdfs_size ]] && return 0 || return 1
}


hdfs_path_check(){
  local page_path="http://$now_nn:50070/webhdfs/v1$1?op=GETFILESTATUS&user.name=$op_user" 
  $curl_cmd -s -i "$page_path"|$tail_cmd -1|grep -q "FileNotFoundException" && return 1 || return 0
}

hdfs_rm_file(){
  local page_path="http://$now_nn:50070/webhdfs/v1$1?op=DELETE&recursive=true&user.name=$op_user"
  $curl_cmd -s -i -X DELETE "$page_path" &> /dev/null
}

hdfs_rename_file(){
  local page_path="http://$now_nn:50070/webhdfs/v1$1?op=RENAME&destination=$2&user.name=$op_user"
  $curl_cmd -s -i -X PUT "$page_path" &> /dev/null
}

hdfs_mkdir(){
  local page_path="http://$now_nn:50070/webhdfs/v1$1?op=MKDIRS&permission=777&user.name=$op_user"
  $curl_cmd -s -i -X PUT "$page_path" &> /dev/null
  hdfs_path_check $1 && return 0 || return 1
}

hdfs_create(){
  local page_path="http://$now_nn:50070/webhdfs/v1$2?op=CREATE&overwrite=true&permission=777&user.name=$op_user"
  local put_path=$($curl_cmd -s -i -X PUT "$page_path"|grep '^Location: http'|awk '{print $NF}')
  #$curl_cmd -s -i -X PUT -T $1 "$put_path"
  $put_hdfs_py "$put_path" $1 &> /dev/null
}
# 此函数需要三个参数
# $1 : hdfs的文件名
# $2 : 本地的对应文件的大小
# $3 : hdfs文件的目录
hdfs_location_check(){
  if [[ $# -ne 3 ]];then
    return 2
  fi
  if hdfs_path_check $3 ;then
    if hdfs_path_check $1 ;then
       if hdfs_size_check $2 $1 ;then
         hdfs_rm_file $1.tmp
         return 1 
       else
         hdfs_rm_file $1
       fi
    fi
    if hdfs_path_check $1.tmp ;then
      if hdfs_size_check $2 $1.tmp ;then
        hdfs_rename_file $1.tmp $1
        return 1
      else
        hdfs_rm_file $1.tmp
        return 0
      fi
    else
      return 0
    fi
  else
    hdfs_mkdir $3 && return 0 || return 3
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
#  $hdp_cmd -put -f $1 $2.tmp &> /dev/null
  hdfs_create $1 $2.tmp
  if hdfs_size_check $3 $2.tmp ;then
    hdfs_rename_file $2.tmp $2 &> /dev/null
    local nowtime=`$timestamp` ; local costtime=`/usr/bin/expr $nowtime - $now_timestamp`
    echo "`$log_date` $FUNCNAME $2 Upload Success $5 $costtime $4" >> $log_file
    echo "$1 $3" >> $put_black_list
    [[ $6 == "delete" ]] && rm -rf $1
    return 0
  else
    hdfs_rm_file $2.tmp &> /dev/null
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

  hdfs_location_check $hdfs_file $local_size $hdfs_dir ; local hlc_rev=$?
  local nowtime=`$timestamp`
  local costtime=`/usr/bin/expr $nowtime - $now_timestamp`
  case $hlc_rev in
    0)
      ONLY_UPLOAD $local_file $hdfs_file $local_size $valid_time $filesize
      if [[ $? -ne 0 ]] ;then
        echo "$file_content" >> $put_retry_list
        local nowtime=`$timestamp` ; local costtime=`/usr/bin/expr $nowtime - $now_timestamp`
        echo "`$log_date` ONLY_UPLOAD Upload Failed $local_file $filesize $costtime $valid_time" >> $log_file
      fi
      ;;
    1)
      echo "$local_file $local_size" >> $put_black_list
      echo "`$log_date` $FUNCNAME $hdfs_file Upload Success $filesize $costtime $valid_time (check size)" >> $log_file ;;
    2)
      echo "$file_content" >> $put_retry_list
      echo "`$log_date` hdfs_location_check Upload Failed: \$# != 2 $filesize $costtime $valid_time" >> $log_file ;;
    3)
      echo "$file_content" >> $put_retry_list
      echo "`$log_date` hdfs_location_check Upload Failed: Can't create directory -> $hdfs_dir $filesize $costtime $valid_time" >> $log_file ;;
    4)
      echo "$file_content" >> $put_retry_list
      echo "`$log_date` hdfs_location_check Upload Failed: Can't chmod 777 $hdfs_dir on the hdfs $filesize $costtime $valid_time" >> $log_file ;;
  esac
  rm -rf $1
}

argCheck $1 $2 $3

echo $$ >> $1
PUT_TO_HDFS $1
