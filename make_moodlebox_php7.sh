#!/usr/bin/env bash

# Uncomment for debugging
#exec 1> >(logger -s -t $(basename $0)) 2>&1

# This script MUST be run as root
[[ $EUID -ne 0 ]] && { echo "This script must be run as root"; exit 1; }

# e.g. it could be launched from the root account like this
# curl -L https://raw.githubusercontent.com/martignoni/make-moodlebox/master/make_moodlebox.sh | sudo bash

VERSION="1.4"
GENERICPASSWORD="Moodlebox4$"
export DEBIAN_FRONTEND="noninteractive"
export APT_LISTCHANGES_FRONTEND="none"

# http://unix.stackexchange.com/questions/145294/how-to-continue-a-script-after-it-reboots-the-machine
before_reboot(){
    # Script start!
    clear
    sync

    cat << "EOF" > /etc/init.d/makemoodlebox
#! /bin/sh
### BEGIN INIT INFO
# Provides:          makemoodlebox
# Required-Start:    $local_fs $remote_fs $network $syslog
# Required-Stop:     $local_fs $remote_fs $network $syslog
# Default-Start:     3 4 5
# Default-Stop:
# Short-Description: Execute the makemoodlebox command.
# Description:
### END INIT INFO

PATH=/sbin:/usr/sbin:/bin:/usr/bin

case "$1" in
    start)
        curl -L https://raw.githubusercontent.com/martignoni/make-moodlebox/master/make_moodlebox.sh | bash
        #bash /root/make_moodlebox.sh
        ;;
    *)
        echo "Usage: $0 start" >&2
        exit 3
        ;;
esac
EOF

    chmod a+x /etc/init.d/makemoodlebox

    cat << "EOF" > /etc/init.d/resize2fs_once
#!/bin/sh
### BEGIN INIT INFO
# Provides:          resize2fs_once
# Required-Start:
# Required-Stop:
# Default-Start: 3
# Default-Stop:
# Short-Description: Resize the root filesystem to fill partition
# Description:
### END INIT INFO
. /lib/lsb/init-functions
case "$1" in
  start)
    log_daemon_msg "Starting resize2fs_once"
    ROOT_DEV=`grep -Eo 'root=[[:graph:]]+' /proc/cmdline | cut -d '=' -f 2-` &&
    resize2fs $ROOT_DEV &&
    update-rc.d resize2fs_once remove &&
    rm /etc/init.d/resize2fs_once &&
    log_end_msg $?
    ;;
  *)
    echo "Usage: $0 start" >&2
    exit 3
    ;;
