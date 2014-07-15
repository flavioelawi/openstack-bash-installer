#!/bin/bash

openstack_txt_pwd=openstack_pwd.txt
openrc=openrc
adminopenrc=admin-openrc.sh
keystone_conf="/etc/keystone/keystone.conf"
glance_api_conf="/etc/glance/glance-api.conf"
glance_registry_conf="/etc/glance/glance-registry.conf"


# FUNCTIONS

function configure_passwords(){
password_db_nova=$(openssl rand -hex 16)
password_db_cinder=$(openssl rand -hex 16)
password_db_glance=$(openssl rand -hex 16)
password_db_neutron=$(openssl rand -hex 16)
password_db_keystone=$(openssl rand -hex 16)
rabbit_pass=$(openssl rand -hex 16)
admin_token=$(openssl rand -hex 16)
echo "Creating Databases user passwords"
echo "rabbit_pass=$rabbit_pass" >> $openstack_txt_pwd
echo "password_db_nova=$password_db_nova" >> $openstack_txt_pwd
echo "password_db_cinder=$password_db_cinder" >> $openstack_txt_pwd
echo "password_db_glance=$password_db_glance" >> $openstack_txt_pwd
echo "password_db_neutron=$password_db_neutron" >> $openstack_txt_pwd 
echo "password_db_keystone=$password_db_keystone" >> $openstack_txt_pwd
echo "admin_token=$admin_token" >> $openstack_txt_pwd
echo "Insert the admin user password " 
read -s admin_pass
echo "admin_pass=$admin_pass" >> $openstack_txt_pwd
echo "Insert the admin email address "
read admin_email
echo "admin_email=$admin_email" >> $openstack_txt_pwd
#echo "export OS_USERNAME=admin" > openrc
echo "export OS_SERVICE_TOKEN=$admin_token" >> $openrc
#echo "export OS_TENANT_NAME=admin" >> openrc
echo "export OS_SERVICE_ENDPOINT=http://$controller_node:35357/v2.0" >> $openrc
echo "export OS_USERNAME=admin" >> $adminopenrc
echo "export OS_PASSWORD=$admin_pass" >> $adminopenrc
echo "export OS_TENANT_NAME=admin" >> $adminopenrc
echo "export OS_AUTH_URL=http://$controller_node:35357/v2.0" >> $adminopenrc
chmod 700 $openstack_txt_pwd
chmod 700 $adminopenrc
}

function set_passwords(){
source $openstack_txt_pwd
source $openrc
source $adminopenrc
}

function create_db(){
if [ -e db_installed ]; then
echo "DB Already configured"
return
	else
	set_passwords
	echo "A file with the passwords already exists, do you want to overwrite?"
	apt install -y python-mysqldb mysql-server rabbitmq-server
	mysql_secure_installation
	sed -i "s/127.0.0.1/0.0.0.0/g" /etc/mysql/my.cnf
	service mysql restart
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
touch db_installed
fi
return
}

function configure_keystone() {
# KEYSTONE INSTALLATION
	set_passwords
	echo "Installing Openstack keystone server"
	apt install -y keystone python-keystone python-keystoneclient
	echo "Creating backup config file (Keystone) "
	cp $keystone_conf /etc/keystone/keystone.conf.bak	
	echo "Configuring Keystone config file"
	sed -i "s/\#admin_token\=ADMIN/admin_token\=$admin_token/g" $keystone_conf
	sed -i "s/connection\ \=\ sqlite\:\/\/\/\/var\/lib\/keystone\/keystone.db/connection\ \=\ mysql\:\/\/keystone\:$password_db_keystone\@localhost\/keystone/g" $keystone_conf
	sed -i "s/\#rabbit_password\=guest/rabbit_password\=$rabbit_pass/g" $keystone_conf
	rm /var/lib/keystone/keystone.db
	keystone-manage db_sync
	service keystone restart
	# BEGIN KEYSTONE CONFIGURATION
	sleep 5
	keystone user-create --name=admin --pass=$admin_pass --email=$admin_email
	keystone role-create --name=admin
	keystone tenant-create --name=admin --description="Admin Tenant"
	keystone user-role-add --user=admin --tenant=admin --role=admin
	keystone user-role-add --user=admin --role=_member_ --tenant=admin
	keystone tenant-create --name=service --description="Service Tenant"
	keystone service-create --name=keystone --type=identity --description="OpenStack Identity"
	#ENDPOINT CONFIGURATION
	keystone endpoint-create --service-id=$(keystone service-list | awk '/ identity / {print $2}') --publicurl=http://$controller_node:5000/v2.0 --internalurl=http://$controller_node:5000/v2.0 --adminurl=http://$controller_node:35357/v2.0
# END KEYSTONE INSTALLATION
return
}

function  configure_rabbitmq(){
	set_passwords
	apt install -y rabbitmq-server
rabbitmqctl change_password guest $rabbit_pass
return
}

function set_controller(){
echo "Insert the FQDN or IP of the controller node"
read controller_node
}

function configure_glance(){
apt install -y glance python-glanceclient
sed -i "s/connection\ \=\ sqlite\:\/\/\/\/var\/lib\/keystone\/keystone.db/connection\ \=\ mysql\:\/\/keystone\:$password_db_glance\@localhost\/keystone/g" $glance_api_conf

glance-manage db_sync

}

# OPERATIONS MENU
show_menus() {
echo "[0] Set Passwords (IMPORTANT!)"
echo "[1] Configure RabbitMQ Server"
echo "[2] Configure the database for all services (MySQL)"
echo "[3] Configure the Identity Service (Keystone)"
echo "[4] Configure the Image Service (Glance)"
echo "[5] Configure the Block Storage (Cinder)"
echo "[6] Configure the Compute node (Nova)"
echo "[7] Configure the Networking (Neutron)"
echo "[8] Configure the Object Storage (Swift)"
echo "[9] Configure the Orchestration (Heat)"
echo "[10] Configure the Telemetry (Ceilometer)"
echo "[11] Configure the Web Portal (Horizon)"
echo "[12] Set the controller hostname or IP"
echo "[q] Exit"
}
read_options(){
	local choice
	read -p "Enter choice [0 - 10] " choice
	case $choice in
	0) configure_passwords ;;
	1) configure_rabbitmq ;;
	2) create_db ;;
	3) configure_keystone ;;
	4) configure_glance ;;
	5) configure_cinder ;;
	6) configure_nova ;;
	7) configure_neutron ;;
	8) configure_swift ;;
	9) configure_heat ;;
	10) configure_ceilometer ;;
	11) configure_horizon ;;
	12) set_controller ;;
	q) exit 0 ;;
	*) echo "Error: Select a number from the list" ;;
	esac
}
# 
while true
do
	show_menus
	read_options
done



