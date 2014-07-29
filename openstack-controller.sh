#!/bin/bash

mkdir rcfiles
mkdir confbak
mkdir lockfiles
openstack_db_pass=rcfiles/openstack_db_pass
openrc=rcfiles/openrc
admin_openrc=rcfiles/admin_openrc
admin_user_creds=rcfiles/admin_user_creds
rabbitrc=rcfiles/rabbitrc
glancerc=rcfiles/glancerc
neutronrc=rcfiles/neutronrc
cinderrc=rcfiles/cinderrc
metadatarc=rcfiles/metadatarc
novarc=rcfiles/novarc
controller_node_file=rcfiles/controller_node_file
keystone_conf="/etc/keystone/keystone.conf"
glance_api_conf="/etc/glance/glance-api.conf"
glance_registry_conf="/etc/glance/glance-registry.conf"
cinder_conf="/etc/cinder/cinder.conf"
nova_conf="/etc/nova/nova.conf"
neutron_conf="/etc/neutron/neutron.conf"
nova_compute_conf="/etc/nova/nova-compute.conf"
statoverride="/etc/kernel/postinst.d/statoverride"
ml2_conf_ini="/etc/neutron/plugins/ml2/ml2_conf.ini"
ml3_conf_agent_ini="/etc/neutron/l3_agent.ini"
dhcp_agent_ini="/etc/neutron/dhcp_agent.ini"
metadata_agent_ini="/etc/neutron/metadata_agent.ini"

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

function is_local(){
	echo "Is it a local installation or a remote installation?"
	echo "[1] Local"
	echo "[2] Remote (SSH)"
	local islocal
	read -p "Enter choice [1 - 3]" islocal
	case $islocal in
		1) configure_nova_controller ;;
		2) ;;
		b) echo "Go back" ;;
		*) echo "Wrong choice" ;;
	esac
}

function exec_ssh(){
	echo "Executing the script remotely"
	
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
		apt-get install -y rabbitmq-server
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
		echo "controller_node=$controller_node" >> $controller_node_file
		chmod 700 $controller_node_file
		source $controller_node_file
	fi
}

function create_db(){
	if [ -e lockfiles/db_installed ]; then
		echo "DB Already configured"
	else
		configure_db_passwords
		apt-get install -y python-mysqldb mysql-server rabbitmq-server
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
		ALTER DATABASE glance charset=utf8;
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
		touch lockfiles/db_installed
	fi
}

function configure_keystone() {
# KEYSTONE INSTALLATION
	if [ -e lockfiles/keystone_installed ]; then
		echo "Keystone already installed"
	else
		create_db
		configure_rabbitmq
		set_controller
		configure_openrc
		echo "Installing Openstack keystone server"
		apt-get install -y keystone python-keystone python-keystoneclient
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
		touch lockfiles/keystone_installed
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
	if [ -e lockfiles/glance_installed ]; then
		echo "Glance already installed"
	else
		set_controller
		configure_admin_openrc
		configure_glancerc
		create_db
		configure_rabbitmq
		apt-get install -y glance python-glanceclient
		keystone user-create --name=glance --pass=$glance_pass --email=glance@example.com
		keystone user-role-add --user=glance --tenant=service --role=admin
		cp $glance_api_conf "confbak/glance-api.conf.$(date +%F_%R)"
		cp $glance_registry_conf "confbak/glance-registry.conf.$(date +%F_%R)"
		# PARSE AND CHANGE API FILE
		sed -i "/\[DEFAULT\]/ a\rpc_backend\ \=\ rabbit\\
rabbit_host\ \=\ $controller_node\\
rabbit_password\ \=\ $rabbit_pass" $glance_api_conf
		sed -i "/\[keystone_authtoken\]/ a\auth_uri\ \=\ http\:\/\/$controller_node\:5000" $glance_api_conf
		sed -i "s/sqlite_db\ \=\ \/var\/lib\/glance\/glance.sqlite/connection\ \=\ mysql\:\/\/glance\:$password_db_glance\@$controller_node\/glance/g" $glance_api_conf
		sed -i "s/auth_host\ \=\ 127.0.0.1/auth_host\ \=\ $controller_node/g" $glance_api_conf		
		sed -i "s/\%SERVICE_TENANT_NAME\%/service/g" $glance_api_conf
		sed -i "s/\%SERVICE_USER\%/glance/g" $glance_api_conf
		sed -i "s/\%SERVICE_PASSWORD\%/$glance_pass/g" $glance_api_conf
		sed -i "s/\#flavor\=/flavor\=keystone/g" $glance_api_conf
		# PARSE AND CHANGE REGISTRY FILE
		sed -i "/\[keystone_authtoken\]/ a\auth_uri\ \=\ http\:\/\/$controller_node\:5000" $glance_registry_conf
		sed -i "s/sqlite_db\ \=\ \/var\/lib\/glance\/glance.sqlite/connection\ \=\ mysql\:\/\/glance\:$password_db_glance\@$controller_node\/glance/g" $glance_registry_conf
		sed -i "s/rabbit_host\ \=\ localhost/rabbit_host\ \=\ $controller_node/g" $glance_registry_conf		
		sed -i "s/\rabbit_password\ \=\ guest/rabbit_password\ \=\ $rabbit_pass/g" $glance_registry_conf
		sed -i "s/auth_host\ \=\ 127.0.0.1/auth_host\ \=\ $controller_node/g" $glance_registry_conf		
		sed -i "s/\%SERVICE_TENANT_NAME\%/service/g" $glance_registry_conf
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
		touch lockfiles/glance_installed
	fi
return
}

