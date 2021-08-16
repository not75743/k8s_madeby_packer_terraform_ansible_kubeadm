# provider
region = "ap-northeast-1"

# vpc
vpc_cidr = "10.0.0.0/16"

# subnet
subnet_availability_zone = "ap-northeast-1a"
subnet_cidr_block        = "10.0.1.0/24"

# inbound ssh for master
ssh_to_master = ["192.0.2.1/32"]

# inbound kubeapi for master
kubeapi_to_master = ["192.0.2.1/32"]

# inbound ssh for worker
ssh_to_worker = ["192.0.2.1/32"]

# nodeport ssh for worker
nodeport_to_worker = ["192.0.2.1/32"]

# worker count
worker_count = 2

# worker instance type
instance_type = "t2.medium"

# ec2 pubkey path
pubkey_path = "./sshkey/kube_sshkey.pub"

# ami made by packer
instance_ami = "ami-xxxxxxxxxx"
