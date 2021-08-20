# k8s_madeby_packer_terraform_ansible_kubeadm
packer,terraform,ansibleを使用し、AWS上にk8sクラスタを作ります。  
変数をいくつか埋めていけばクラスタを作成できるように作りました。  
また、各種ツールを備えるdockerfileも作成済みであるため、ツールをインストールすることなく実施可能です。（要docker,podman）

# こんなものが出来上がる
- master *1 worker *(1~3) のk8sクラスタ
```sh
# 例
NAME                                            STATUS   ROLES                  AGE   VERSION
ip-10-0-1-100.ap-northeast-1.compute.internal   Ready    control-plane,master   15m   v1.22.1
ip-10-0-1-101.ap-northeast-1.compute.internal   Ready    <none>                 15m   v1.22.1
ip-10-0-1-102.ap-northeast-1.compute.internal   Ready    <none>                 15m   v1.22.1
```
- CNIプラグイン(calico)適用済み
- 操作PCよりkubectlで設定適用可能

# 本手順のメリット
- dockerと適切なAWSリソース権限があれば実施可能
- terraformを使用するため、GUIでリソースを用意する必要がなく、なおかつ事前準備、片付けが容易
- terraform.tfvarsを編集することで容易にノード数を増やせる

# 要件
- VPC,EC2等のAWSリソースを作成できるAWSユーザであること
- 手順内で使用するツールがインストール済みであること
- 各種操作にコンテナを使用する場合、docker 及び podman が使用可能であ ること。本手順ではdocker,docker-composeを使用します。

# 注意
- 本手順はインターネットにつなげるホストで動作検証しているため、プロキシ接続下のホストについては考慮できていません。
- スペック、セキュリティ等は考慮しきれていないため、デフォルト設定での商用利用は控えてください。
- 各種AWSリソース使用料金が発生するのでご留意ください

# 各種バージョン
動作検証に使用したツールのバージョンは以下の通り
| ツール名       | バージョン | 用途                        |
| -------------- | ---------- | --------------------------- |
| docker         | 20.10.7    | 環境準備用                  |
| docker-compose | 1.27.4     | 環境準備用                  |
| packer         | 1.7.4      | k8sノードAMI作成用          |
| ansible        | 2.9.23     | ノード設定用                |
| python         | 2.7.5      | ansible用                   |
| jq             | 1.6        | terraform出力整形用         |
| terraform      | 1.0.4      | 各AWSリソースセットアップ用 |
| kubectl        | 1.22       | k8sCLIクライアント          |

k8sクラスタのバージョンは以下の通り(2021/8/20時点)
| ツール名            | バージョン                                                                                                                                                                                 | 備考                                       | 
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------ | 
| OS                  | CentOS Linux release 7.9.2009 (Core)<br>Linux ip-10-0-1-100.ap-northeast-1.compute.internal 3.10.0-1160.36.2.el7.x86_64 #1 SMP Wed Jul 21 11:57:15 UTC 2021 x86_64 x86_64 x86_64 GNU/Linux | cat /etc/redhat-release<br>uname -a        | 
| rootボリューム(EBS) | gp2                                                                                                                                                                                        | サイズは10GB<br>ほかの外付けディスクはなし | 
| k8sクラスタ         | 1.22.1                                                                                                                                                                                     |                                            | 
| kubeadm             | 1.22.1                                                                                                                                                                                     |                                            | 
| kubelet             | 1.22.1                                                                                                                                                                                     |                                            | 
| docker              | 20.10.8                                                                                                                                                                                    | コンテナランタイムとしてcontainerdを使用   | 
| containerd          | 1.4.9                                                                                                                                                                                      | k8sが使用するコンテナランタイム            | 
| calico              | 3.20.0                                                                                                                                                                                     | ネットワークCNI                            | 

# 所要時間
~ 1時間（ツール用意済みが前提）

# 手順
## ① 環境準備
```sh
# 作業ディレクトリを作り、そこに本gitリポジトリを持ってくる
mkdir testdir
cd testdir
git clone https://github.com/not75743/k8s_madeby_packer_terraform_ansible_kubeadm.git

# イメージビルド後、コンテナ内に入る
cd k8s_madeby_packer_terraform_ansible_kubeadm/docker
docker-compose up -d --build
docker-compose run kube_centos7 /bin/bash
```

ツールが用意できている場合git clone以外不要です。

