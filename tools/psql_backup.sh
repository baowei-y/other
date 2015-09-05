#!/bin/bash

[ -x /bin/basename ] && bn_cmd=/bin/basename
[ -x /usr/bin/basename ] && bn_cmd=/usr/bin/basename

date_cmd="/bin/date +%H:%M:%S/%Y-%m-%d"
pid_file=/tmp/$($bn_cmd $0).pid
log_file=/tmp/$($bn_cmd $0).log

pidCheck(){
  [[ ! -f $1 ]] && echo $$ > $1 && return 0
  if [[ -f $1 ]];then
    ps -p `cat $1` &> /dev/null ; local rev=$?
    [[ $rev -eq 1 ]] && echo $$ > $1 && return 0
    echo "`$date_cmd` : `cat $1` pid($1) exist." >> $log_file
    exit 1
  fi
}

helpDoc(){
  echo "Usage: $0 [(remote ip or hostname):/path/backup/]"
  echo "Usage: $0 10.100.0.3:/storage/disk2/pgsql_backup/"
  exit 1
}

mainFunc(){
  if [ -z $1 ];then
    helpDoc
  fi
  local backup_file="/tmp/$(/bin/date +%Y%m%d%H%M).postgresql.all.gz"
  su -l postgres -c "/usr/bin/pg_dumpall|/bin/gzip > $backup_file"
  /usr/bin/rsync -av $backup_file $1 &> /dev/null ; local rev=$?
  if [[ $rev -eq 0 ]];then
    rm -rf $backup_file
    echo "$($date_cmd) : $backup_file [deleted] -> $1/$($bn_cmd $backup_file) OK" >> $log_file
  else
    echo "$($date_cmd) : $backup_file [not deleted] -> $1/$($bn_cmd $backup_file) Fail" >> $log_file
  fi
}

pidCheck $pid_file
mainFunc $1
