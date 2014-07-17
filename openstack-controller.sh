#!/bin/bash

mkdir rcfiles
mkdir confbak
openstack_db_pass=rcfiles/openstack_db_pass
openrc=rcfiles/openrc
admin_openrc=rcfiles/admin_openrc
admin_user_creds=rcfiles/admin_user_creds
rabbitrc=rcfiles/rabbitrc
glancerc=rcfiles/glancerc
cinderrc=rcfiles/cinderrc
novarc=rcfiles/novarc
controller_node_file=rcfiles/controller_node_file
keystone_conf="/etc/keystone/keystone.conf"
glance_api_conf="/etc/glance/glance-api.conf"
glance_registry_conf="/etc/glance/glance-registry.conf"
cinder_conf="/etc/cinder/cinder.conf"
nova_conf="/etc/nova/nova.conf"
nova_compute_conf="/etc/nova/nova-compute.conf"
statoverride="/etc/kernel/postinst.d/statoverride"

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
		CREATE DATABASE heat;
		GRANT ALL PRIVILEGES ON heat.* TO "heat"@"localhost" IDENTIFIED BY "password_db_heat";
		GRANT ALL PRIVILEGES ON heat.* TO "heat"@"%" IDENTIFIED BY "password_db_heat";
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
		cp $keystone_conf "confbak/keystone.conf.$(date +%F_%R)"	
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

