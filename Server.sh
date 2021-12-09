#!/bin/bash
running=true
port=$1

trap 'running=false; rm tmp/socket' SIGINT

while $running
do
  nc -l -w 1 -p $port >> tmp/socket
done
