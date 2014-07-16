#!/bin/bash

openstack_db_pass=openstack_db_pass
openrc=openrc
admin_openrc=admin_openrc
admin_user_creds=admin_user_creds
rabbitrc=rabbitrc
glancerc=glancerc
controller_node_file=controller_node_file
keystone_conf="/etc/keystone/keystone.conf"
glance_api_conf="/etc/glance/glance-api.conf"
glance_registry_conf="/etc/glance/glance-registry.conf"

# FUNCTIONS
function generate_first_admin(){
	if [ -e "$admin_user_creds" ]; then
		echo "The $admin_user_creds file already exists, sourcing it. "
		source $admin_user_creds
	else
		configure_openrc
		echo "Insert the admin user password " 
		read -s admin_pass
		echo "admin_pass=$admin_pass" >> $admin_user_creds
		echo "Insert the admin email address "
		read admin_email
		echo "admin_email=$admin_email" >> $admin_user_creds
		chmod 700 $admin_user_creds
		source $admin_user_creds
	fi
}

function configure_admin_openrc(){
	if [ -e "$admin_openrc" ]; then
		echo "The $admin_openrc file already exists, sourcing it. "
		source $admin_openrc
	else
		generate_first_admin
		echo "export OS_USERNAME=admin" >> $admin_openrc
		echo "export OS_PASSWORD=$admin_pass" >> $admin_openrc
		echo "export OS_TENANT_NAME=admin" >> $admin_openrc
		echo "export OS_AUTH_URL=http://$controller_node:35357/v2.0" >> $admin_openrc
		chmod 700 $admin_openrc
		source $admin_openrc
	fi
}

function configure_openrc(){
	if [ -e "$openrc" ]; then
		echo "The $openrc file already exists, sourcing it. "
		source $openrc
	else	
		admin_token=$(openssl rand -hex 16)
		#echo "export OS_USERNAME=admin" > openrc
		echo "export OS_SERVICE_TOKEN=$admin_token" >> $openrc
		#echo "export OS_TENANT_NAME=admin" >> openrc
		echo "export OS_SERVICE_ENDPOINT=http://$controller_node:35357/v2.0" >> $openrc
		chmod 700 $openrc
		source $openrc
	fi
}

function configure_db_passwords(){
	if [ -e "$openstack_db_pass" ]; then
		echo "The $openstack_db_pass file already exists, sourcing it. "
		source $openstack_db_pass
	else
		password_db_nova=$(openssl rand -hex 16)
		password_db_cinder=$(openssl rand -hex 16)
		password_db_glance=$(openssl rand -hex 16)
		password_db_neutron=$(openssl rand -hex 16)
		password_db_keystone=$(openssl rand -hex 16)
		echo "Creating Databases user passwords"
		echo "password_db_nova=$password_db_nova" >> $openstack_db_pass
		echo "password_db_cinder=$password_db_cinder" >> $openstack_db_pass
		echo "password_db_glance=$password_db_glance" >> $openstack_db_pass
		echo "password_db_neutron=$password_db_neutron" >> $openstack_db_pass 
		echo "password_db_keystone=$password_db_keystone" >> $openstack_db_pass
		chmod 700 $openstack_db_pass
		source $openstack_db_pass
	fi
}

function  configure_rabbitmq(){
	if [ -e "$rabbitrc" ]; then
		echo "The $rabbitrc file already exists, sourcing it. "
		source $rabbitrc
	else
		apt install -y rabbitmq-server
		rabbit_pass=$(openssl rand -hex 16)
		rabbitmqctl change_password guest $rabbit_pass
		echo "rabbit_pass=$rabbit_pass" >> $rabbitrc
		chmod 700 $rabbitrc
		source $rabbitrc
	fi
}

function set_controller(){
	if [ -e "$controller_node_file" ]; then
		echo "The $controller_node file already exists, sourcing it. "
		source $controller_node_file
	else
		echo "Insert the FQDN or IP of the controller node"
		read controller_node
		echo "controller_hostname=$controller_node" >> $controller_node_file
		chmod 700 $controller_node_file
		source $controller_node_file
	fi
}

function create_db(){
	if [ -e db_installed ]; then
		echo "DB Already configured"
	else
		configure_db_passwords
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
}

