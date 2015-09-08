#!/usr/bin/python
#-*- coding:utf-8-*-
import urllib2
import sys

if __name__ == "__main__":
    url=""
    path=""
    
    if len(sys.argv) == 3:
        url = sys.argv[1]
        path = sys.argv[2]
    else:
        sys.exit('args error')
    print url
    print path
    opener = urllib2.build_opener(urllib2.HTTPHandler) 
    
    data = None
    with open(path) as f:  
        data=f.read()  
        
    request = urllib2.Request(url, data=data)
    request.add_header("Content-Type", "application/octet-stream") 
    request.get_method = lambda:"PUT"  
    url = opener.open(request)
