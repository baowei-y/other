#!/bin/bash

[ -x /bin/basename ] && bn_cmd=/bin/basename
[ -x /usr/bin/basename ] && bn_cmd=/usr/bin/basename
[ -x /usr/bin/dirname ] && dn_cmd=/usr/bin/dirname
[ -x /usr/bin/wc ] && wc_cmd=/usr/bin/wc
[ -x /usr/bin/uniq ] && uq_cmd=/usr/bin/uniq
[ -x /usr/bin/hadoop ] && hdp_cmd=/usr/bin/hadoop
[ -x /usr/bin/md5sum ] && ms_cmd=/usr/bin/md5sum

mail_date="/bin/date +%Y%m%d%H%M%S"

# 载入参数1指定的配置文件
if [[ ! -f $1 ]];then
  echo "Usage: $0 /etc/ftp_lab.conf"
  echo "Usage: $0 /etc/ftp_lab.conf --test"
  exit 0
else
  . $1
fi

[[ ! -d $run_dir/mail || ! -d $local_dir ]] && mkdir -p $run_dir/mail $local_dir

# 日志记录函数
TEE(){
  /usr/bin/tee -a $log_file
}

# pid检查函数
pidCheck(){
  [[ ! -f $1 ]] && echo $$ > $1 && return 0
  if [[ -f $1 ]];then
    ps -p `cat $1` &> /dev/null ; local rev=$?
    [[ $rev -eq 1 ]] && echo $$ > $1 && return 0
    echo "`$date_cmd` : `cat $1` pid($1) exist." >> $log_file
    exit 1
  fi
}

mailFunc(){
  [[ ! -f $1 ]] && echo "`$log_date` $FUNCNAME Message body file specified [$1] does not exist"|TEE && return 1
  local arg_1="-f $from_mail -t $to_mail -s $smtp_mail"
  local arg_2="-xu $user_mail -xp $pass_mail -u ${2:-"MTF FTP Download Report"}"
  local arg_3="-o message-charset=utf-8 -o message-file=$1"
  local mail_exec="$cmd_mail $arg_1 $arg_2 $arg_3"
  $mail_exec &> /dev/null ; local rev=$?
  if [[ $rev -eq 0 ]];then
    echo "`$log_date` $FUNCNAME Email was sent successfully[$mail_exec]" >> $log_file
  else
    echo "`$log_date` $FUNCNAME Command Failed[$mail_exec]" >> $log_file
  fi
}

# ftp操作函数
ftpOp(){
  /usr/bin/lftp << EOF
open $ftp_type://$ftp_user:$ftp_pass@$ftp_host
$1 $2 $3 $4 $5 $6 $7 $8
EOF
}

