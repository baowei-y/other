#!/bin/bash

[ -x /bin/basename ] && bn_cmd=/bin/basename
[ -x /usr/bin/basename ] && bn_cmd=/usr/bin/basename
[ -x /usr/bin/dirname ] && dn_cmd=/usr/bin/dirname
[ -x /usr/bin/wc ] && wc_cmd=/usr/bin/wc
[ -x /usr/bin/uniq ] && uq_cmd=/usr/bin/uniq
[ -x /usr/bin/hadoop ] && hdp_cmd=/usr/bin/hadoop
[ -x /usr/bin/md5sum ] && ms_cmd=/usr/bin/md5sum

log_date="/bin/date +%H:%M:%S/%Y-%m-%d"
log_dir=/var/log/ftp_op
[ ! -d $log_dir ] && mkdir -p $log_dir
log_file=$log_dir/ftp_op.log

# 检查是否有本脚本pid
pid_file=/tmp/`$bn_cmd $0`_ftp_op.pid
if [ -f $pid_file ];then
 ps -p `cat $pid_file` &> /dev/null
 [[ "$?" -eq "0" ]] && echo "`$log_date` : $0 exist." && exit 0
fi
echo $$ > $pid_file 

files_md5_list=$log_dir/files_md5.list
retry_down_list=$log_dir/retry_files.list
put_hdfs_list=$log_dir/put_hdfs.list
put_retry_list=$log_dir/retry_put.list

ftp_host="10.127.3.51:52039"
ftp_user=nilesftp
ftp_pass=Nile1408
ftp_source_dir=/MIAOZHEN
ftp_mv_dir=/ftp_backup

tmp_dir1=/tmp/ftptmp1 ; tmp_dir2=/tmp/ftptmp2 ; tmp_dir3=/tmp/ftptmp3
[[ ! -d $tmp_dir1 || ! -d $tmp_dir2 || ! -d $tmp_dir3 ]] && mkdir -p $tmp_dir1 $tmp_dir2 $tmp_dir3

transit_dir=/storage/disk10/MIAOZHEN
final_dir=/storage/disk9/MIAOZHEN
hdfs_dir=/ftp_ngi/MIAOZHEN
mv_str=report
checkfile_str=checkfile
[[ ! -d $transit_dir || ! -d $final_dir ]] && mkdir -p $transit_dir $final_dir


# 日志记录函数
TEE(){
  /usr/bin/tee -a $log_file
}

# ftp操作函数
FTP_OP(){
  /usr/bin/lftp << EOF
open sftp://$ftp_user:$ftp_pass@$ftp_host
$1 $2 $3 $4 $5 $6 $7 $8
EOF
}

