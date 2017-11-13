. ~/overcloudrc

function help-msg {
  echo " "
  echo "usage: setup-overcloud, create-tenant <tenant name>, setup-tenant-network <tenant name>, create-instance <tenant name>"
}

function setup-overcloud {
  . ~/stackrc
  #configure hosts file on undercloud
  grep -v overcloud /etc/hosts > /tmp/hosts.new
  nova list --fields name,networks | awk '/overcloud/ { gsub("ctlplane=",""); print $6" "$4; }' >> /tmp/hosts.new
  sudo cp /etc/hosts /etc/hosts.backup
  sudo mv -f /tmp/hosts.new /etc/hosts

  . ~/overcloudrc
  if ! openstack image list -c Name -f value | grep -q cirros; then 
    pushd .
    cd /tmp
    wget http://download.cirros-cloud.net/0.3.5/cirros-0.3.5-x86_64-disk.img 
    openstack image create --file cirros-0.3.5-x86_64-disk.img --disk-format qcow2 --public cirros
    popd 
  fi
  if ! openstack flavor list -c Name -f value | grep -q 'm1.tiny'; then 
    openstack flavor create --public m1.tiny --id auto --ram 512 --disk 10 --vcpus 1
  fi 
  if ! neutron net-list  --name public -c name -f value | grep -q public; then 
    neutron net-create public -- --router:external=true  --provider:network_type=flat  --provider:physical_network=datacentre
  fi
  if ! neutron subnet-list -c name -f value | grep -q public-subnet; then
    neutron subnet-create public --name public-subnet --allocation-pool start=192.168.122.180,end=192.168.122.220 192.168.122.0/24
    #neutron subnet-create public --name public-subnet --allocation-pool start=172.16.0.128,end=172.16.0.199 172.16.0.0/24
  fi
  help-msg
}

function create-tenant {
  . ~/overcloudrc
  tenant=$1
  openstack project create $tenant
  openstack user create --password $tenant --project $tenant $tenant
  openstack role add --project $tenant --use admin admin
  #this works if run for admin project (or any other)
  export OS_USERNAME=$tenant
  export OS_TENANT_NAME=$tenant
  export OS_PROJECT_NAME=$tenant
  export OS_PASSWORD=$tenant
  default_security_group_id=$(openstack security group list -c ID -c Name -c Project -f value | \
    grep $(openstack project show $tenant -c id -f value) | grep default | awk '{ print $1 }')
  echo default_security_group_id=$default_security_group_id
#  openstack security group rule create --ingress --ethertype IPv4 --protocol icmp $default_security_group_id
#  openstack security group rule create --ingress --ethertype IPv4 --protocol tcp --dst-port 22 $default_security_group_id
  neutron security-group-rule-create --direction ingress \
    --ethertype IPv4 --protocol tcp --port-range-min 22 \
    --port-range-max 22 default
  neutron security-group-rule-create --direction ingress \
   --ethertype IPv4 --protocol icmp default
  nova keypair-add demo-key
  help-msg
}
 
function setup-tenant-network {
  . ~/overcloudrc
  tenant=$1
  #networkname='private-net'
  networkname="$tenant-private1-net"
  export OS_USERNAME=$tenant
  export OS_TENANT_NAME=$tenant
  export OS_PROJECT_NAME=$tenant
  export OS_PASSWORD=$tenant

  if ! neutron net-list  --name $networkname -c name -f value | grep -q $networkname; then 
    neutron net-create $networkname
  fi
  if ! neutron subnet-list -c name -f value | grep -q $networkname-subnet; then 
    neutron subnet-create $networkname 10.0.1.0/24 --name $networkname-subnet
  fi
  if ! neutron router-list -c name -f value | grep -q $tenant-router1; then
    neutron router-create $tenant-router1
  fi
  if ! [ $(neutron router-port-list $tenant-router1 -c id -f value | wc -l) -gt 1 ]; then 
    neutron router-gateway-set $tenant-router1 public
    neutron router-interface-add $tenant-router1 $networkname-subnet
  fi
  help-msg
}

function create-instance {
  tenant=$1
  count=$2 #number of instances
  if [ -z $count ]; then count=1; fi
  . ~/overcloudrc
  export OS_TENANT_NAME=$tenant
  export OS_PROJECT_NAME=$tenant
  export OS_USERNAME=$tenant
  export OS_PASSWORD=$tenant
  for i in $(seq 1 $count); do 
    nova boot --flavor m1.tiny --image cirros --nic net-name=$tenant-private1-net $tenant-test$i
    sleep 5
    nova floating-ip-associate $tenant-test$i $(neutron floatingip-create -c floating_ip_address -f value  public)
  done

  help-msg
}

help-msg