function configure_horizon(){
	apt-get install -y apache2 memcached libapache2-mod-wsgi openstack-dashboard
	apt-get remove --purge -y openstack-dashboard-ubuntu-theme
}

function configure_cinder_controller(){
	if [ -e lockfiles/cinder_controller_installed ]; then
		echo "Cinder already installed"
	else
		apt-get install -y cinder-api cinder-scheduler
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
		touch lockfiles/cinder_controller_installed
	fi
}
function configure_cinder_service(){
	apt-get install -y cinder-volume
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
	if [ -e lockfiles/nova_generic_installed ]; then
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
		touch lockfiles/nova_generic_installed
	fi
}

function configure_nova_controller(){
	if [ -e lockfiles/nova_controller_installed ]; then
		echo "Nova Controller already installed"
	else	
		apt-get install -y nova-api nova-cert nova-conductor nova-consoleauth nova-novncproxy nova-scheduler python-novaclient
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
		touch lockfiles/nova_controller_installed	
	fi
}

function configure_nova_compute(){
	if [ -e lockfiles/nova_compute_installed ]; then
		echo "Nova Compute already installed"
	else	
		apt-get install -y nova-compute-kvm python-guestfs python-mysqldb
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
		touch lockfiles/nova_compute_installed
		if [ $(egrep -c '(vmx|svm)' /proc/cpuinfo) -eq 0 ]; then
			echo "WARNING KVM ACCELERATION NOT ENABLED ON THIS HOST"
			sed -i "s/virt_type\=kvm/virt_type\=qemu/g" $nova_compute_conf
		else
			echo "KVM ACCELERATION ENABLED"
		fi		
		service nova-compute restart
	fi
}

function configure_neutronrc(){
	if [ -e "$neutronrc" ]; then
		echo "The $neutronrc file already exists, sourcing it. "
		source $neutronrc
	else
		neutron_pass=$(openssl rand -hex 16)
		echo "neutron_pass=$neutron_pass" >> $neutronrc
		chmod 700 $neutronrc
		source $neutronrc
	fi
}

function configure_neutron_ml2(){
	if [ -e lockfiles/neutron_ml2_installed ]; then
		echo "Neutron ml2 file already configured"
	else
		sed -i "/\[ml2\]/ a\mechanism_drivers\ \=\ openvswitch" $ml2_conf_ini
		sed -i "/\[ml2\]/ a\tenant_network_types\ \=\ gre" $ml2_conf_ini
		sed -i "/\[ml2\]/ a\type_drivers\ \=\ gre" $ml2_conf_ini
		sed -i "/\[ml2_type_gre\]/ a\tunnel_id_ranges\ \=\ 1\:1000" $ml2_conf_ini
		sed -i "/\[securitygroup\]/ a\enable_security_group\ \=\ True" $ml2_conf_ini
		sed -i "/\[securitygroup\]/ a\firewall_driver\ \=\ neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver" $ml2_conf_ini
		touch lockfiles/neutron_ml2_installed
	fi
}