# 完整下载
FULL_SYNC(){
  if [[ $# -ne 2 || -z $1 || ! -d $2 ]];then
    echo "`$log_date` $FUNCNAME Error \$#!=2 or \$1 is empty or \$2 No such directory" >> $log_file
    return 1
  fi
  FTP_OP mirror $1 $2 &> /dev/null
}


# ftp文件的删除函数
# 此函数需要提供一个两个有效参数 $1 $2
# $1 为一个本地有效文件，$2 为这个文件的父目录
# 当此文件在本地存在，并要调用此函数时：
# 说明此文件已经完整的下载到了本地
FTP_CLEAN(){
  if [[ ! -f $1 ]];then
    echo "`$log_date` $FUNCNAME Error \$1=$1 or \$2=$2 No such file or directory" >> $log_file
    return 1
  fi

  ftp_file=`echo $1|sed "s@$2@$ftp_source_dir@1"`
#  del_condition=`echo $ftp_file|grep "\/\<$mv_str\>\/"|$wc_cmd -l`
#  if [[ $del_condition -eq 0 ]];then
    FTP_OP rm -rf $ftp_file
    echo "`$log_date` $FUNCNAME $ftp_file deleted in the ftp" >> $log_file
    return 0
#  else
#    ftp_bak_file=`echo $ftp_file|sed "s@$ftp_source_dir@$ftp_mv_dir@1"`
#    ftp_bak_dir=`/usr/bin/dirname $ftp_bak_file`
#    FTP_OP mkdir -p $ftp_bak_dir &> /dev/null
#    FTP_OP rm -rf $ftp_bak_file
#    FTP_OP mv $ftp_file $ftp_bak_file &> /dev/null
#    echo "`$log_date` $FUNCNAME mv $ftp_file $ftp_bak_file in the ftp" >> $log_file
#    return 0
#  fi
}

# 此函数可以将文件移动到指定路径
# 此函数在移动过程中可以根据提供父目录进行替换
# 此函数的$4和$5文件会被直接删除
# 此函数最少需要提供三个参数 $1 $2 $3
# $1 ：一个有效源文件路径
# $2 : $1的父目录，也就是要被替换成$3的部分
# $3 : 目标位置的父目录
# $4 : 需要删除的文件1
# $5 : 需要删除的文件2
MV_FILE(){
  if [[ $# -le 2 || ! -f $1 || ! -d $3 ]];then
    echo "`$log_date` $FUNCNAME Error \$1 No such file or \$3 No such directory or \$#<3" >> $log_file
    return 1
  fi
  dest_file=`echo $1|sed "s@$2@$3@1"`
  dest_dir=`/usr/bin/dirname $dest_file`
  [ ! -d $dest_dir ] && mkdir -p $dest_dir
  mv -f $1 $dest_file
  if [[ $? -ne 0 ]];then
    echo "`$log_date` $FUNCNAME Error mv -f $1 $dest_file" >> $log_file
    return 1
  else
    echo "`$log_date` $FUNCNAME $dest_file Move Success" >> $log_file
    echo "$dest_file" >> $put_hdfs_list
    FTP_CLEAN $dest_file $3
    rm -rf $4 $5
    return 0
  fi
}

# 此函数将ftp文件下载到本地某个目录内，
# 此函数保留ftp原有目录结构
# 此函数需要两个参数 $1 和 $2
# $1是ftp文件绝对路径
# $2是要下载到本地父目录
DOWN_FILE(){
  [[ $# -ne 2 || ! -d $2 ]] && echo "`$log_date` $FUNCNAME Error \$#!=3 or \$2 is not directory "
  file_name=`echo $1|sed "s@$ftp_source_dir@$2@1"` 
  file_dir=`$dn_cmd $file_name`
  [ ! -d $file_dir ] && mkdir -p $file_dir
  [ ! -f $file_name ] && FTP_OP get $1 -o $file_name &> /dev/null
  if [ -f $file_name ];then
    echo $file_name
    return 0 
  else
    echo "`$log_date` $FUNCNAME Error \$file_name=$file_name Download failed" >> $log_file
    return 1
  fi
}

# 需要提供两个文件,进行md5校验,并生成md5sum
MD5SUM_CHECK(){
  if [[ $# -ne 3 || ! -f $1 || ! -f $2 || ! -d $3 ]];then
    echo "`$log_date` $FUNCNAME Error \$1=$1 or \$2=$2 or \$3=$3 No such file or directory" >> $log_file
    return 1
  fi
  md5_res=`$ms_cmd $1 $2|awk '{print $1}'|$uq_cmd|$wc_cmd -l`
  if [[ $md5_res -eq 1 ]];then
    cf_name=`echo $1|sed "s@$3@$final_dir@1"`
    cf_dir=`echo $cf_name|$dn_cmd $cf_name`
    cat $1|sed "s@\(.*\)@\1\t$cf_dir@g" >> $files_md5_list
    return 0 
  else
    return 1
  fi
}

# 下载文件，尝试最多两次下下载
# 比对给出文件和下载文件的md5
# 此函需要提供两个参数 $1 $2
# $1 ：一个本地的有效文件
# $2 : $1的父目录
CHECK_DOWN(){
  if [[ ! -f $1 ]];then
    echo "`$log_date` $FUNCNAME Error No such file" >> $log_file
    return 1
  fi

  ftp_filename=`echo $1|sed "s@$2@$ftp_source_dir@1"`
  sleep 5
  check_file1=`DOWN_FILE $ftp_filename $tmp_dir1`
  [ ! -f $check_file1 ] && echo "`$log_date` $FUNCNAME Error \$check_file1=$check_file1 No such file" >> $log_file && return 1
  if MD5SUM_CHECK $1 $check_file1 $2;then
    MV_FILE $1 $2 $final_dir $check_file1 
    return 0
  else
    sleep 5
    check_file2=`DOWN_FILE $ftp_filename $tmp_dir2`
    [ ! -f $check_file2 ] && echo "`$log_date` $FUNCNAME Error \$check_file2=$check_file2 No such file" >> $log_file && return 1
    if MD5SUM_CHECK $1 $check_file2 $2;then
      MV_FILE $1 $2 $final_dir $check_file2
      return 0
    else
      if MD5SUM_CHECK $check_file1 $check_file2 $tmp_dir1;then
        MV_FILE $check_file2 $tmp_dir2 $final_dir $check_file1 $1
        return 0 
      else
        echo "`$log_date` $FUNCNAME Error \$1=$1 != $check_file1 != $check_file2" >> $log_file
        rm -rf $1 $check_file1 $check_file2
        return 1
      fi
    fi
  fi
}

# 遍历所需下载的文件，找出有效目录并下载
# 此函数需要提供一个参数$1
# $1：已下载文件所在目录父目录
SGM_CHECKDIRS(){
  [[ ! -d $1 ]] && echo "`$log_date` $FUNCNAME No such directory" >> $log_file && return 1 
  for f in `find $1 -name "*$checkfile_str"`;do
    [ ! -f "$f" ] && continue
    CHECK_DOWN $f $1
  done
}

# 列表检查函数
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

# 根据本地已有的md5做校验.
FILES_CHECK(){
  RETRY_LIST $retry_down_list $1
  if [[ $# -ne 2 || ! -f $1 || ! -d $transit_dir ]];then
    echo "`$log_date` $FUNCNAME \$#!=2 or \$1 No such file or \$2 No such directory" >> $log_file 
    return 0
  fi
  local check_sums=`cat $1|$wc_cmd -l`
  [[ $check_sums -eq 0 ]] && echo "`$log_date` $FUNCNAME $1 is empty" >> $log_file && return 0
  
  for cc in `/usr/bin/seq 1 $check_sums`;do 
  #for cc in `/usr/bin/seq 1 2`;do 
    local f_name=`sed -n "1p" $1|awk '{print $1}'`
    local f_md5=`sed -n "1p" $1|awk '{print $2}'`
    local last_path=`sed -n "1p" $1|awk '{print $3}'`
    local now_path=`echo $last_path|sed "s@$final_dir@$2@1"`
    local now_file=$now_path/$f_name
    if [[ ! -f $now_file ]];then
#      echo "`$log_date` $FUNCNAME $now_file no such file" >> $log_file
      sed -n "1p" $1 >> $retry_down_list
      sed -i "1d" $1
      continue
    fi
    local now_md5sum=`$ms_cmd $now_file|awk '{print $1}'`
    if [[ "$now_md5sum" == "$f_md5" ]];then
      MV_FILE $now_file $2 $final_dir 
      sed -i "1d" $1
    else
      rm -rf $now_file
      sed -n "1p" $1 >> $retry_down_list
      sed -i "1d" $1 
    fi
  done
}

FULL_SYNC $ftp_source_dir $transit_dir
FILES_CHECK $files_md5_list $transit_dir
SGM_CHECKDIRS $transit_dir
FILES_CHECK $files_md5_list $transit_dir

rm -rf $pid_file
