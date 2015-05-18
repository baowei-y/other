#!/bin/bash


helpDoc(){
  echo "Usage: $0 [cache block name] [ssd] [mount point]"
  echo "Usage: $0 cache_disk1 /dev/sda5 /data/disk1"
  exit 0
}

argCheck(){
  if [[ $# -ne 3 || ! -b $2 || ! -d $3 ]];then
    echo "Error, Invalid parameters" 
    helpDoc
  fi
}

loadBlock(){
  local fc_cmd=/sbin/flashcache_load
  $fc_cmd $2 $1 &> /dev/null
  return $?
}

checkMount(){
  mount|grep -q $1 ; local rev=$?
  if [[ $rev -eq 0 ]];then
    return 1
  else
    return 0
  fi
}

mainFunc(){
  argCheck $1 $2 $3
  local bp=/dev/mapper/$1
  if checkMount $bp ;then
    if [[ ! -b $bp ]];then
      if loadBlock $1 $2;then
        /bin/mount $bp $3
      fi
    else
      /bin/mount $bp $3
    fi
  fi
}

# 
mainFunc $1 $2 $3 
