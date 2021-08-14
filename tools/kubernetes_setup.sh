#! /bin/bash

# エラー時に停止
set -eu -o pipefail

# エラー箇所出力
trap 'echo "ERROR: line no = $LINENO, exit status = $?" >&2; exit 1' ERR

# 各AWSリソース生成
cd ./terraform
terraform plan
terraform apply
echo ""

# masterIPアドレスをhosts,varsに転記
cp -f ../ansible/hosts.org ../ansible/hosts
sed -i -e "3i $(command terraform output -json | jq -r ".master_public_ip.value")" ../ansible/hosts
sed -i -e "2s@[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}@`terraform output -json | jq -r ".master_public_ip.value"`@g" ../ansible/vars/vars.yaml

# workerIPアドレスをhostsに転記
declare -i COUNT=0
declare -i ROW=6

while [ $COUNT -lt `terraform output -json | jq -r ".worker_public_ip.value[]" | wc -l` ]
do
  sed -i -e ""${ROW}i" $(command terraform output -json | jq -r ".worker_public_ip.value[$COUNT]")" ../ansible/hosts
  COUNT+=1
    ROW+=1
done

# worker IPをメモ
terraform output -json | jq -r ".worker_public_ip.value[]" > ../kubernetes_yaml/workerip.txt

# sshポート開放まで待機
echo "wait for SSH to master"
sleep 120s

# playbook実行
cd ../ansible
export ANSIBLE_CONFIG=./cfg/ansible.cfg
ansible-playbook -i hosts master.yaml
ansible-playbook -i hosts worker.yaml

echo "done !!"
echo ""

echo 'Run "export KUBECONFIG=`realpath ./kubernetes_yaml/kubeconfig`" to connect kubernetes API'
echo ""
