#!/bin/bash

[ -x /bin/basename ] && bn_cmd=/bin/basename
[ -x /usr/bin/basename ] && bn_cmd=/usr/bin/basename
[ -x /usr/bin/dirname ] && dn_cmd=/usr/bin/dirname
[ -x /usr/bin/wc ] && wc_cmd=/usr/bin/wc
[ -x /usr/bin/uniq ] && uq_cmd=/usr/bin/uniq

log_date="/bin/date +%H:%M:%S/%Y-%m-%d"
log_dir=/var/log/backup_to_hdfs
log_file=$log_dir/`$bn_cmd $0`.log
[[ ! -d $log_dir ]] && mkdir -p $log_dir

# 检查是否有本脚本pid
pid_file=$log_dir/`$bn_cmd $0`.pid
if [[ -f $pid_file ]];then
 ps -p `cat $pid_file` &> /dev/null
 if [[ "$?" -eq "0" ]];then
   echo "`$log_date` : `cat $pid_file`[$pid_file] exist." >> $log_file
   exit 
 fi
fi
echo $$ > $pid_file 

put_hdfs_list=$log_dir/put_hdfs.list
put_black_list=$log_dir/put_black.list
[ ! -f $put_hdfs_list ] && touch $put_hdfs_list
[ ! -f $put_black_list ] && touch $put_black_list

# 提供一个有效的本地文件作为参数即可
blacklistCheck(){
  if [[ ! -f $1 ]];then
    echo "`$log_date` $FUNCNAME $1 No such file" >> $log_file
    return 1
  fi
  if [ -f $put_black_list ];then
    if grep -q $1 $put_black_list;then
      local file_size=`/usr/bin/du -b $1|awk '{print $1}'`
      local black_size=`grep $1 $put_black_list|awk '{print $NF}'|/usr/bin/tail -1`
      if [[ $file_size == $black_size ]];then
        echo "`$log_date` $1 is exist in the hdfs" >> $log_file
        return 2
      else
        sed -i -e "s@"$1".*@@g" -e '/^$/d' $put_black_list
        echo "`$log_date` $1 file_size($file_size) != black_size($black_size) , So delete file line in the $put_black_list" >> $log_file
        return 0 
      fi
    else
      return 0
    fi
    return 0
  fi
}

delFile(){
  #local days=${1:-30}
  #local delstr=`/bin/date -d "-$1 days" +%Y%m%d`
  for d in `cat $put_black_list|awk '{print $1}'`;do
    if [ -f $d ];then
      rm -f $d
      echo "`$log_date` $d deleted" >> $log_file
#    else
#      echo "`$log_date` $d does not exist" >> $log_file
    fi
  done
}

helpDoc(){
  echo "Usage: $0 [/long/dir] [/long/replace/path] [/hdfs/dir] [120(min)] [30(day)]"
  echo "Exam: $0 /ceph-storage /ceph-storage /log_backup 180 30"
  exit 0
}

argCheck(){
  if [[ ! -d $1 || ! -d $2 || $# -ne 5 ]];then
    helpDoc
  fi 
}

putListCheck(){
  if [ ! -f $put_hdfs_list ];then
    return 0
  fi
  local p_lines=`cat $put_hdfs_list|$wc_cmd -l`
  if [[ $p_lines -ne 0 ]];then
    echo "`$log_date` $1 put_hdfs_list($put_hdfs_list) lines = $p_lines" >> $log_file
    exit 0
  fi
}
# 主调用函数，函数接受参数如下
# $1 : 本地文件有效目录
# $2 : 本地目录需要替换的前缀部分
# $3 : hdfs备份的根目录部分，和$2做替换 
# $4 : 多少分钟前的文件
# $5 : 可以删除的多少天以前的文件
mainFunc(){
  local v_min=${4:-120}
  for f in `find $1 -type f -a -mmin +$v_min -a -name "*.log.201*.tar.gz"`;do
    if blacklistCheck $f;then
      local file_date=`$bn_cmd $f|sed "s@.*.log.\(201[0-9][0-9][0-9][0-9][0-9]\).*.\(tar.gz$\)@\1@g"`
      local hdfs_file=`echo $f|sed "s@$2@$3@g"`
      local hdfs_dir="`$dn_cmd $hdfs_file`/$file_date"
      local hdfs_file="$hdfs_dir/`$bn_cmd $hdfs_file`"
      echo "$f $hdfs_file" >> $put_hdfs_list
    fi
  done
 
}


delFile 
argCheck $1 $2 $3 $4 $5
putListCheck
mainFunc $1 $2 $3 $4
