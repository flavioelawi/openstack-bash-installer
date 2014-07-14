#!/bin/bash

#apt update

echo "Controller node script"
echo "input the hostname: "
read $hostname_var
echo hostname_var > /etc/hostname
if [ -e db_installed ]; then
	echo "DB Already configured"
	else
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
	
	echo "Nova DB Password: $password_db_nova " > openstack_db_pwd.txt
	echo "Cinder DB Password: $password_db_cinder " >> openstack_db_pwd.txt
	echo "Glance DB Password: $password_db_glance " >> openstack_db_pwd.txt
	echo "Neutron DB Password: $password_db_neutron " >> openstack_db_pwd.txt 
	echo "Keystone DB Password: $password_db_keystone " >> openstack_db_pwd.txt
	
	echo "Creating Databases for Openstack services"

	mysql -u root -p << EOF
	CREATE DATABASE nova;
	GRANT ALL PRIVILEGES ON nova.* TO "nova"@"localhost" IDENTIFIED BY "$password_db_nova";
	GRANT ALL PRIVILEGES ON nova.* TO "nova"@"%" IDENTIFIED BY "$password_db_nova";
	CREATE DATABASE cinder;
	GRANT ALL PRIVILEGES ON cinder.* TO "cinder"@"localhost" IDENTIFIED BY "$password_db_cinder";
	GRANT ALL PRIVILEGES ON cinder.* TO "cinder"@"%" IDENTIFIED BY "$password_db_cinder";
	CREATE DATABASE glance;
	GRANT ALL PRIVILEGES ON glance.* TO "glance"@"localhost" IDENTIFIED BY 	"$password_db_glance";
	GRANT ALL PRIVILEGES ON glance.* TO "glance"@"%" IDENTIFIED BY "$password_db_glance";
	CREATE DATABASE neutron;
	GRANT ALL PRIVILEGES ON neutron.* TO "neutron"@"localhost" IDENTIFIED BY "$password_db_neutron";
	GRANT ALL PRIVILEGES ON neutron.* TO "neutron"@"%" IDENTIFIED BY "$password_db_neutron";
	CREATE DATABASE keystone;
	GRANT ALL PRIVILEGES ON keystone.* TO "keystone"@"localhost" IDENTIFIED BY "$password_db_keystone";
	GRANT ALL PRIVILEGES ON keystone.* TO "keystone"@"%" IDENTIFIED BY "$password_db_keystone";
	FLUSH PRIVILEGES;
EOF
fi

touch db_installed

echo "Installing Openstack keystone server"

apt install -y keystone python-keystone python-keystoneclient

echo "Configuring Keystone config file"
admin_token_var=$(openssl rand -base64 32)
echo "Admin token password: $admin_token_var" >> openstack_db_pwd.txt
if [ -e /etc/keystone/keystone.conf.bak ]; then
	echo "backup file already exists, probably Keystone is already configured"
	else
	echo "Creating backup config file (Keystone) "
	cp /etc/keystone/keystone.conf /etc/keystone/keystone.conf.bak
	keystone_conf="/etc/keystone/keystone.conf"
	sed -i "s/#admin_token=ADMIN/admin_token=$admin_token_var/g" $keystone_conf
	sed -i "s/connection = sqlite:\/\/\/\/var\/lib\/keystone\/keystone.db/connection = mysql:\/\/keystone:$password_db_keystone@localhost\/keystone/g" $keystone_conf
	keystone-manage db_sync
	service keystone restart
fi

