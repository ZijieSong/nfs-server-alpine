#!/bin/bash

# Make sure we react to these signals by running stop() when we see them - for clean shutdown
# And then exiting
trap "stop; exit 0;" SIGTERM SIGINT

stop() {
  # We're here because we've seen SIGTERM, likely via a Docker stop command or similar
  # Let's shutdown cleanly
  echo "SIGTERM caught, terminating NFS process(es)..."
  /usr/sbin/exportfs -uav
  /usr/sbin/rpc.nfsd 0
  pid1=$(pidof rpc.nfsd)
  pid2=$(pidof rpc.mountd)
  # For IPv6 bug:
  pid3=$(pidof rpcbind)
  kill -TERM $pid1 $pid2 $pid3 >/dev/null 2>&1
  echo "Terminated."
  exit
}

# Check if the SHARED_DIRECTORY variable is empty
if [ -z "${SHARED_DIRECTORY}" ]; then
  echo "The SHARED_DIRECTORY environment variable is unset or null, exiting..."
  exit 1
else
  echo "Writing to /etc/exports file"
  OLD_IFS="$IFS"
  IFS=","
  dir_arr=($SHARED_DIRECTORY)
  IFS="$OLD_IFS"

  fsid=1
  for s in ${dir_arr[@]}; do
    echo "$s *(rw,fsid=$fsid,async,no_subtree_check,no_auth_nlm,insecure,no_root_squash)" >>/etc/exports
    let fsid+=1
  done
fi

# Partially set 'unofficial Bash Strict Mode' as described here: http://redsymbol.net/articles/unofficial-bash-strict-mode/
# We don't set -e because the pidof command returns an exit code of 1 when the specified process is not found
# We expect this at times and don't want the script to be terminated when it occurs
set -uo pipefail
IFS=$'\n\t'

# This loop runs till until we've started up successfully
while true; do

  # Check if NFS is running by recording it's PID (if it's not running $pid will be null):
  pid=$(pidof rpc.mountd)

  # If $pid is null, do this to start or restart NFS:
  while [ -z "$pid" ]; do
    echo "Displaying /etc/exports contents:"
    cat /etc/exports
    echo ""

    # Normally only required if v3 will be used
    # But currently enabled to overcome an NFS bug around opening an IPv6 socket
    echo "Starting rpcbind..."
    /sbin/rpcbind -w
    echo "Displaying rpcbind status..."
    /sbin/rpcinfo

    mount -t nfsd nfsd /proc/fs/nfsd
    # Fixed nlockmgr port
    echo 'fs.nfs.nlm_tcpport=32768' >>/etc/sysctl.conf
    echo 'fs.nfs.nlm_udpport=32768' >>/etc/sysctl.conf
    sysctl -p >/dev/null

    rpcbind -w
    rpc.nfsd -N 2 -V 3 -N 4 -N 4.1 8
    exportfs -arfv
    rpc.statd -p 32765 -o 32766
    rpc.mountd -N 2 -V 3 -N 4 -N 4.1 -p 32767 -F

    # Check if NFS is now running by recording it's PID (if it's not running $pid will be null):
    pid=$(pidof rpc.mountd)

    # If $pid is null, startup failed; log the fact and sleep for 2s
    # We'll then automatically loop through and try again
    if [ -z "$pid" ]; then
      echo "Startup of NFS failed, sleeping for 2s, then retrying..."
      sleep 2
    fi

  done

  # Break this outer loop once we've started up successfully
  # Otherwise, we'll silently restart and Docker won't know
  echo "Startup successful."
  break

done

while true; do

  # Check if NFS is STILL running by recording it's PID (if it's not running $pid will be null):
  pid=$(pidof rpc.mountd)
  # If it is not, lets kill our PID1 process (this script) by breaking out of this while loop:
  # This ensures Docker observes the failure and handles it as necessary
  if [ -z "$pid" ]; then
    echo "NFS has failed, exiting, so Docker can restart the container..."
    break
  fi

  # If it is, give the CPU a rest
  sleep 1

done

sleep 1
exit 1