esac
EOF

    chmod a+x /etc/init.d/resize2fs_once

    echo -e "\e[96mMake MoodleBox"
    echo -e "Author: Nicolas Martignoni"
    echo -e "Version: $VERSION\n"

    # Configure important settings (done via raspi-config when GUI used)
    echo -e "\e[93mConfiguring locale...\e[97m"
    ## Change locale
    # Comment all uncommented lines, then uncomment line fr_FR.UTF-8 in /etc/locale.gen
    sed -i "/^#/! {/./ s/^#*/# /}" /etc/locale.gen
    sed -i "/fr_FR.UTF-8/c\fr_FR.UTF-8 UTF-8" /etc/locale.gen
    dpkg-reconfigure -f noninteractive locales
    export LANG=fr_FR.UTF-8
    update-locale LANG=fr_FR.UTF-8
    echo -e "\e[93mConfiguring timezone...\e[97m"
    ## Change timezone
    echo "Europe/Paris" > /etc/timezone
    dpkg-reconfigure -f noninteractive tzdata
    echo -e "\e[93mConfiguring Wi-Fi country...\e[97m"
    ## Change WiFi country
    COUNTRY=CH
    if grep -q "^country=" /etc/wpa_supplicant/wpa_supplicant.conf ; then
        sed -i "s/^country=.*/country=$COUNTRY/g" /etc/wpa_supplicant/wpa_supplicant.conf
    else
        sed -i "1i country=$COUNTRY" /etc/wpa_supplicant/wpa_supplicant.conf
    fi
    echo -e "\e[93mChanging hostname...\e[97m"
    ## Change hostname
    CURRENT_HOSTNAME=`cat /etc/hostname | tr -d " \t\n\r"`
    NEW_HOSTNAME=moodlebox
    echo $NEW_HOSTNAME > /etc/hostname
    sed -i "s/127.0.1.1.*$CURRENT_HOSTNAME/10.0.0.1\t$NEW_HOSTNAME/g" /etc/hosts

    # Rename default user from "pi" to "moodlebox"
    # http://unixetc.co.uk/2016/01/07/how-to-rename-the-default-raspberry-pi-user/
    echo -e "\e[93mRenaming default user to \"moodlebox\"...\e[97m"
    cd /etc
    # tar -czf /home/pi/authfiles.tgz passwd group shadow gshadow sudoers sudoers.d/* systemd/system/autologin@.service
    # sed -i.$(date +'%y%m%d_%H%M%S') 's/\bpi\b/moodlebox/g' passwd group shadow gshadow sudoers sudoers.d/* systemd/system/autologin@.service
    sed -i 's/\bpi\b/moodlebox/g' passwd group shadow gshadow sudoers sudoers.d/* systemd/system/autologin@.service
    mv /etc/sudoers.d/010_pi-nopasswd /etc/sudoers.d/010_moodlebox-nopasswd
    mv /home/pi /home/moodlebox
    ## Change user password
    echo "moodlebox:$GENERICPASSWORD" | chpasswd

    ## Remove logging to /dev/xconsole from the default rsyslog configuration
    # https://anonscm.debian.org/cgit/collab-maint/rsyslog.git/commit/?id=67bc8e5326b0d3564c7e2153dede25f9690e6839
    # https://blog.dantup.com/2016/04/removing-rsyslog-spam-on-raspberry-pi-raspbian-jessie/
    sed -i '/# The named pipe \/dev\/xconsole/,$d' /etc/rsyslog.conf
    systemctl restart rsyslog

    ## Some bash configurations for default account
    cat << "EOF" >> /home/moodlebox/.bashrc

alias ll='ls -la'

# Assign arrow keys to history search in bash
bind '"\e[A":history-search-backward'
bind '"\e[B":history-search-forward'
# TAB cycles through the list of partial matches
bind 'TAB:menu-complete'
EOF

    # Update system to latest stable release
    echo -e "\e[93mUpdating system to latest stable release...\e[97m"
    apt-get update -y && apt-get dist-upgrade -y
    ### We have to reboot here, and continue afterwards
}

after_reboot(){
    # mariadb-server preseed selections (http://dba.stackexchange.com/questions/59317/install-mariadb-10-on-ubuntu-without-prompt-and-no-root-password)
    debconf-set-selections <<< "mariadb-server mysql-server/root_password password $GENERICPASSWORD"
    debconf-set-selections <<< "mariadb-server mysql-server/root_password_again password $GENERICPASSWORD"

    # mysql-server preseed selections (https://serversforhackers.com/video/installing-mysql-with-debconf)
    # debconf-set-selections <<< "mysql-server mysql-server/root_password password $GENERICPASSWORD"
    # debconf-set-selections <<< "mysql-server mysql-server/root_password_again password $GENERICPASSWORD"

    # phpmyadmin preseed selections
    debconf-set-selections <<< "phpmyadmin phpmyadmin/mysql/admin-pass password $GENERICPASSWORD"
    debconf-set-selections <<< "phpmyadmin phpmyadmin/mysql/app-pass password $GENERICPASSWORD"
    debconf-set-selections <<< "phpmyadmin phpmyadmin/app-password-confirm password $GENERICPASSWORD"
    debconf-set-selections <<< "phpmyadmin phpmyadmin/reconfigure-webserver multiselect none"
    debconf-set-selections <<< "phpmyadmin phpmyadmin/dbconfig-install boolean true"

    ## Add stretch to sources.list
    echo "deb http://mirrordirector.raspbian.org/raspbian/ stretch main contrib non-free rpi" >> /etc/apt/sources.list

    # use jessie packages by default
    cat << "EOF" >> /etc/apt/preferences
Package: *
Pin: release n=jessie
Pin-Priority: 600
EOF

    sudo apt-get update -y

    ## Install all packages needed for the whole process
    echo -e "\e[93mPackages installation...\e[97m"
    apt-get install -y hostapd dnsmasq git usbmount incron mariadb-server
    echo root > /etc/incron.allow
    # install nginx 1.10 and php 7.0
    apt-get install -y -t stretch nginx php7.0-fpm php7.0-cli php7.0-xmlrpc php7.0-curl php7.0-gd php7.0-intl php7.0-mysql
    apt-get install -y -t stretch phpmyadmin

    ## Access point and network configuration: edit configuration files
    echo -e "\e[93mAccess point and network configuration...\e[97m"
    # 1. /etc/dhcpcd.conf
    cat << "EOF" >> /etc/dhcpcd.conf

denyinterfaces wlan0
EOF

    # 2. /etc/network/interfaces
    cat << "EOF" > /etc/network/interfaces
# interfaces(5) file used by ifup(8) and ifdown(8)

# Include files from /etc/network/interfaces.d:
source-directory /etc/network/interfaces.d

auto lo
iface lo inet loopback

iface eth0 inet manual

allow-hotplug wlan0
iface wlan0 inet static
    address 10.0.0.1
    netmask 255.255.255.0
    network 10.0.0.0
    broadcast 10.0.0.255
#    wpa-conf /etc/wpa_supplicant/wpa_supplicant.conf

allow-hotplug wlan1
iface wlan1 inet manual
    wpa-conf /etc/wpa_supplicant/wpa_supplicant.conf
EOF

    # 3. /etc/hostapd/hostapd.conf
    cat << "EOF" > /etc/hostapd/hostapd.conf
# Set country code
country_code=CH
# Name of the Wi-Fi interface
interface=wlan0
# Use the nl80211 driver
driver=nl80211
# Wi-Fi network name
ssid=MoodleBox
# Use the 2.4GHz band
hw_mode=g
# Use channel 11
channel=11
# Enable 802.11n
ieee80211n=1
# Enable WMM
wmm_enabled=1
# Enable 40 MHz channels with short guard interval for 20 Mhz
ht_capab=[HT40][SHORT-GI-20][DSSS_CCK-40]
# Accept all MAC addresses
macaddr_acl=0
# Use WPA authentication
auth_algs=1
# Use WPA2
wpa=2
# Use a pre-shared key
wpa_key_mgmt=WPA-PSK
# The network passphrase
wpa_passphrase=moodlebox
# Use AES, instead of TKIP
rsn_pairwise=CCMP
# Enable hostapd_cli
ctrl_interface=/var/run/hostapd
ctrl_interface_group=0
EOF

    sed -i '/#DAEMON_CONF/c\DAEMON_CONF="/etc/hostapd/hostapd.conf"' /etc/default/hostapd

    # 4. /etc/dnsmasq.conf
    cat << "EOF" > /etc/dnsmasq.conf
interface=wlan0             # Use interface wlan0
listen-address=127.0.0.1    # Explicitly specify the address to listen on
listen-address=10.0.0.1     # Explicitly specify the address to listen on
bind-interfaces             # Make sure we aren't sending things elsewhere
server=209.244.0.3          # Forward DNS requests to Level3 DNS
server=209.244.0.4          # Forward DNS requests to Level3 DNS
domain-needed               # Don't forward short names
bogus-priv                  # Don't forward addresses in the non-routed spaces
domain=home                 # Set private domain name to 'home'
local=/home/                # Don't forward queries for private domain 'home'
expand-hosts                # Add private domain name to hostnames
dhcp-range=wifi,10.0.0.100,10.0.0.199,255.255.255.0,12h # Assign IP addresses with 12h lease, subnet name 'wifi'
dhcp-option=wifi,6,10.0.0.1 # Set DNS server for subnet wifi
# log-facility=/var/log/dnsmasq.log # Enable log
EOF

    # 5. /etc/sysctl.conf
    sed -i '/#net.ipv4.ip_forward/c\net.ipv4.ip_forward=1' /etc/sysctl.conf

    # 6. /etc/iptables.ipv4.nat
    iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
    iptables -A FORWARD -i eth0 -o wlan0 -m state --state RELATED,ESTABLISHED -j ACCEPT
    iptables -A FORWARD -i wlan0 -o eth0 -j ACCEPT
    sh -c "iptables-save > /etc/iptables.ipv4.nat"
    sh -c "echo 1 > /proc/sys/net/ipv4/ip_forward"

    # 7. /lib/dhcpcd/dhcpcd-hooks/70-ipv4-nat
    cat << "EOF" > /lib/dhcpcd/dhcpcd-hooks/70-ipv4-nat
iptables-restore < /etc/iptables.ipv4.nat
EOF

    # 8. /etc/avahi/services/moodlebox.service (Advertise mDNS services)
    cat << "EOF" > /etc/avahi/services/moodlebox.service
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">%h</name>
  <service>
    <type>_device-info._tcp</type>
    <port>0</port>
    <txt-record>model=MoodleBox</txt-record>
  </service>
  <service>
    <type>_ssh._tcp</type>
    <port>22</port>
  </service>
  <service>
    <type>_sftp-ssh._tcp</type>
    <port>22</port>
  </service>
  <service>
    <type>_http._tcp</type>
    <port>80</port>
  </service>
</service-group>
EOF

    ## Edit web server configuration
    echo -e "\e[93mWebserver (nginx) configuration...\e[97m"
    cat << "EOF" > /etc/nginx/sites-available/default
# Default server configuration
#
server {
  listen 80 default_server;
  listen [::]:80 default_server;

  root /var/www/html;

  index index.php index.html index.htm index.nginx-debian.html;

  server_name moodlebox;

  location / {
    try_files $uri $uri/ =404;
  }

  location /dataroot/ {
    internal;
    alias /var/www/moodledata/;
  }

  location ~ [^/]\.php(/|$) {
    include fastcgi_params;
    fastcgi_split_path_info	^(.+\.php)(/.+)$;
    fastcgi_read_timeout	300;
    fastcgi_pass	unix:/var/run/php/php7.0-fpm.sock;
    fastcgi_index	index.php;
    fastcgi_param	PATH_INFO	$fastcgi_path_info;
    fastcgi_param	SCRIPT_FILENAME	$document_root$fastcgi_script_name;
    fastcgi_param	PHP_VALUE	"max_execution_time=300\n upload_max_filesize=50M\n post_max_size=50M";
    client_max_body_size	50M;
  }

}
EOF

    ## Create database for Moodle and configure MySQL vars
    echo -e "\e[93mMySQL and Moodle database configuration...\e[97m"
    mysql -u root -p$GENERICPASSWORD -t << STOP
create database moodle;
grant all on moodle.* to 'root'@'localhost' identified by '$GENERICPASSWORD';
\q
STOP

    sed -i '/table_cache/c\table_cache             = 512' /etc/mysql/my.cnf
    sed -i '/table_cache/i table_definition_cache  = 512' /etc/mysql/my.cnf
    sed -i '/max_connections/c\max_connections         = 100' /etc/mysql/my.cnf
    sed -i '/query_cache_size/c\query_cache_size        = 16M' /etc/mysql/my.cnf
    sed -i '/query_cache_size/i query_cache_type        = 0' /etc/mysql/my.cnf

    ## Download Moodle via git and create all needed directories, with adequate permissions
    echo -e "\e[93mDownloading Moodle 3.2.x via Git and directories configuration...\e[97m"
    cd /var/www/
    rm -r html
    git clone --depth=1 -b MOODLE_32_STABLE git://git.moodle.org/moodle.git html
    mkdir /var/www/moodledata
    mkdir -p /var/www/moodledata/repository
    chown -R www-data:www-data /var/www/html /var/www/moodledata/

    mkdir -p /home/moodlebox/files
    chown -R moodlebox:www-data /home/moodlebox/files
    chmod g+s /home/moodlebox/files
    ln -s /home/moodlebox/files /var/www/moodledata/repository
    ln -s /media/usb /var/www/moodledata/repository

    ln -s /usr/share/phpmyadmin /var/www/html/phpmyadmin

    ## Configure RAM disk for Moodle cache
    mkdir -p /var/cache/moodle
    mkdir -p /var/cache/moodle-cache-backup
    chown www-data:www-data /var/cache/moodle

    cat << "EOF" >> /etc/fstab
tmpfs /var/cache/moodle tmpfs size=64M,mode=775,uid=www-data,gid=www-data 0 0
tmpfs /var/www/moodledata/temp tmpfs size=64M,mode=775,uid=www-data,gid=www-data 0 0
tmpfs /var/www/moodledata/sessions tmpfs size=32M,mode=775,uid=www-data,gid=www-data 0 0
EOF

    ## Install Moodle via cli
    echo -e "\e[93mMoodle installation (via CLI)...\e[97m"
    /usr/bin/php "/var/www/html/admin/cli/install.php" \
      --lang=fr \
      --wwwroot="http://moodlebox.home" \
      --dataroot="/var/www/moodledata" \
      --dbtype="mariadb" \
      --dbname="moodle" \
      --prefix="mdl_" \
      --dbuser="root" \
      --dbpass="$GENERICPASSWORD" \
      --fullname="MoodleBox" \
      --shortname="MoodleBox" \
      --adminuser=admin \
      --adminpass="$GENERICPASSWORD" \
      --non-interactive \
      --agree-license
    sed -i "/$CFG->directorypermissions/i \$CFG->xsendfile = 'X-Accel-Redirect';\n\$CFG->xsendfilealiases = array ('/dataroot/' => \$CFG->dataroot);\n" /var/www/html/config.php
    chown www-data:www-data /var/www/html/config.php
    /usr/bin/php /var/www/html/admin/cli/mysql_compressed_rows.php -f

    ## Install MoodleBox Admin Moodle plugin
    echo -e "\e[93mMoodleBox plugin installation (via CLI)...\e[97m"
    cd /var/www/html/admin/tool/
    git clone https://github.com/martignoni/moodlebox-plugin.git moodlebox
    cd /var/www/html/admin/tool/moodlebox
    touch .reboot-server; touch .shutdown-server; touch .set-server-datetime; touch .newpassword; touch .wifipassword
    chown -R www-data:www-data /var/www/html/admin/tool/moodlebox

    /usr/bin/php "/var/www/html/admin/cli/upgrade.php" --non-interactive

    # Cron and incron jobs configuration
    echo -e "\e[93mCron and incron jobs configuration...\e[97m"
    ## Configure incron jobs (for restart/shutdown from web interface)
    (incrontab -l -u root 2>/dev/null; echo "/var/www/html/admin/tool/moodlebox/.reboot-server IN_CLOSE_WRITE /sbin/shutdown -r now") | incrontab -
    (incrontab -l -u root 2>/dev/null; echo "/var/www/html/admin/tool/moodlebox/.shutdown-server IN_CLOSE_WRITE /sbin/shutdown -h now") | incrontab -
    (incrontab -l -u root 2>/dev/null; echo "/var/www/html/admin/tool/moodlebox/.set-server-datetime IN_MODIFY /bin/bash /var/www/html/admin/tool/moodlebox/.set-server-datetime") | incrontab -
    (incrontab -l -u root 2>/dev/null; echo "/var/www/html/admin/tool/moodlebox/.newpassword IN_CLOSE_WRITE /bin/bash /var/www/html/admin/tool/moodlebox/bin/changepassword.sh") | incrontab -
    (incrontab -l -u root 2>/dev/null; echo "/var/www/html/admin/tool/moodlebox/.wifipassword IN_CLOSE_WRITE /bin/bash /var/www/html/admin/tool/moodlebox/bin/setwifipassword.sh") | incrontab -

    ## Configure cron jobs
    (crontab -l -u root 2>/dev/null; echo "*/3 * * * * nice -n 10 ionice -c2 /usr/bin/php /var/www/html/admin/cli/cron.php") | crontab -
    (crontab -l -u root 2>/dev/null; echo "*/20 * * * * rsync -a --delete /var/cache/moodle/ /var/cache/moodle-cache-backup/") | crontab -
    (crontab -l -u root 2>/dev/null; echo "@reboot cp -Rpf /var/cache/moodle-cache-backup/* /var/cache/moodle/") | crontab -

    ## Cleanup tasks
    echo -e "\e[93mCleaning up...\e[97m"
    rm -rf /var/www/moodledata/cache/*
    rm -rf /var/www/moodledata/localcache/*
    rm -rf /var/www/moodledata/temp/*
    rm -rf /var/www/moodledata/trashdir/*
    rm -rf /var/www/moodledata/sessions/*
    rm -rf /var/cache/moodle/*
    rm -rf /var/cache/moodle-cache-backup/*
    mysql -u root -p$GENERICPASSWORD moodle -e "truncate table moodle.mdl_logstore_standard_log"
    mysql -u root -p$GENERICPASSWORD moodle -e "truncate table moodle.mdl_config_log"
    apt-get clean
    rm -rf /var/cache/debconf/*
    rm -rf /tmp/*
    rm -rf /var/tmp/*
    rm -f ~/.mysql_history
    rm -f ~/.nano_history
    rm -f ~/.bash_history
    sudo bash -c 'for logs in `find /var/log -type f`; do > $logs; done'
    rm -rf /root/.ssh
    truncate -s 0 /root/.bash_history
    systemctl stop dnsmasq
    truncate -s 0 /var/lib/misc/dnsmasq.leases
    apt-get --purge autoremove
}

if [ -f /root/rebooting-for-secondstep ]; then
    after_reboot
    rm /root/rebooting-for-secondstep
    rm /etc/init.d/makemoodlebox
    update-rc.d makemoodlebox remove
    reboot
else
    before_reboot
    touch /root/rebooting-for-secondstep
    update-rc.d makemoodlebox defaults
    reboot
fi
## The end