# 完整下载
fullDown(){
  if [[ $# -ne 2 || -z $1 || ! -d $2 ]];then
    echo "`$log_date` $FUNCNAME Error \$#!=2 or \$1 is empty or \$2 No such directory"|TEE
    return 1
  fi
  ftpOp mirror $1 $2 &> /dev/null
}

# ftp文件的删除函数
# 此函数需要提供一个有效参数 $1
# $1 FTP的文件目录
ftpDel(){
  if [[ -z $1 ]];then
    echo "`$log_date` $FUNCNAME Error \$1=$1 or \$2=$2 No such file or directory"|TEE
    return 1
  fi

  ftpOp rm -rf $1
  echo "`$log_date` $FUNCNAME $1 deleted in the ftp" >> $log_file
  return 0
}

# 日志检查函数，此函数最少提供一个文件路径作为参数
# 此函数检查参数文件中日志，输出或退出
# $1 : 一个仅有日期的文件
dateCheck(){
  # 日期文件检查
  if [[ ! -f $1 ]];then
    echo "`$log_date` $FUNCNAME $1 No such file"|TEE
    local mail_file="$path_mail.`$mail_date`"
    echo "`$log_date` $FUNCNAME Error [$1] No such file" > $mail_file 
    mailFunc $mail_file "MTF FTP PROBLEM : date"
    exit 1
  fi
  # 如果日期为今天，则退出
  local today=`/bin/date +%Y%m%d` 
  local file_day=`cat $1`
  if [[ $file_day == $today ]];then
    echo "`$log_date` $FUNCNAME Exit [$1($file_day) == today($today)]"|TEE
    exit 0
  fi
  # 输出有效日期或根据传递进来的参数修改日期文件
  if [[ $# -eq 1 ]];then
    echo $file_day
    return 0
  elif [[ $# -eq 2 ]];then
    echo `/bin/date -d "$file_day $2 days" +"%Y%m%d"` > $1
    echo `cat $1`
    return 0
  fi
}

# 此函数将ftp文件下载到本地某个目录内，
# 此函数保留ftp原有目录结构
# 此函数需要两个参数 $1 和 $2
# $1 ftp文件绝对路径
# $2 要下载到本地父目录
# $3 指定下载文件的,可选参数
ftpDownFile(){
  [[ ! -d $2 ]] && echo "`$log_date` $FUNCNAME Error \$2=$2 directory not exist" >> $log_file
  local file_name=`$bn_cmd $1`
  local file_path="$2/${3:-$file_name}"
  if [ -f $file_path ];then
    local new_name=$file_path.`/bin/date +%Y%m%d%H%M%S`
    mv -f $file_path $new_name
    echo "`$log_date` $FUNCNAME Warn $file_path exist. rename to $new_name"  >> $log_file
  fi
  ftpOp get $1 -o $file_path &> /dev/null
  if [ -f $file_path ];then
    echo $file_path
    return 0 
  else
    echo "`$log_date` $FUNCNAME Error \$file_name=$file_name Download failed" >> $log_file
    return 1
  fi
}

# 需要提供两个文件,进行md5校验,并生成md5sum
md5Check(){
  if [[ $# -ne 2 || ! -f $1 || ! -f $2 ]];then
    echo "`$log_date` $FUNCNAME Error \$1=$1 or \$2=$2  No exist"|TEE
    return 1
  fi
  local md5_res=`$ms_cmd $1 $2|awk '{print $1}'|$uq_cmd|$wc_cmd -l`
  [[ $md5_res -eq 1 ]] && return 0 || return 1
}

# 下载文件，尝试最多两次下下载
# 比对给出文件和下载文件的md5
# 此函需要提供两个参数 $1 $2
# $1 : 此文件所在的本地路径
# $2 : 要对比的文件名字
# $3 : 此文件的父目录
# $4 : 此文件所在的ftp路径
# $5 : 两次下载的间隔周期，此参数不给则默认为15s
md5fileCheck(){
  if [[ ! -f "$1" ]];then
    echo "`$log_date` $FUNCNAME "$1" No such file"|TEE
    return 1
  fi
  local ftp_filename="$4/$2"
  local period=${5:-5} ; sleep $period
  local check_file1=`ftpDownFile $ftp_filename $3 "$2.down-1"`
  [ ! -f $check_file1 ] && echo "`$log_date` $FUNCNAME $check_file1 No such file"|TEE && return 1
  if md5Check $1 $check_file1 ;then
    rm -rf $check_file1
    return 0
  else
    sleep $period
    check_file2=`ftpDownFile $ftp_filename $3 "$2.down-2"`
    [ ! -f $check_file2 ] && echo "`$log_date` $FUNCNAME Error \$check_file2=$check_file2 No such file"|TEE && return 1
    if md5Check $1 $check_file2 ;then
      rm -rf $check_file1 $check_file2
      return 0
    else
      if md5Check $check_file1 $check_file2 ;then
        rm -rf $check_file2
        mv -f $check_file1 $1
        return 0 
      else
        echo "`$log_date` $FUNCNAME checkfile md5sum check failed (download 3)" >> $log_file
        rm -rf $3
        return 1
      fi
    fi
  fi
}

# 此函数根据md5进行文件检查，参数如下
# $1 文件父路径
# $2 当前目录所有checkfile最终合并成为的临时文件
# $3 ftp文件父路径
# $4 日志文件
validFileCheck(){
  local mail_file=${4:-"$path_mail.`$mail_date`"}
  local lines=`cat $2|$wc_cmd -l`
  local ss=0
  echo "Current path: ftp[ $3 ] -> local[ $1 ] " >> $mail_file
  for vv in `/usr/bin/seq 1 $lines`;do
    local f_name=`sed -n "1p" $2|awk '{print $1}'` 
    local f_md5=`sed -n "1p" $2|awk '{print $2}'`
    local f_path=$1/$f_name
    if [[ ! -f $f_path ]];then
      echo "$f_name $f_md5 [ Error : file does not exist ]" >> $mail_file
      sed -i "1d" $2
      continue
    fi
    local now_md5=`$ms_cmd $f_path|awk '{print $1}'`
    if [[ "$f_md5" == "$now_md5" ]];then
      echo "$f_name $f_md5 [ ok ]" >> $mail_file
      sed -i "1d" $2
      let ss++
      continue
    else
      echo "$f_name $f_md5 [ Error : Invalid md5sum -> $now_md5 ]" >> $mail_file
      sed -i "1d" $2 
      continue
    fi
  done 
  # 当完全匹配行数一致，且有效文件数量一致时：
  # 删除临时checkfile文件，删除ftp当天文件
  # 生成有效文件列表追加上传hdfs列表
  # 修改有效时间加一天
  # 发送成功信息邮件
  if [[ $ss -eq  $lines && -z $4 ]];then
    rm -rf $2
    find $1 -type f >> $into_hdfs_list
    ftpDel $3 
    echo "[ $3 ] deleted in the ftp" >> $mail_file
    local m_date=`dateCheck $ftp_dir_date 1`
    local nn_ftp="$ftp_dir_header/$m_date/$ftp_dir_end"
    local nn_local=`echo "$nn_ftp"|sed "s@$ftp_dir@$local_dir@g"`
    echo "Next path : ftp[ $nn_ftp ] -> local[ $nn_local ] " >> $mail_file
    mailFunc $mail_file "MTF FTP INFO : check files ok" 
    exit 0
  else
    # 当出现文件数量或者md5sum不匹配时:
    # 删除本地已下载文件，删除临时文件checkfile文件
    # 发送失败邮件
    rm -rf $2 $1
    echo "Next path : ftp[ $3 ] -> local[ $1 ]" >> $mail_file
    mailFunc $mail_file "MTF FTP PROBLEM : check files failed"
    exit 10
  fi
}

# 根据checkfile校验所有文件，此函数接收三个参数
# $1 : 本地文件路径
# $2 : checkfile文件数组
# $3 : 目录内文件数组
# $4 : ftp文件路径
checkFiles(){
  local checkfiles=(`echo $2`)
  local existfiles=(`echo $3`)
  
  # 合并checkfile的内容生成一个临时文件
  local t_file=`/bin/mktemp /var/log/ftp_op/all.checkfiles.XXXXXXXXXX`
  for i in ${checkfiles[@]};do
    cat $i >> $t_file 
  done

  # 当合并后的文件总行数为0时,发出报警邮件并退出
  # 不为0, 则统计当前有效文件和目录文件的数量,如果两者不相等，则记录各自对应的数量
  local valid_files=`cat $t_file|$wc_cmd -l`
  if [[ $valid_files -eq 0 ]];then
    local mail_file="$path_mail.`$mail_date`"
    echo "`$log_date` $FUNCNAME Error checkfile lines: 0" >> $mail_file 
    echo "files: ${checkfiles[@]}" >> $mail_file
    mailFunc $mail_file "MTF FTP PROBLEM : checkfile lines"
    exit 2
  else
    # 如果文件数量和有效文件数量不相等，则记录文件相关数量和文件名
    local vaild_files=`echo $valid_files ${#checkfiles[@]}|awk '{print $1+$2}'`
    if [[ ${#existfiles[@]} -ne $vaild_files ]];then
      local mail_file="$path_mail.`$mail_date`"
      echo "###############################" >> $mail_file
      echo "## all files (${#existfiles[@]})##" >> $mail_file
      for e in ${existfiles[@]};do
        echo `$bn_cmd $e` >> $mail_file
      done
      echo "###############################" >> $mail_file
      echo "## valid files ($vaild_files)##" >> $mail_file
      for ccc in ${checkfiles[@]};do
        echo `$bn_cmd $ccc` >> $mail_file
      done
      cat $t_file|awk '{print $1}' >> $mail_file
      echo "###############################" >> $mail_file
      echo "##########################################################" >> $mail_file
      echo "##########################################################" >> $mail_file
    fi
  fi
  validFileCheck $1 $t_file $4 $mail_file
}

# 遍历所需下载的文件，找出有效目录并下载
# 此函数需要提供一个参数$1
# $1 ：已下载文件所在目录父目录
# $2 : ftp路径地址
# $3 : 本地有效文件列表
md5fileFind(){
  [[ ! -d $1 ]] && echo "`$log_date` $FUNCNAME No such directory"|TEE && return 1 
  local count_checkfile=(`find $1 -name "*$checkfile_str"`)
  # 没有checkfile时，直接跳出
  if [[ ${#count_checkfile[@]} -eq 0 ]];then
    local mail_file="$path_mail.`$mail_date`"
    echo "`$log_date` $FUNCNAME $f no such valid checkfile in the ftp($2)" > $mail_file
    mailFunc $mail_file "MTF FTP PROBLEM : checkfile"
    return 1
  fi
  # 对已有的checkfile做最多三次下载
  local count_rc=0
  for f in ${count_checkfile[@]};do
    local fn=`$bn_cmd $f`
    if md5fileCheck $f $fn $1 $2 ;then
      let count_rc++
    else
      local mail_file="$path_mail.`$mail_date`"
      echo "`$log_date` $FUNCNAME $f md5 check failed (download 3)" > $mail_file
      mailFunc $mail_file "MTF FTP PROBLEM : checkfile"
      return 1
    fi
  done
  if [[ $count_rc -eq ${#count_checkfile[@]} ]];then
    checkFiles $1 "${count_checkfile[*]}" "$3" $2
  fi
}

# 主控制函数，需要提供最少两个参数，参数拼接起来则为ftp下载路径
# $1 : ftp文件路径，例如: /MAIOZHEN/AdMonitor
# $2 : 起始处理日期文件，例如：/local_disk/admonitor.date(20150402)
# $3 : 路径最后一部分，例如 report (非必要参数)
# 按照上述三个参数，最后得出路径： /MAIOZHEN/AdMonitor/20150402/report
# 按照上述给出前两个个参数，最后得出路径： /MAIOZHEN/AdMonitor/20150402
mainFunc(){
  local dir_date=`dateCheck $2`
  local dir_ftp=$1/$dir_date/$3
  local dir_local=`echo $dir_ftp|sed "s@$ftp_dir@$local_dir@g"`

  if [[ $4 == "--test" ]];then
    echo "ftp_dir: $dir_ftp"
    echo "local_dir: $dir_local"
    exit 0
  fi

  [[ ! -d $dir_local ]] && mkdir -p $dir_local

  fullDown $dir_ftp $dir_local
  local files_count=`find $dir_local -type f`
  if [[ ${#files_count[@]} -eq 0 ]];then
    local mail_file="$path_mail.`$mail_date`"
    echo "`$log_date` $FUNCNAME Error [$dir_ftp] Directory is null in the ftp" > $mail_file 
    mailFunc $mail_file "MTF FTP PROBLEM : directory"
  else
    md5fileFind $dir_local $dir_ftp "${files_count[*]}"
  fi
}

# 配置文件语法检查
confCheck(){
  [[ ! -f $ftp_dir_date ]] && echo "[ftp_dir_date : $ftp_dir_date] invalid config in the [$1]" && exit 20
  [[ ! -x $cmd_mail ]] && echo "[cmd_mail: $cmd_mail] invalid config in the [$1] or permission error" && exit 21
  [[ -z $log_date ]] && echo "[log_date: $log_date] invalid config in the [$1]" && exit 22
  [[ -z $checkfile_str ]] && echo "[checkfile_str: $checkfile_str] invalid config in the [$1]" && exit 23
  [[ -z $path_mail ]] && echo "[path_mail: $path_mail] invalid config in the [$1]" && exit 24
}

del_mail="$path_mail.`/bin/date -d "-$days_mail days" +%Y%m%d`"
rm -rf "$del_mail"*

pidCheck $pid_file
confCheck $1
mainFunc $ftp_dir_header $ftp_dir_date $ftp_dir_end $2

rm -rf $pid_file