## ② packer事前準備
### ②-1 packer/variables.pkrvars.hcl確認
packerは上記の変数ファイルを使用します。  
デフォルト設定で使用可能ですが、もし変更がある場合は以下に従って修正してください。

| 変数           | 用途                                  | デフォルト              | 必須/任意 |
| -------------- | ------------------------------------- | ----------------------- | --------- |
| instance_type  | packerが用意するEC2インスタンスタイプ | "t2.medium"             | 任意      |
| region         | インスタンス,AMIを用意するリージョン  | "ap-northeast-1"        | 任意      |
| source_ami     | ベースとなるAMI IDを指定              | "ami-06a46da680048c8ae" | 任意      |
| ssh_username   | EC2にSSHするユーザ                    | "centos"                | 任意      |
| ami_prefix     | AMIのNAMEとTAGに使用                  | "kubenode"              | 任意      |
### ②-2 環境変数設定
packer,terraformがAWSリソースを操作可能にするため、環境変数でcredentialを設定します
```sh
export AWS_ACCESS_KEY_ID="xxxxxxxxxxxxxxxxxx"
export AWS_SECRET_ACCESS_KEY="xxxxxxxxxxxxxxxxxxx"
```
なお、本手順は~/.aws/credentialを設定している場合、自動的にcredential を読み込むため不要です。

## ③packer実行
以下を実行します
```sh
# 移動(packerコマンドはカレントディレクトリを参照するため)
cd packer

# AWS用プラグインインストール
packer init .

# AMI作成
packer build -var-file=variables.pkrvars.hcl .
```
無事完了したら以下のように出力されます。
terraformの変数ファイルで使うため、生成されたAMI IDを控えて下さい。
```sh
--> amazon-ebs.centos: AMIs were created:
ap-northeast-1: ami-xxxxxxxxxxxxxxx # これ
```

## ④ terraform事前準備
### ④-1 SSH鍵用意
各ノードへのansible,SSHに必要な鍵を用意します。  
既存の鍵を用意する場合 は不要です。
```sh
# 鍵格納ディレクトリに移動、鍵生成
cd ../terraform
mkdir sshkey && chmod 700 sshkey
cd sshkey
ssh-keygen -t rsa -b 4096 -N "" -f kube_sshkey
```
### ④-2 terraform/terraform.tfvars編集
terraformは上記の変数ファイルを使用します。  
入力必須箇所があるため、以下に従って必ず編集してください。

| 変数                      | 用途                                                                                                               | デフォルト                | 必須/任意 |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------ | -------------------------- | --------- |
| region                    | リソースを用意するリージョン                                                                                       | "ap-northeast-1"           | 任意      |
| vpc_cidr                  | VPCで使用するIPアドレスレンジ                                                                                      | "10.0.0.0/16"              | 任意      |
| subnet_availability_zone  | サブネットを用意するAZ                                                                                             | "ap-northeast-1a"          | 任意      |
| subnet_cidr_block         | サブネットで使用するIPアドレスレンジ                                                                               | "10.0.1.0/24"              | 任意      |
| ssh_to_master             | masterにSSH接続するホスト<br>本手順では 作業するホストを指定                                                        | "192.0.2.0/24"             | 必須      |
| kubeapi_to_master         | kubectlでk8s APIへ接続するホスト<br>本手順では作業するホストを指定                                                 | "192.0.2.0/24"             | 必須      |
| ssh_to_worker             | workerにSSH接続するホスト<br>本手順では 作業するホストを指定                                                        | "192.0.2.0/24"             | 必須      |
| nodeport_to_worker        | workerのnodeportへ接続するホスト<br>本手順では作業するホストを指定                                                 | "192.0.2.0/24"             | 必須      |
| worker_count              | 作成するworkerノードの数<br>1~3の中から 指定してください。<br>※ 0を選択すると1、4以上を選択すると3が選択され ます。 | 2                          | 必須      |
| instance_type            | 作成するworkerノードのインスタンスタイプ                                                                           | "t2.medium"                | 任意      |
| pubkey_path               | 先ほど作成したEC2へログインするために必 要な鍵ファイル                                                              | "./sshkey/kube_sshkey.pub" | 任意      |
| instance_ami              | packerで用意したAMIのID                                                                                            | "ami-xxxxxxxxxx"           | 必須      |

※ 複数IPを対象にする場合、以下の様に記載してください。
```sh
["192.0.2.1/32", "192.0.2.2/32"]
```

### ④-3 terraform init
terraformのプラグインをインストールします。terraformディレクトリに移動してください
```sh
cd terraform
terraform init
```