function configure_keystone() {
# KEYSTONE INSTALLATION
	if [ -e keystone_installed ]; then
		echo "Keystone already installed"
	else
		create_db
		configure_rabbitmq
		set_controller
		configure_openrc
		echo "Installing Openstack keystone server"
		apt install -y keystone python-keystone python-keystoneclient
		echo "Creating backup config file (Keystone) "
		cp $keystone_conf /etc/keystone/keystone.conf.bak	
		echo "Configuring Keystone config file"
		sed -i "s/\#admin_token\=ADMIN/admin_token\=$admin_token/g" $keystone_conf
		sed -i "s/connection\ \=\ sqlite\:\/\/\/\/var\/lib\/keystone\/keystone.db/connection\ \=\ mysql\:\/\/keystone\:$password_db_keystone\@$controller_node\/keystone/g" $keystone_conf
		sed -i "s/\#rabbit_password\=guest/rabbit_password\=$rabbit_pass/g" $keystone_conf
		rm /var/lib/keystone/keystone.db
		keystone-manage db_sync
		service keystone restart
		# BEGIN KEYSTONE CONFIGURATION
		sleep 5
		configure_admin_openrc
		keystone user-create --name=admin --pass=$admin_pass --email=$admin_email
		keystone role-create --name=admin
		keystone tenant-create --name=admin --description="Admin Tenant"
		keystone user-role-add --user=admin --tenant=admin --role=admin
		keystone user-role-add --user=admin --role=_member_ --tenant=admin
		keystone tenant-create --name=service --description="Service Tenant"
		keystone service-create --name=keystone --type=identity --description="OpenStack Identity"
		#ENDPOINT CONFIGURATION
		keystone endpoint-create --service-id=$(keystone service-list | awk '/ identity / {print $2}') --publicurl=http://$controller_node:5000/v2.0 --internalurl=http://$controller_node:5000/v2.0 --adminurl=http://$controller_node:35357/v2.0
		touch keystone_installed
		# END KEYSTONE INSTALLATION
	fi
return
}

function configure_glance(){
	if [ -e "$glancerc" ]; then
		echo "The $glancerc file already exists, sourcing it. "
		source $glancerc
	else
		glance_pass=$(openssl rand -hex 16)
		echo "glance_pass=$glance_pass" >> $glancerc
		chmod 700 $glancerc
		source $glancerc
	fi
}

function install_glance(){
	if [ -e glance_installed ]; then
		echo "Glance already installed"
	else
		set_controller
		configure_admin_openrc
		configure_glance
		create_db
		configure_rabbitmq
		apt install -y glance python-glanceclient
		keystone user-create --name=glance --pass=$glance_pass --email=glance@example.com
		# PARSE AND CHANGE API FILE
		sed -i "s/sqlite_db\ \=\ \/var\/lib\/glance\/glance.sqlite/connection\ \=\ mysql\:\/\/glance\:$password_db_glance\@$controller_node\/glance/g" $glance_api_conf
		sed -i "s/\#rabbit_password\=guest/rabbit_password\=$rabbit_pass/g" $glance_api_conf
		sed -i "s/auth_host\ \=\ 127.0.0.1/auth_host\ \=\ $controller_node/g" $glance_api_conf		
		sed -i "s/\%SERVICE_TENANT_NAME\%/admin/g" $glance_api_conf
		sed -i "s/\%SERVICE_USER\%/glance/g" $glance_api_conf
		sed -i "s/\%SERVICE_PASSWORD\%/$glance_pass/g" $glance_api_conf
		sed -i "s/\#flavor\=/flavor\=keystone/g" $glance_api_conf
		# PARSE AND CHANGE REGISTRY FILE
		sed -i "s/sqlite_db\ \=\ \/var\/lib\/glance\/glance.sqlite/connection\ \=\ mysql\:\/\/glance\:$password_db_glance\@$controller_node\/glance/g" $glance_registry_conf
		sed -i "s/\#rabbit_password\=guest/rabbit_password\=$rabbit_pass/g" $glance_registry_conf
		sed -i "s/auth_host\ \=\ 127.0.0.1/auth_host\ \=\ $controller_node/g" $glance_registry_conf		
		sed -i "s/\%SERVICE_TENANT_NAME\%/admin/g" $glance_registry_conf
		sed -i "s/\%SERVICE_USER\%/glance/g" $glance_registry_conf
		sed -i "s/\%SERVICE_PASSWORD\%/$glance_pass/g" $glance_registry_conf
		sed -i "s/\#flavor\=/flavor\=keystone/g" $glance_registry_conf
		glance-manage db_sync
		service glance-registry restart
		service glance-api restart
		sleep 5
		keystone service-create --name=glance --type=image --description="OpenStack Image Service"
		sleep 5
		keystone endpoint-create --service-id=$(keystone service-list | awk '/ image / {print $2}') --publicurl=http://$controller_node:9292 --internalurl=http://$controller_node:9292 --adminurl=http://$controller_node:9292
		touch glance_installed
	fi
return
}

function configure_horizon(){
	apt install -y apache2 memcached libapache2-mod-wsgi openstack-dashboard
	apt-get remove --purge openstack-dashboard-ubuntu-theme
}

# OPERATIONS MENU
show_menus() {
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
	echo "[11] Configure the Dashboard (Horizon)"
	echo "[q] Exit"
}

read_options(){
	local choice
	read -p "Enter choice [0 - 11] " choice
	case $choice in
	1) configure_rabbitmq ;;
	2) create_db ;;
	3) configure_keystone ;;
	4) install_glance ;;
	5) configure_cinder ;;
	6) configure_nova ;;
	7) configure_neutron ;;
	8) configure_swift ;;
	9) configure_heat ;;
	10) configure_ceilometer ;;
	11) configure_horizon ;;
	q) exit 0 ;;
	*) echo "Error: Select a number from the list" ;;
	esac
}

while true
do
	show_menus
	read_options
done



