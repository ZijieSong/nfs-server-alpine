## nfs server alpine in docker

### how to setup

docker run -d --name nfs --privileged -v /some/where/fileshare:/nfsshare -e SHARED_DIRECTORY=/nfsshare zijiesong/nfs-server:latest

if you want share multi volume, just set SHARED_DIRECTORY to multi volume name split by ',' just like "/nfsshare,/test,/etc"

### how to mount from client
sudo mount -v 192.168.151.176:/etc/testConfig ~/test

sudo umount test