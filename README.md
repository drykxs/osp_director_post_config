# osp_director_post_config

This script is intended to streamline the configuration necessary after a Red Hat OpenStack Platform deployment done with Director. This script has four functions:  

setup-overcloud: creates a cirros image, a flavor and sets up an external network and subnet.  

create-tenant: creates a user and project with the same name.  Adds the user with admin role to the project.  Adds icmp and port 22 rules to the tenant security group.  

setup-tenant-network: creates a private network, subnet, router that attaches to external network.  

create-instance: creates an instance and assigns a floating ip from the external network.  

