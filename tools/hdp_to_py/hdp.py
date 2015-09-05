#!/usr/bin/env python
# -*- coding: utf-8 -*-

import sys
import os
import getopt
import getpass
import paramiko
import ConfigParser
import subprocess
import threading

cf = ConfigParser.ConfigParser()

def usage():
  print "Usage: ....." 

def readConfig(filepath='/opt/hdp.ini'):
  if not os.path.isfile(filepath):
    print "%s no such file." % filepath
    sys.exit(1)
  cf.read(filepath)

def setupRpm():
  rpm = 'python-paramiko \
        python-iniparse \
        python-crypto'
  subprocess.call('yum -y install %s' % (rpm),shell=True)

#def cmdRunPwd():

# 使用ssh秘钥执行远程登录执行命令
def cmdRunKey(cmd, address = '127.0.0.1', port=22, username = getpass.getuser(), pkey = os.environ['HOME'] + '/.ssh/id_rsa'):
  key = paramiko.RSAKey.from_private_key_file(pkey)
  s = paramiko.SSHClient()
  s.load_system_host_keys()
  s.set_missing_host_key_policy(paramiko.AutoAddPolicy())
  s.connect(address, port, username, pkey=key)
  stdin, stdout, stderr = s.exec_command(str(cmd[0]))
  print stdout.read(),
  s.close()

# 命令选择函数，通过hosts_py文件，判断使用秘钥还是密码进行远程执行命令
def cmdRoute(cmd):
  hostsfile = cf.get("basic", "hosts_file")
  if os.path.isfile(hostsfile):
    fileHandle = open(hostsfile, "r")
    fileList = fileHandle.readlines()
    threads = []
    for line in fileList:
      address = line.split()
      c=threading.Thread(target=cmdRunKey,args=(cmd,address[0]))
      c.start()
  else:
    print "%s : no such file" % hostsfile

def functionRouting(opts, args):
  for k, v in opts:
    if k in ["-c"]:
      cmdRoute(sys.argv[2:])
    elif k in ["-k"]:
      setupRpm()
    else:
      usage()
      sys.exit(0)

def getCommand():
  try:
    opts, args = getopt.getopt(sys.argv[1:], 'hkc:')
  except getopt.GetoptError:
    usage()
    sys.exit(2)
  functionRouting(opts, args)

if __name__ == '__main__':
  readConfig('/etc/sysconfig/hdp.ini')
  getCommand()
