#!/bin/bash

cfg_parser ()
{
    ini="$(<$1)"                # read the file
    ini="${ini//[/\[}"          # escape [
    ini="${ini//]/\]}"          # escape ]
    IFS=$'\n' && ini=( ${ini} ) # convert to line-array
    ini=( ${ini[*]//;*/} )      # remove comments with ;
    ini=( ${ini[*]/\    =/=} )  # remove tabs before =
    ini=( ${ini[*]/=\   /=} )   # remove tabs be =
    ini=( ${ini[*]/\ =\ /=} )   # remove anything with a space around =
    ini=( ${ini[*]/#\\[/\}$'\n'cfg.section.} ) # set section prefix
    ini=( ${ini[*]/%\\]/ \(} )    # convert text2function (1)
    ini=( ${ini[*]/=/=\( } )    # convert item to array
    ini=( ${ini[*]/%/ \)} )     # close array parenthesis
    ini=( ${ini[*]/%\\ \)/ \\} ) # the multiline trick
    ini=( ${ini[*]/%\( \)/\(\) \{} ) # convert text2function (2)
    ini=( ${ini[*]/%\} \)/\}} ) # remove extra parenthesis
    ini[0]="" # remove first element
    ini[${#ini[*]} + 1]='}'    # add the last brace
    eval "$(echo "${ini[*]}")" # eval the result
}
 
cfg_writer ()
{
    IFS=' '$'\n'
    fun="$(declare -F)"
    fun="${fun//declare -f/}"
    for f in $fun; do
        [ "${f#cfg.section}" == "${f}" ] && continue
        item="$(declare -f ${f})"
        item="${item##*\{}"
        item="${item%\}}"
        item="${item//=*;/}"
        vars="${item//=*/}"
        eval $f
        echo "[${f#cfg.section.}]"
        for var in $vars; do
            echo $var=\"${!var}\"
        done
    done
}

apt update

echo "Controller node script"
echo "input the hostname: "
read $hostname_var
echo hostname_var > /etc/hostname
apt install -y python-mysqldb mysql-server rabbitmq-server
mysql_secure_installation
sed -i "s/127.0.0.1/0.0.0.0/g" /etc/mysql/my.cnf

service mysql restart

password_db_nova=$(openssl rand -base64 32)
password_db_cinder=$(openssl rand -base64 32)
password_db_glance=$(openssl rand -base64 32)
password_db_neutron=$(openssl rand -base64 32)
password_db_keystone=$(openssl rand -base64 32)

echo "Creating DB passwords"

echo "Nova DB Password: " $password_db_nova
echo "Cinder DB Password: " $password_db_cinder
echo "Glance DB Password: " $password_db_glance
echo "Neutron DB Password: " $password_db_neutron
echo "Keystone DB Password: " $password_db_keystone

echo "Creating Databases for Openstack services"

mysql -u root -p <<EOF
CREATE DATABASE nova;
GRANT ALL PRIVILEGES ON nova.* TO "nova"@"localhost" IDENTIFIED BY "$password_db_nova";
GRANT ALL PRIVILEGES ON nova.* TO "nova"@"%" IDENTIFIED BY "$password_db_nova";
CREATE DATABASE cinder;
GRANT ALL PRIVILEGES ON cinder.* TO "cinder"@"localhost" IDENTIFIED BY "$password_db_cinder";
GRANT ALL PRIVILEGES ON cinder.* TO "cinder"@"%" IDENTIFIED BY "$password_db_cinder";
CREATE DATABASE glance;
GRANT ALL PRIVILEGES ON glance.* TO "glance"@"localhost" IDENTIFIED BY "$password_db_glance";
GRANT ALL PRIVILEGES ON glance.* TO "glance"@"%" IDENTIFIED BY "$password_db_glance";
CREATE DATABASE neutron;
GRANT ALL PRIVILEGES ON neutron.* TO "neutron"@"localhost" IDENTIFIED BY "$password_db_neutron";
GRANT ALL PRIVILEGES ON neutron.* TO "neutron"@"%" IDENTIFIED BY "$password_db_neutron";
CREATE DATABASE keystone;
GRANT ALL PRIVILEGES ON keystone.* TO "keystone"@"localhost" IDENTIFIED BY "$password_db_keystone";
GRANT ALL PRIVILEGES ON keystone.* TO "keystone"@"%" IDENTIFIED BY "$password_db_keystone";
FLUSH PRIVILEGES;
EOF

echo "Installing Openstack keystone server"

apt install -y keystone python-keystone python-keystoneclient

echo "Configuring Keystone config file"

cfg.parser "/etc/keystone/keystone.conf"
cfg.section.DEFAULT


