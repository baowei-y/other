#!/bin/bash

s_xml=$1
d_xml=$2

helpFunc(){
  if [[ ! -f $s_xml || ! -f $d_xml ]];then
    echo "Usage: $0 [clusetr1-hdfs-site.xml] [cluster2-hdfs-site.xml]"
    echo "  Exam: $0 ./hdfs-site.xml /etc/hadoop/conf/hdfs-site.xml"
    exit 1
  fi
}

filterFunc(){
  grep -q -A 1 "<name>$1\></name>" $s_xml && local s_v=$(grep -A 1 "<name>$1\></name>" $s_xml|/usr/bin/tail -1|awk -F\> '{print $2}'|awk -F\< '{print $1}')
  grep -q -A 1 "<name>$1\></name>" $d_xml && local d_v=$(grep -A 1 "<name>$1\></name>" $d_xml|/usr/bin/tail -1|awk -F\> '{print $2}'|awk -F\< '{print $1}')
  if [[ $s_v != $d_v ]];then
    echo "key:$1 $s_xml=>$s_v $d_xml=>${d_v:-null}"
    echo
  fi
}

mainFunc(){
  for f in `grep "\<name\>" $1|awk -F\> '{print $2}'|awk -F\< '{print $1}'`;do
    filterFunc $f
  done
}

helpFunc
mainFunc $s_xml