function configure_neutron_ml2_node(){
	echo "[ovs]" >> $ml2_conf_ini
	echo "Enter the ip address that is used for the ml2 tunnel network on this node"
	read instance_tunnel_ip_address
	echo "local_ip = $instance_tunnel_ip_address" >> $ml2_conf_ini
	echo "tunnel_type = gre" >> $ml2_conf_ini
	echo "enable_tunneling = True" >> $ml2_conf_ini
}

function configure_neutron_ml3(){
	sed -i "/interface_driver\ \=\ neutron.agent.linux.interface.OVSInterfaceDriver/ s/# *//" $ml3_conf_agent_ini
	sed -i "/use_namespaces\ \=\ True/ s/# *//" $ml3_conf_agent_ini
}

function configure_neutron_dhcp_agent(){
	echo "interface_driver = neutron.agent.linux.interface.OVSInterfaceDriver" >> $dhcp_agent_ini
	echo "dhcp_driver = neutron.agent.linux.dhcp.Dnsmasq" >> $dhcp_agent_ini
	echo "use_namespaces = True" >> $dhcp_agent_ini
}

function configure_neutron_conf(){
	configure_neutronrc
	if [ -e lockfiles/neutron_conf_installed ]; then
		echo "Neutron conf file already configured"
	else	
		cp $neutron_conf "confbak/neutron.conf.$(date +%F_%R)"	
		sed -i "/\[keystone_authtoken\]/ a\auth_uri\ \=\ http\:\/\/$controller_node\:5000" $neutron_conf
		sed -i "s/connection\ \=\ \/\/\/\/var\/lib\/neutron\/neutron.sqlite/connection\ \=\ mysql\:\/\/neutron\:$password_db_neutron\@$controller_node\/neutron/g" $neutron_conf
		sed -i "s/\#\ auth_strategy\ \=\ keystone/auth_strategy\ \=\ keystone/g" $neutron_conf
		sed -i "s/auth_host\ \=\ 127.0.0.1/auth_host\ \=\ $controller_node/g" $neutron_conf
		sed -i "s/\%SERVICE_TENANT_NAME\%/admin/g" $neutron_conf
		sed -i "s/\%SERVICE_USER\%/neutron/g" $neutron_conf
		sed -i "s/\%SERVICE_PASSWORD\%/$neutron_pass/g" $neutron_conf
		sed -i "s/\#\ rabbit_host\ \=\ localhost/rabbit_host\ =\ $controller_node/g" $neutron_conf
		sed -i "s/\#\ rabbit_password\ \=\ guest/rabbit_password\ \=\ $rabbit_pass/g" $neutron_conf
		sed -i "/notify_nova_on_port_status_changes\ \=\ True/ s/# *//" $neutron_conf
		sed -i "/notify_nova_on_port_data_changes\ \=\ True/ s/# *//" $neutron_conf
		sed -i "s/\#\ nova_url\ \=\ http\:\/\/127.0.0.1\:8774\/v2/nova_url\ \=\http\:\/\/$controller_node\:8774\/v2/g" $neutron_conf
		sed -i "s/\#\ nova_admin_username\ \=/nova_admin_username\ \=\ nova/g" $neutron_conf
		nova_admin_tenant_id=$(keystone tenant-get service | awk '/ id / {print $4}')
		sed -i "s/\#\ nova_admin_tenant_id\ \=/nova_admin_tenant_id\ \=\ $nova_admin_tenant_id/g" $neutron_conf
		sed -i "s/\#\ nova_admin_password\ \=/nova_admin_password\ \=\ $nova_pass/g" $neutron_conf
		sed -i "s/\#\ nova_admin_auth_url\ \=/nova_admin_auth_url\ \=\ http\:\/\/$controller_node\:35357\/v2.0/g" $neutron_conf
		sed -i "/\[DEFAULT\]/ a\allow_overlapping_ips\ \=\ True" $neutron_conf
		sed -i "/\[DEFAULT\]/ a\service_plugins\ \=\ router" $neutron_conf
		sed -i "/\[DEFAULT\]/ a\core_plugin\ \=\ ml2" $neutron_conf
		touch lockfiles/neutron_conf_installed
	fi
}

