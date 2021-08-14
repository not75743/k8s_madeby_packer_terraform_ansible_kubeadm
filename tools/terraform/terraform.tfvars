# provider
region = "ap-northeast-1"

# vpc
vpc_cidr = "10.0.0.0/16"

# subnet
subnet_availability_zone = "ap-northeast-1a"
subnet_cidr_block        = "10.0.1.0/24"

# inbound ssh for master
ssh_to_master = [""]

# inbound kubeapi for master
kubeapi_to_master = [""]

# inbound ssh for worker
ssh_to_worker = [""]

# nodeport ssh for worker
nodeport_to_worker = [""]

# worker count
worker_count = 2

# ec2 pubkey path
pubkey_path = "./sshkey/kube_sshkey.pub"

# ami made by packer
instance_ami = ""
