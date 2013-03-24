#!/bin/bash

# This annotated script sets up a limited deployment of OpenStack Swift
# onto a Raspberry Pi. It sets up a one-replica, one-server environment
# appropriate for external testing. It assumes there is a user called "pi"
# and that user has sudo access (this is the default on a Raspberry Pi).


set -e

# install requirements
# I assume you've already done an `apt-get update && apt-get upgrade`

sudo apt-get install python-software-properties curl gcc git memcached \
    python-coverage python-dev python-nose python-setuptools \
    python-simplejson python-xattr sqlite3 xfsprogs python-eventlet \
    python-greenlet python-pastedeploy python-netifaces python-pip \
    python-sphinx
sudo pip install mock tox dnspython


# build loopback drive
sudo mkdir -p /srv
sudo truncate -s 1GB /srv/swift-disk
sudo mkfs.xfs -f -i size=512 /srv/swift-disk

# update /etc/fstab
grep '/srv/swift-disk' /etc/fstab
if [ $? = 1 ]; then
sudo tee -a /etc/fstab >/dev/null <<EOF

/srv/swift-disk /mnt/sdb1 xfs loop,noatime,nodiratime,nobarrier,inode64,logbufs=8 0 0
EOF
fi

sudo mkdir -p /mnt/sdb1/1

sudo chown -R pi:pi /mnt/sdb1/1
sudo ln -fs /mnt/sdb1/1 /srv/1
sudo chown -R pi:pi /etc/swift /srv/1/ /var/run/swift

# update /etc/rc.local
grep 'su - pi /home/pi/bin/startmain' /etc/rc.local
if [ $? = 1 ]; then
sudo tee -a /etc/rc.local >/dev/null <<EOF

mkdir -p /var/cache/swift
chown pi:pi /var/cache/swift*
mkdir -p /var/run/swift
chown pi:pi /var/run/swift
su - pi /home/pi/bin/startmain
EOF
fi

sudo tee /etc/rsyncd.conf >/dev/null <<EOF
uid = pi
gid = pi
log file = /var/log/rsyncd.log
pid file = /var/run/rsyncd.pid
address = 127.0.0.1

[account6012]
max connections = 25
path = /srv/1/node/
read only = false
lock file = /var/lock/account6012.lock


[container6011]
max connections = 25
path = /srv/1/node/
read only = false
lock file = /var/lock/container6011.lock

[object6010]
max connections = 25
path = /srv/1/node/
read only = false
lock file = /var/lock/object6010.lock
EOF

sudo tee /etc/rsyslog.d/10-swift.conf >/dev/null <<EOF
# Uncomment the following to have a log containing all logs together
local1,local2,local3,local4,local5.*   /var/log/swift/all.log

# Uncomment the following to have hourly proxy logs for stats processing
$template HourlyProxyLog,"/var/log/swift/hourly/%\$YEAR%%\$MONTH%%\$DAY%%\$HOUR%"
local1.*;local1.!notice ?HourlyProxyLog

local1.*;local1.!notice /var/log/swift/proxy.log
local1.notice           /var/log/swift/proxy.error
local1.*                ~

local2.*;local2.!notice /var/log/swift/storage1.log
local2.notice           /var/log/swift/storage1.error
local2.*                ~
EOF

sudo mkdir -p /var/log/swift/hourly
sudo chmod -R g+w /var/log/swift



set +e
cd && git clone git://github.com/openstack/python-swiftclient.git
set -e
cd ~/python-swiftclient; git pull origin master && sudo python ./setup.py develop

set +e
cd && git clone git://github.com/openstack/swift.git
set -e
cd ~/swift; git pull origin master && sudo python ./setup.py develop

cd && mkdir -p ~/bin

sudo mkdir -p /etc/swift
sudo chown pi:pi /etc/swift


cat >/etc/swift/proxy-server.conf <<EOF
[DEFAULT]
bind_port = 8080
user = pi
log_facility = LOG_LOCAL1
log_level = DEBUG
eventlet_debug = true

[pipeline:main]
pipeline = catch_errors healthcheck proxy-logging cache slo ratelimit tempurl formpost tempauth staticweb container-quotas account-quotas proxy-logging proxy-server

[app:proxy-server]
use = egg:swift#proxy
allow_account_management = true
account_autocreate = true

[filter:tempauth]
use = egg:swift#tempauth
user_admin_admin = admin .admin .reseller_admin
user_test_tester = testing .admin
user_test2_tester2 = testing2 .admin http://192.168.52.2:8080/v1/AUTH_test2
user_test4_tester4 = testing4 .admin http://192.168.52.2:8080/v1/AUTH_test4
user_test_tester3 = testing3
user_demo_demo = demo .admin http://192.168.52.2:8080/v1/AUTH_abc

[filter:catch_errors]
use = egg:swift#catch_errors

[filter:healthcheck]
use = egg:swift#healthcheck

[filter:cache]
use = egg:swift#memcache

[filter:proxy-logging]
use = egg:swift#proxy_logging

[filter:ratelimit]
use = egg:swift#ratelimit

[filter:domain_remap]
use = egg:swift#domain_remap

[filter:cname_lookup]
# Note: this middleware requires python-dnspython
use = egg:swift#cname_lookup

