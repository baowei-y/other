#!/usr/bin/env python
# -*- coding: utf-8 -*-

import sys
import os
import time
import getopt
import getpass
import paramiko
import ConfigParser
import subprocess
import threading


def cmdRun(cmd, hostsfile):
  file = open(hostsfile)
  for line in file:
    infoall =  line.split()
    ip, port, username, password = infoall[0], infoall[1], infoall[2], infoall[3]
    root_pwd = infoall[4]
    s = paramiko.SSHClient()
    s.load_system_host_keys()
    s.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    s.connect(ip, port, username, password)
    if username != 'root':
      ssh = s.invoke_shell()  
      time.sleep(0.1)
      ssh.send('su - \n')
      buff = ''
      while not buff.endswith('Password: '):
        resp = ssh.recv(9999)
        buff +=resp
      ssh.send(root_pwd)
      ssh.send('\n')
      buff = ''

      while not buff.endswith('# '):
        resp = ssh.recv(9999)
        buff +=resp
      ssh.send(str(cmd[0]))
      out = ssh.recv(1024)
      ssh.send('\n')
      buff = ''
      print out,

      while not buff.endswith('# '):
        resp = ssh.recv(9999)
        buff +=resp

      s.close()
    #stdin, stdout, stderr = s.exec_command(str(cmd[0]))
    #print stdout.read(),
    #s.close()
    

if __name__ == '__main__':
  cmdRun(sys.argv[1:], "/root/hostsfile")