configure_neutron_metadatarc(){
	if [ -e "$metadatarc" ]; then
		echo "The $metadatarc file already exists, sourcing it. "
		source $metadatarc
	else
		metadata_pass=$(openssl rand -hex 16)
		echo "metadata_pass=$metadata_pass" >> $metadatarc
		chmod 700 $metadatarc
		source $metadatarc
	fi
}

function configure_neutron_metadata(){
	set_controller
	configure_neutronrc
	sed -i "s/auth_url\ \=\ http\:\/\/localhost\:5000\/v2.0/auth_url\ \=\ http\:\/\/$controller_node\:5000\/v2.0/g" $metadata_agent_ini
	sed -i "s/\%SERVICE_TENANT_NAME\%/service/g" $metadata_agent_ini
	sed -i "s/\%SERVICE_USER\%/neutron/g" $metadata_agent_ini
	sed -i "s/\%SERVICE_PASSWORD\%/$neutron_pass/g" $metadata_agent_ini
	sed -i "s/\#\ nova_metadata_ip\ \=\ 127.0.0.1/nova_metadata_ip\ \=\ $controller_node/g" $metadata_agent_ini
	configure_neutron_metadatarc
	sed -i "\#\ metadata_proxy_shared_secret\ \=/metadata_proxy_shared_secret\ \=\ $metadata_pass/g" $metadata_agent_ini
}

function configure_neutron_novaconf(){
	if [ -e lockfiles/neutron_nova_configured ]; then
		echo "Neutron controller service already installed"
	else
		cp $nova_conf "confbak/neutron.conf.$(date +%F_%R)"	
		sed -i "/\[DEFAULT\]/ a\network_api_class\ \=\ nova.network.neutronv2.api.API\\
service_neutron_metadata_proxy\ \=\ true\\
neutron_metadata_proxy_shared_secret\ \=\ $metadata_pass\\
neutron_url\ \=\ http:\/\/$controller_node\:9696\\
neutron_auth_strategy\ \=\ keystone\\
neutron_admin_tenant_name\ \=\ service\\
neutron_admin_username\ \=\ neutron\\
neutron_admin_password\ \=\ $neutron_pass\\
neutron_admin_auth_url\ \=\ http\:\/\/$controller_node\:35357\/v2.0\\
linuxnet_interface_driver\ \=\ nova.network.linux_net.LinuxOVSInterfaceDriver\\
firewall_driver\ \=\ nova.virt.firewall.NoopFirewallDriver\\
security_group_api\ \=\ neutron" $nova_conf
		touch lockfiles/neutron_nova_configured
	fi
}

function configure_neutron_controller(){
	if [ -e lockfiles/neutron_controller_installed ]; then
		echo "Neutron controller service already installed"
	else
		apt-get install -y neutron-server neutron-plugin-ml2
		create_db
		configure_neutronrc
		configure_rabbitmq
		configure_admin_openrc
		set_controller
		cp $neutron_conf "confbak/neutron.conf.$(date +%F_%R)"
		keystone user-create --name neutron --pass $neutron_pass --email neutron@example.com
		keystone user-role-add --user neutron --tenant service --role admin
		keystone service-create --name neutron --type network --description "OpenStack Networking"
		keystone endpoint-create --service-id $(keystone service-list | awk '/ network / {print $2}') --publicurl http://$controller_node:9696 --adminurl http://$controller_node:9696 --internalurl http://$controller_node:9696
		configure_neutron_conf
		configure_nova_controller
		configure_neutron_metadatarc
		configure_neutron_novaconf
		service nova-api restart
		service nova-scheduler restart
		service nova-conductor restart
		service neutron-server restart
		touch lockfiles/neutron_controller_installed
	fi
}