[filter:staticweb]
use = egg:swift#staticweb

[filter:formpost]
use = egg:swift#formpost

[filter:list-endpoints]
use = egg:swift#list_endpoints

[filter:bulk]
use = egg:swift#bulk

[filter:container-quotas]
use = egg:swift#container_quotas

[filter:account-quotas]
use = egg:swift#account_quotas

[filter:slo]
use = egg:swift#slo

[filter:tempurl]
use = egg:swift#tempurl

[filter:formpost]
use = egg:swift#formpost
EOF

cat >/etc/swift/account-server.conf <<EOF
[DEFAULT]
devices = /srv/1/node/
bind_port = 6012
user = pi
log_facility = LOG_LOCAL2
recon_cache_path = /var/cache/swift
eventlet_debug = true
log_level = DEBUG
mount_check = false
disable_fallocate = true

[pipeline:main]
pipeline = recon account-server

[app:account-server]
use = egg:swift#account

[filter:recon]
use = egg:swift#recon

[account-replicator]
vm_test_mode = yes

[account-auditor]

[account-reaper]
EOF

cat >/etc/swift/container-server.conf <<EOF
[DEFAULT]
devices = /srv/1/node/
bind_port = 6011
user = pi
log_facility = LOG_LOCAL2
recon_cache_path = /var/cache/swift
eventlet_debug = true
log_level = DEBUG
mount_check = false
disable_fallocate = true

[pipeline:main]
pipeline = recon container-server

[app:container-server]
use = egg:swift#container

[filter:recon]
use = egg:swift#recon

[container-replicator]
vm_test_mode = yes

[container-updater]

[container-auditor]

[container-sync]
EOF

cat >/etc/swift/object-server.conf <<EOF
[DEFAULT]
devices = /srv/1/node/
bind_port = 6010
user = pi
log_facility = LOG_LOCAL2
recon_cache_path = /var/cache/swift
eventlet_debug = true
log_level = DEBUG
mount_check = false
disable_fallocate = true

[pipeline:main]
pipeline = recon object-server

[app:object-server]
use = egg:swift#object

[filter:recon]
use = egg:swift#recon

[object-replicator]
vm_test_mode = yes

[object-updater]

[object-auditor]
EOF

# when setting up the hash_path_suffix, it is important to make it unique
# and keep it a secret
SUFF=`python -c 'import uuid; print uuid.uuid4().hex'`
cat <<EOF >/etc/swift/swift.conf
[swift-hash]
swift_hash_path_suffix = $SUFF

[swift-constraints]
#max_file_size = 5368709122
# Note: Since the Raspberry Pi has such limited storage space,
# the maximum size of a single object has been set to 500MB.
max_file_size = 524288000
#max_meta_name_length = 128
#max_meta_value_length = 256
#max_meta_count = 90
#max_meta_overall_size = 4096
#max_object_name_length = 1024
#container_listing_limit = 10000
#account_listing_limit = 10000
#max_account_name_length = 256
#max_container_name_length = 256
EOF


cat <<EOF >/home/pi/bin/remakerings
#!/bin/bash

cd /etc/swift

rm -f *.builder *.ring.gz backups/*.builder backups/*.ring.gz

swift-ring-builder object.builder create 8 1 0
swift-ring-builder object.builder add r1z1-127.0.0.1:6010/d1 1
swift-ring-builder object.builder rebalance
swift-ring-builder container.builder create 8 1 0
swift-ring-builder container.builder add r1z1-127.0.0.1:6011/d1 1
swift-ring-builder container.builder rebalance
swift-ring-builder account.builder create 8 1 0
swift-ring-builder account.builder add r1z1-127.0.0.1:6012/d1 1
swift-ring-builder account.builder rebalance
EOF

cat <<EOF >/home/pi/bin/resetswift
#!/bin/bash

swift-init all stop

sudo umount /srv/swift-disk
sudo mkdir -p /srv
sudo truncate -s 1GB /srv/swift-disk
sudo mkfs.xfs -f -i size=512 /srv/swift-disk

sudo mount -a
sudo mkdir -p /mnt/sdb1/1
sudo chown -R pi:pi /mnt/sdb1/*

sudo rm -rf /var/log/swift
sudo mkdir -p /var/log/swift/hourly

sudo mkdir /var/cache/swift
sudo chown -R pi:pi /var/cache/swift

find /var/cache/swift* -type f -name *.recon -exec rm -f {} \;

sudo service rsyslog restart
sudo service memcached restart
EOF

cat <<EOF >/home/pi/bin/startmain
#!/bin/bash

if [ ! -d /var/run/swift ]; then
  sudo mkdir -p /var/run/swift
  sudo chown -R pi:pi /var/run/swift
fi

swift-init main start
EOF

chmod +x /home/pi/bin/*

cat <<EOF

===========================================

Install completed.

You can now call \`resetswift\` and \`startmain\` to clean everything and start
the Swift server processes.

To test, try the following:
export PIIP=<IP address of your Raspberry Pi>
curl -i -H "X-Auth-User: test:tester" -H "X-Auth-Key: testing" \\
   http://\${PIIP}:8080/auth/v1.0/
EOF