## ⑤ shell実行
用意してあるシェルスクリプトを実行します。
```sh
cd ~
./kubernetes_setup.sh
```
最初にterraform applyが実行されるので、出力内容に問題がなければ`yes`をタイプして先に進んでください。
後は待つだけです。  
やっていることはざっくり以下です。

1. terraform実行(途中で一度実行して問題ないか聞かれます)
2. terraformのoutputで得たIPアドレスを必要箇所に転記
3. ノードのSSHポートが空くまで2分待機
4. masterセットアップ用のplaybookを実施
5. workerセットアップ用のplaybookを実施
6. k8s接続用コマンドを出力

終わったら以下の様に出力されます
```sh
done !!

Run "export KUBECONFIG=`realpath ./kubernetes_yaml/kubeconfig`" to connect kubernetes API
```

## ⑥ kubernetes接続
shellscript終了時に指示された内容を入力します。
```sh
export KUBECONFIG=`realpath ./kubernetes_yaml/kubeconfig`
```
k8sクラスタに接続できるようになりました。
本環境(worker2台)では以下の様に出力されました。
```sh
$ kubectl get node
NAME                                            STATUS   ROLES                  AGE    VERSION
ip-10-0-1-100.ap-northeast-1.compute.internal   Ready    control-plane,master   2m6s   v1.22.0
ip-10-0-1-101.ap-northeast-1.compute.internal   Ready    <none>                 109s   v1.22.0
ip-10-0-1-102.ap-northeast-1.compute.internal   Ready    <none>                 110s   v1.22.0

$ kubectl get pod -A
NAMESPACE     NAME                                                                    READY   STATUS    RESTARTS   AGE
kube-system   calico-kube-controllers-58497c65d5-jrpgw                                1/1     Running   0          2m30s
kube-system   calico-node-6ppj2                                                       1/1     Running   0          2m23s
kube-system   calico-node-hhsxk                                                       1/1     Running   0          2m30s
kube-system   calico-node-nfk8q                                                       1/1     Running   0          2m24s
kube-system   coredns-78fcd69978-s6r2f                                                1/1     Running   0          2m32s
kube-system   coredns-78fcd69978-sjsdc                                                1/1     Running   0          2m32s
kube-system   etcd-ip-10-0-1-100.ap-northeast-1.compute.internal                      1/1     Running   0          2m38s
kube-system   kube-apiserver-ip-10-0-1-100.ap-northeast-1.compute.internal            1/1     Running   0          2m38s
kube-system   kube-controller-manager-ip-10-0-1-100.ap-northeast-1.compute.internal   1/1     Running   0          2m39s
kube-system   kube-proxy-4mpxk                                                        1/1     Running   0          2m24s
kube-system   kube-proxy-bdpbd                                                        1/1     Running   0          2m32s
kube-system   kube-proxy-bhrph                                                        1/1     Running   0          2m23s
kube-system   kube-scheduler-ip-10-0-1-100.ap-northeast-1.compute.internal            1/1     Running   0          2m36s
```

## ⑦動作確認
おいてあるファイルで動作確認が可能です。
```sh
cd kubernetes_yaml
kubectl apply -f sample.yaml
```
接続確認してつなげるか試してください。
workerの接続情報が書かれたworkerip.txtがあるので使います。
```sh
$ cat workerip.txt
$ curl http://<workerip>:30080 && echo
Hello Kubernetes!
```

## ⑧ 片付け
以下を実行してください。
terraformで作成したリソースが削除されます。
```sh
cd ~
./kubernetes_destroy.sh
```
途中で消していいか聞かれるため、問題なければ`yes`をタイプしてください 。
コンテナを使用している場合は、使わないのであれば忘れずに消して置きましょう
```sh
exit
docker-compose down
```

片付きました。  
再度クラスタを作る際は、コンテナの用意、環境変数でのcredential設定を行ってください。その後手順⑤から再度クラスタを作成できます。

# 想定されるエラー
## Error: NoCredentialProviders: no valid providers in chain. Deprecated.
packer,terraformにcredential設定が反映できていません。手順②-2を実施してください

## fatal: [xxx.xxx.xxx.xxx]: UNREACHABLE! => {"changed": false, "msg": "timed out", "unreachable": true}
playbookを実行するためのsshが失敗しています。セキュリティグループで弾 かれている可能性が高いため、ipアドレスの記載が誤っていないか確認しましょう