function configure_glancerc(){
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

function configure_cinderrc(){
	if [ -e "$cinderrc" ]; then
		echo "The $cinderrc file already exists, sourcing it. "
		source $cinderrc
	else
		cinder_pass=$(openssl rand -hex 16)
		echo "cinder_pass=$cinder_pass" >> $cinderrc
		chmod 700 $cinderrc
		source $cinderrc
	fi
}

function install_glance(){
	if [ -e glance_installed ]; then
		echo "Glance already installed"
	else
		set_controller
		configure_admin_openrc
		configure_glancerc
		create_db
		configure_rabbitmq
		apt install -y glance python-glanceclient
		keystone user-create --name=glance --pass=$glance_pass --email=glance@example.com
		cp $glance_api_conf "confbak/glance-api.conf.$(date +%F_%R)"
		cp $glance_registry_conf "confbak/glance-registry.conf.$(date +%F_%R)"
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
	apt-get remove --purge -y openstack-dashboard-ubuntu-theme
}

function configure_cinder_controller(){
	if [ -e cinder_controller_installed ]; then
		echo "Cinder already installed"
	else
		apt install -y cinder-api cinder-scheduler
		set_controller
		cp $cinder_conf "confbak/cinder.conf.$(date +%F_%R)"
		configure_rabbitmq
		echo "rpc_backend = cinder.openstack.common.rpc.impl_kombu" >> $cinder_conf
		echo "rabbit_host = $controller_node" >> $cinder_conf
		echo "rabbit_port = 5672" >> $cinder_conf
		echo "rabbit_userid = guest" >> $cinder_conf
		echo "rabbit_password = $rabbit_pass" >> $cinder_conf
		echo "[database]" >> $cinder_conf
		configure_db_passwords
		echo "connection = mysql://cinder:$password_db_cinder@$controller_node/cinder" >> $cinder_conf
		cinder-manage db sync
		configure_cinderrc
		keystone user-create --name=cinder --pass=$cinder_pass --email=cinder@example.com
		keystone user-role-add --user=cinder --tenant=service --role=admin
		echo "[keystone_authtoken]" >> $cinder_conf
		echo "auth_uri = http://$controller_node:5000" >> $cinder_conf
		echo "auth_host = $controller_node" >> $cinder_conf
		echo "auth_port = 35357" >> $cinder_conf
		echo "auth_protocol = http" >> $cinder_conf
		echo "admin_tenant_name = service" >> $cinder_conf
		echo "admin_user = cinder" >> $cinder_conf
		echo "admin_password = $cinder_pass" >> $cinder_conf
		configure_admin_openrc
		keystone service-create --name=cinder --type=volume --description="OpenStack Block Storage"
		keystone endpoint-create --service-id=$(keystone service-list | awk '/ volume / {print $2}') --publicurl=http://$controller_node:8776/v1/%\(tenant_id\)s --internalurl=http://$controller_node:8776/v1/%\(tenant_id\)s --adminurl=http://$controller_node:8776/v1/%\(tenant_id\)s
		keystone service-create --name=cinderv2 --type=volumev2 --description="OpenStack Block Storage v2"
		keystone endpoint-create --service-id=$(keystone service-list | awk '/ volumev2 / {print $2}') --publicurl=http://$controller_node:8776/v2/%\(tenant_id\)s --internalurl=http://$controller_node:8776/v2/%\(tenant_id\)s --adminurl=http://$controller_node:8776/v2/%\(tenant_id\)s
		service cinder-scheduler restart
		service cinder-api restart
		touch cinder_controller_installed
	fi
}
function configure_cinder_service(){
	apt install -y cinder-volume
}

function configure_novarc(){
	if [ -e "$novarc" ]; then
		echo "The $novarc file already exists, sourcing it. "
		source $novarc
	else
		nova_pass=$(openssl rand -hex 16)
		echo "nova_pass=$nova_pass" >> $novarc
		chmod 700 $novarc
		source $novarc
	fi
}

function configure_nova_generic(){
	if [ -e nova_generic_installed ]; then
		echo "Nova Controller already installed"
	else
		configure_novarc
		configure_rabbitmq
		configure_admin_openrc
		set_controller
		echo "rpc_backend = rabbit" >> $nova_conf
		echo "rabbit_host = $controller_node" >> $nova_conf
		echo "rabbit_port = 5672" >> $nova_conf
		echo "rabbit_userid = guest" >> $nova_conf
		echo "rabbit_password = $rabbit_pass" >> $nova_conf
		echo "my_ip = 0.0.0.0" >> $nova_conf
		echo "vncserver_listen = 0.0.0.0" >> $nova_conf
		echo "vncserver_proxyclient_address = 0.0.0.0" >> $nova_conf
		echo "novncproxy_base_url = http://$controller_node:6080/vnc_auto.html" >> $nova_conf
		echo "glance_host = $controller_node" >> $nova_conf
		echo "auth_strategy = keystone" >> $nova_conf
		rm /var/lib/nova/nova.sqlite
		create_db
		echo "[database]" >> $nova_conf
		echo "connection = mysql://nova:$password_db_nova@$controller_node/nova" >> $nova_conf
		echo "[keystone_authtoken]" >> $nova_conf
		echo "auth_uri = http://$controller_node:5000" >> $nova_conf
		echo "auth_host = $controller_node" >> $nova_conf
		echo "auth_port = 35357" >> $nova_conf
		echo "auth_protocol = http" >> $nova_conf
		echo "admin_tenant_name = service" >> $nova_conf
		echo "admin_user = nova" >> $nova_conf
		echo "admin_password = $nova_pass" >> $nova_conf
		touch nova_generic_installed
	fi
}

function configure_nova_controller(){
	if [ -e nova_controller_installed ]; then
		echo "Nova Controller already installed"
	else	
		apt install -y nova-api nova-cert nova-conductor nova-consoleauth nova-novncproxy nova-scheduler python-novaclient
		cp $nova_conf "confbak/nova.conf.$(date +%F_%R)"
		configure_nova_generic
		keystone user-create --name=nova --pass=$nova_pass --email=nova@example.com
		keystone user-role-add --user=nova --tenant=service --role=admin
		keystone service-create --name=nova --type=compute --description="OpenStack Compute"
		keystone endpoint-create --service-id=$(keystone service-list | awk '/ compute / {print $2}') --publicurl=http://$controller_node:8774/v2/%\(tenant_id\)s --internalurl=http://$controller_node:8774/v2/%\(tenant_id\)s --adminurl=http://$controller_node:8774/v2/%\(tenant_id\)s
		nova-manage db sync
		service nova-api restart
		service nova-cert restart
		service nova-consoleauth restart
		service nova-scheduler restart
		service nova-conductor restart
		service nova-novncproxy restart
		touch nova_controller_installed	
	fi
}

function configure_nova_compute(){
	if [ -e nova_compute_installed ]; then
		echo "Nova Compute already installed"
	else	
		apt install -y nova-compute-kvm python-guestfs python-mysqldb
		cp $nova_compute_conf "confbak/nova-compute.conf.$(date +%F_%R)"
		cp $nova_conf "confbak/nova.conf.$(date +%F_%R)"
		configure_nova_generic
		dpkg-statoverride  --update --add root root 0644 /boot/vmlinuz-$(uname -r)
		echo "#!/bin/sh" >> $statoverride
		echo "version="$1"" >> $statoverride
		echo "# passing the kernel version is required" >> $statoverride
		echo "[ -z "${version}" ] && exit 0" >> $statoverride
		echo "dpkg-statoverride --update --add root root 0644 /boot/vmlinuz-${version}" >> $statoverride
		chmod +x $statoverride
		touch nova_compute_installed
		if [ $(egrep -c '(vmx|svm)' /proc/cpuinfo) -eq 0 ]; then
			echo "WARNING KVM ACCELERATION NOT ENABLED ON THIS HOST"
			sed -i "s/virt_type\=kvm/virt_type\=qemu/g" $nova_compute_conf
		else
			echo "KVM ACCELERATION ENABLED"
		fi		
		service nova-compute restart
	fi
}

show_menus_nova(){
	echo "[1] Install the nova Controller API Service"
	echo "[2] Install the nova Compute Service"
	echo "[3] Go back to the previous menu"
	local choice
	read -p "Enter choice [1 - 3]" choice
	case $choice in
	1) configure_nova_controller ;;
	2) configure_nova_compute ;;
	b) init_menu ;;
	*) echo "Error: Select a number from the list" ;;
	esac
}

