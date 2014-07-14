#!/bin/bash

openstack_txt_pwd=openstack_pwd.txt
keystone_conf="/etc/keystone/keystone.conf"


# FUNCTIONS

function create_db(){
	apt install -y python-mysqldb mysql-server rabbitmq-server
	if [ $password_exists == 1 ]; then
	echo "A file with the passwords already exists, do you want to overwrite?"
	get_passwords_from_file;
	else
		rabbitmqctl change_password guest $rabbit_pass
		mysql_secure_installation
		sed -i "s/127.0.0.1/0.0.0.0/g" /etc/mysql/my.cnf
		service mysql restart
		echo "Creating Databases for Openstack services"
		touch db_installed
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
}

function configure_keystone() {
	
	echo "Creating backup config file (Keystone) "
	cp $keystone_conf /etc/keystone/keystone.conf.bak
	sed -i "s/#admin_token=ADMIN/admin_token=$admin_token_var/g" $keystone_conf
	sed -i "s/connection\ =\ sqlite:\/\/\/\/var\/lib\/keystone\/keystone.db/connection\ =\ mysql:\/\/keystone:$password_db_keystone\@localhost\/keystone/g" $keystone_conf
	sed -i "s/#rabbit_password=guest/rabbit_password=$rabbit_pass/g" $keystone_conf
	keystone-manage db_sync
	service keystone restart
	# BEGIN KEYSTONE CONFIGURATION
	#echo "export OS_USERNAME=admin" > openrc
	echo "export OS_SERVICE_TOKEN=$admin_token_var" >> openrc
	#echo "export OS_TENANT_NAME=admin" >> openrc
	echo "export OS_SERVICE_ENDPOINT=http://localhost:35357/v2.0" >> openrc
	source openrc
	echo "source openrc" >> .bashrc
	
	keystone user-create --name=admin --pass=$admin_pass --email=$admin_email
	keystone role-create --name=admin
	keystone tenant-create --name=admin --description="Admin Tenant"
	keystone user-role-add --user=admin --tenant=admin --role=admin
	keystone user-role-add --user=admin --role=_member_ --tenant=admin
	keystone tenant-create --name=service --description="Service Tenant"
	keystone service-create --name=keystone --type=identity --description="OpenStack Identity"
	# END KEYSTONE CONFIGURATION
}

function set_passwords() {
	if [ -e openstack_pwd.txt ]; then
	password_exists=1
	source $openstack_txt_pwd
		else 
		password_exists=0
		password_db_nova=$(openssl rand -base64 32)
		password_db_cinder=$(openssl rand -base64 32)
		password_db_glance=$(openssl rand -base64 32)
		password_db_neutron=$(openssl rand -base64 32)
		password_db_keystone=$(openssl rand -base64 32)
		rabbit_pass=$(openssl rand -base64 32)
		echo "Creating Databases user passwords"
		echo "rabbit_pass=$rabbit_pass" > $openstack_txt_pwd
		echo "password_db_nova=$password_db_nova" >> $openstack_txt_pwd
		echo "password_db_cinder=$password_db_cinder" >> $openstack_txt_pwd
		echo "password_db_glance=$password_db_glance" >> $openstack_txt_pwd
		echo "password_db_neutron=$password_db_neutron" >> $openstack_txt_pwd 
		echo "password_db_keystone=$password_db_keystone" >> $openstack_txt_pwd
		echo "Insert the admin user password " 
		read -s admin_pass
		echo "admin_pass=$admin_pass" >> $openstack_txt_pwd
		echo "Insert the admin email address "
		read admin_email
		echo "admin_email=$admin_email" >> $openstack_txt_pwd
	fi
}

# OPERATIONS MENU

echo "[1] Try to start the configuration"
echo "[2] Configure the database"
echo "[3] Configure Keystone"


# NODE ENVIRONMENT CONFIGURATION START

set_passwords

apt update

echo "Controller node script"
echo "input the hostname: "
read hostname_var
echo $hostname_var > /etc/hostname

# MYSQL INSTALLATION

if [ -e db_installed ]; then
	echo "DB Already configured"
	else
		#CALL CREATE_DB Function
		create_db;
fi



# END MYSQL INSTALLATION

# KEYSTONE INSTALLATION

echo "Installing Openstack keystone server"

apt install -y keystone python-keystone python-keystoneclient
if [ $password_exists == 1 ]; then
	echo "A file with the passwords already exists, check your config!"
	else
	echo "Configuring Keystone config file"
	admin_token_var=$(openssl rand -base64 32)
	echo "admin_token_var:$admin_token_var" >> $openstack_txt_pwd
		if [ -e /etc/keystone/keystone.conf.bak ]; then
		echo "backup file already exists, probably Keystone is already configured"
		else
			# call configure_keystone function
			configure_keystone ;
			
		fi
fi
# END KEYSTONE INSTALLATION