function configure_neutron_node(){
	sed -i "/net.ipv4.ip_forward=1/ s/# *//" /etc/sysctl.conf
	sysctl -p
	apt-get install -y neutron-plugin-ml2 neutron-plugin-openvswitch-agent openvswitch-datapath-dkms neutron-l3-agent neutron-dhcp-agent
	configure_neutron_conf
	configure_neutron_ml3
	configure_neutron_dhcp_agent
	configure_neutron_metadata
	configure_neutron_ml2
	configure_neutron_ml2_node
	service openvswitch-switch restart
	ovs-vsctl add-br br-int
	ovs-vsctl add-br br-ex
	echo "Enter the external interface name eg.: eth0 eth1"
	read external_interface
	ovs-vsctl add-port br-ex $external_interface
# SERVICE RESTART	
	service neutron-plugin-openvswitch-agent restart
	service neutron-l3-agent restart
	service neutron-dhcp-agent restart
	service neutron-metadata-agent restart
}

function configure_neutron_compute(){
	apt-get install -y neutron-common neutron-plugin-ml2 neutron-plugin-openvswitch-agent openvswitch-datapath-dkms
	configure_rabbitmq
	set_controller
	configure_neutron_conf
	configure_neutron_ml2
	service openvswitch-switch restart
	ovs-vsctl add-br br-int
	configure_neutron_novaconf
	service nova-compute restart
	service neutron-plugin-openvswitch-agent restart
}
# OPERATIONS MENU
show_menus(){
	echo "REMEMBER TO UPDATE THE REPOSITORIES!"
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
	read -p "Enter choice [1 - 11] " choice
	case $choice in
		1) configure_rabbitmq ;;
		2) create_db ;;
		3) configure_keystone ;;
		4) install_glance ;;
		5) show_menus_cinder ;;
		6) show_menus_nova ;;
		7) show_menus_neutron ;;
		8) configure_swift ;;
		9) configure_heat ;;
		10) configure_ceilometer ;;
		11) configure_horizon ;;
		q) exit 0 ;;
		*) echo "Error: Select a number from the list" ;;
	esac
}

function show_menus_cinder(){
	echo "[1] Install the Cinder Controller API Service"
	echo "[2] Install the Cinder Block Storage"
	echo "[b] Go back to the previous menu"
	local choice
	read -p "Enter choice [1 - 2]" choice
	case $choice in
		1) configure_cinder_controller ;;
		2) configure_cinder_service ;;
		b) init_menu ;;
		*) echo "Error: Select a number from the list" ;;
	esac
}

function show_menus_cinder_type(){
	echo "[1] Configure LVM2 Block Storage"
	echo "[2] Configure NFS Network Storage"
	local choice
	read -p "Enter choise [1 - 3]" choice
	case $choice in
		1) configure_cinder_lvm ;;
		2) configure_cinder_nfs ;;
		b) show_menus_cinder ;;
		*) echo "Error: Select a number from the list" ;;
	esac
}

function show_menus_nova(){
	echo "[1] Install the nova Controller API Service"
	echo "[2] Install the nova Compute Service"
	echo "[b] Go back to the previous menu"
	local choice
	read -p "Enter choice [1 - 2]" choice
	case $choice in
		1) configure_nova_controller ;;
		2) configure_nova_compute ;;
		b) init_menu ;;
		*) echo "Error: Select a number from the list" ;;
	esac
}

function show_menus_neutron(){
	echo "[1] Install the Neutron Controller API Service"
	echo "[2] Install the Neutron Network Service"
	echo "[3] Install the Neutron service on a Compute Node"
	echo "[b] Go back to the previous menu"
	local choice
	read -p "Enter choice [1 - 3]" choice
	case $choice in
		1) configure_neutron_controller ;;
		2) configure_neutron_node ;;
		3) configure_neutron_compute ;;
		b) init_menu ;;
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