# OPERATIONS MENU
show_menus(){
	echo "REMEMBER TO UPDATE THE REPOSITORIES!"
	echo "[1] Configure RabbitMQ Server"
	echo "[2] Configure the database for all services (MySQL)"
	echo "[3] Configure the Identity Service (Keystone)"
	echo "[4] Configure the Image Service (Glance)"
	echo "[5] Configure the Block Storage (Cinder-controller)"
	echo "[6] Configure the Block Storage (Cinder-service)"
	echo "[7] Configure the Compute Controller node (Nova Controller)"
	echo "[8] Configure the Compute node (Nova)"
	echo "[9] Configure the Networking (Neutron)"
	echo "[10] Configure the Object Storage (Swift)"
	echo "[11] Configure the Orchestration (Heat)"
	echo "[12] Configure the Telemetry (Ceilometer)"
	echo "[13] Configure the Dashboard (Horizon)"
	echo "[q] Exit"
}

read_options(){
	local choice
	read -p "Enter choice [1 - 13] " choice
	case $choice in
	1) configure_rabbitmq ;;
	2) create_db ;;
	3) configure_keystone ;;
	4) install_glance ;;
	5) configure_cinder_controller ;;
	6) configure_cinder_service ;;	
	7) configure_nova_controller ;;
	8) configure_nova_compute ;;
	9) configure_neutron ;;
	10) configure_swift ;;
	11) configure_heat ;;
	12) configure_ceilometer ;;
	13) configure_horizon ;;
	q) exit 0 ;;
	*) echo "Error: Select a number from the list" ;;
	esac
}

function init_menu(){
	while true
	do
		show_menus
		read_options
	done
}

while true
do
	init_menu
done


