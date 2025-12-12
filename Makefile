##############################################################################
## Makefile.settings : Environment Variables for Makefile(s)
include Makefile.settings
# … ⋮ ︙ • ● – — ™ ® © ± ° ¹ ² ³ ¼ ½ ¾ ÷ × ₽ € ¥ £ ¢ ¤ ♻ ⚐ ⚑ ✪ ❤  \ufe0f
# ☢ ☣ ☠ ¦ ¶ § † ‡ ß µ Ø ƒ Δ ☡ ☈ ☧ ☩ ✚ ☨ ☦ ☓ ♰ ♱ ✖  ☘  웃 𝐀𝐏𝐏 🡸 🡺 ➔
# ℹ️ ⚠️ ✅ ⌛ 🚀 🚧 🛠️ 🔧 🔍 🧪 👈 ⚡ ❌ 💡 🔒 📊 📈 🧩 📦 🥇 ✨️ 🔚
##############################################################################
## Environment variable rules:
## - Any TRAILING whitespace KILLS its variable value and may break recipes.
## - ESCAPE only that required by the shell (bash).
## - Environment hierarchy:
##   - Makefile environment OVERRIDEs OS environment lest set using `?=`.
##     - `FOO ?= bar` is overridden by parent setting; `export FOO=new`.
##     - `FOO :=`bar` is NOT overridden by parent setting.
##   - Docker YAML `env_file:` OVERRIDEs OS and Makefile environments.
##   - Docker YAML `environment:` OVERRIDEs YAML `env_file:`.
##   - CMD-inline OVERRIDEs ALL REGARDLESS; `make recipeX FOO=new BAR=new2`.


##############################################################################
## Recipes : Meta

menu :
	$(INFO) '=== K8s Admin'
	$(INFO) '🧩  Install HA kubeadm cluster onto target hosts'
	@echo "    ● Expects target hosts are RHEL 8+"
	@echo "    ● Control Plane Entrypoint: ${K8S_CONTROL_ENTRYPOINT} (${K8S_FQDN})"
	@echo "      - External HA LB operating in TCP mode"
	@echo "      - See https://${HALB_PROJECT}.git"
	@echo "    ● Security requirements of targets include:"
	@echo "      - SELinux mode is 'Enforcing'"
	@echo "      - Linux firewall zone bound to host device (${K8S_NETWORK_DEVICE}) has target 'DROP'"
	$(INFO) "🚧  1. Provision targets for a K8s cluster (kubeadm ${K8S_VERSION})"
	@echo "upgrade      : dnf upgrade all targets"
	@echo "conf         : kernel selinux swap : See scripts/configure-*"
	@echo "  -kernel    : Configure kernel for K8s/CNI/CRI : load modules and set runtime params"
	@echo "  -selinux   : Configure targets' SELinux"
	@echo "  -swap      : Configure targets' swap : Disable all swap devices"
	@echo "install      : Install K8s and all deps"
	@echo "  -rpms      : Install host tools and K8s dep (conntrack)"
	@echo "  -cni       : Install K8s CNI Pod network providers"
	@echo "  -cri       : Install K8s CRI and all deps, and tools"
	@echo "  -k8s       : Install K8s and CNI plugins"
	@echo "rootca       : Create PKI for domain's Root Certificate Authority (CA)"
	$(INFO) "🚧  2. Configure Linux firewall of targets to protect/allow K8s cluster traffic"
	@echo "fw           : Configure Linux firewall for the Kubernetes cluster"
	@echo "  -k8s       : Configure firewalld and NetworkManager for K8s control and worker nodes"
	@echo "   -external : Configure --zone=${K8S_FW_ZONE_EXTERNAL} (zone bound to ${HALB_DEVICE})"
	@echo "   -internal : Configure --zone=${K8S_FW_ZONE_INTERNAL} (default zone; binds to CNI adapters)"
	@echo "  -calico    : Configure firewalld for Calico CNI"
	@echo "    *-remove : Remove the set firewalld rules : fw-k8s-external-remove … fw-calico-remove"
	@echo "  -list      : firewall-cmd --list-all : both k8s zones : ${K8S_FW_ZONE_EXTERNAL} and ${K8S_FW_ZONE_INTERNAL}"
	@echo "   -external : firewall-cmd --list-all --zone=${K8S_FW_ZONE_EXTERNAL} (zone bound to ${HALB_DEVICE})"
	@echo "   -internal : firewall-cmd --list-all --zone=${K8S_FW_ZONE_INTERNAL} (default zone; binds to CNI adapters)"
	@echo "  -get       : firewall-cmd --info-service={} (each service) and --direct --get-all-rules"
	@echo "  -zones     : firewall-cmd : Verify zones : active (${K8S_FW_ZONE_EXTERNAL}) and default (${K8S_FW_ZONE_INTERNAL})"
	@echo "  -log       : Recently DROPped packets : journalctl --since='${ADMIN_JOURNAL_SINCE}' |grep DROP"
	$(INFO) "🚀  3. Initialize the K8s cluster"
	@echo "init         : Create 1st control node of the cluster"
	@echo "  -purge     : Purge Makefile.bootstrap.settings of stale PKI params"
	@echo "  -gen       : Generate ${K8S_KUBEADM_CONF_INIT} from template (.yaml.tpl)"
	@echo "  -push      : Upload ${K8S_KUBEADM_CONF_INIT} to all nodes"
	@echo "  -images    : kubeadm config images pull …"
	@echo "  -pki       : Generate cluster PKI (once)"
	@echo "  -pre       : kubeadm init phase preflight …"
	@echo "  -now       : kubeadm init … : at 1st node (${ADMIN_USER}@${K8S_NODE_INIT})"
	$(INFO) "🚧  4. Configure K8s API clients at local host ($(shell hostname))"
	@echo "kubeconfig   : See ~/.kube/config, else set KUBECONFIG"
	$(INFO) "🚧  5. Install (one) CNI Add-on to provision the cluster's Pod Network"
	@echo "cilium       : Install Cilium"
	@echo "calico       : Install Calico"
	@echo "  -status    : kubectl get …"
	@echo "  -restart   : Rolling restart of both DaemonSet and controller (Fix for various Pod Network fail modes)"
	@echo "  -teardown  : Teardown Calico"
	@echo "calicoctl    : Reports of calicoctl via K8s plugin : kubectl calico …"
	@echo "kuberouter   : Install Kube Router"
	@echo "  -teardown  : Teardown Kuberoute"
	$(INFO) "🚧  6. Join other nodes into the cluster"
	@echo "join-control : Join all other control-plane nodes into cluster"
	@echo "  -prep      : join-certs join-gen join-push"
	@echo "  -gen       : Process ${K8S_KUBEADM_CONF_JOIN}.tpl into YAML"
	@echo "  -push      : Push ${K8S_KUBEADM_CONF_JOIN} to nodes"
	@echo "join-command : Print join command for control-plane node : same cert key/hash; new token"
	@echo "join-token   : kubeadm token list"
	@echo "init-certs   : Only on join and ONLY IF CERTIFICATE KEY EXPIRED"
	$(INFO) "🚧  Ingress"
	@echo "ingress-nginx: Ingress NGINX Controller"
	@echo "  -status    : kubectl get "
	@echo "  -up        : Install"
	@echo "  -secret    : Create K8s Secret for default TLS certificate"
	@echo "    -parse   : Parse the TLS certificate of K8s Secret"
	@echo "  -down      : Teardown"
	@echo "  -e2e       : End-to-end HTTP  test : curl -s http://\$$host:\$$nodePort/{foo,bar}/hostname"
	@echo "  -e2e-tls   : End-to-end HTTPS test : curl -s https://e2e.${K8S_FQDN}/{foo,bar}/hostname"
	$(INFO) "🚧  External Storage Provisioners (CSI)"
	@echo "csi-local    : Install local-path-provisioner"
	@echo "csi-nfs      : Install chart of a K8s CSI External Provisioner and SC of NFS-type storage"
	@echo "  -down      : Teardown the chart"
	@echo "  -test      : Test dynamic PV provisioning and write access thereto by Pod/PVC manifest"
	@echo "  -test-down : Teardown the test Pod/PVC/PV"
	@echo "csi-nfs      : Install K8s CSI SC and Provisioner for NFS "
	@echo "csi-smb      : WIP : Install K8s csi-driver-smb"
	@echo "csi-rook-up  : Install Rook Operator / Ceph "
	@echo "csi-rook-down: Teardown Rook Operator / Ceph "
	$(INFO) "🚧  Observability"
	@echo "metrics      : Install metrics-server, enabling: kubectl top …"
	@echo "dashboard    : Install K8s Dashboard : Web UI for K8s API"
	@echo "prom-*       : kube-prometheus-stack"
	@echo "  -install   : Install by Helm chart"
	@echo "  -access    : Forward Grafana port for local access (Remove: pkill kubectl)"
	@echo "  -delete    : Delete the running release"
	$(INFO) "🚧  Cluster-level Logging"
	@echo "efk-apply    : Install EFK stack"
	@echo "efk-delete   : Teardown EFK stack"
	@echo "efk-verify   : GET request to Kibana"
	@echo "loki-install : Install Grafana Loki chart"
	@echo "loki-delete  : Uninstall Grafana Loki chart"
	$(INFO) "🚧  Security"
	@echo "trivy        : Install Trivy Operator by Helm"
	$(INFO) "⚠️  Cluster Teardown"
	@echo "teardown     : kubeadm reset and cleanup at target node(s)"
	$(INFO) "🔍  Inspect : Hosts"
	@echo "status       : Print targets' status"
	@echo "sealert      : sealert -l '*'"
	@echo "net          : Interfaces' info"
	@echo "ruleset      : nftables rulesets"
	@echo "iptables     : iptables"
	@echo "ipvs         : List the IPVS table"
	@echo "psk          : ps of K8s processes"
	@echo "psrss        : ps sorted by RSS usage"
	@echo "pscpu        : ps sorted by CPU usage"
	$(INFO) "🔍  Inspect : K8s API"
	@echo "journal      : kubelet logs … --since='${ADMIN_JOURNAL_SINCE}' (per node)"
	@echo "version      : GET /version"
	@echo "health       : GET /livez, /readyz"
	@echo "apiserver    : Timeout errors of K8s API server logs"
	@echo "events       : kubectl events -A --sort-by=.lastTimestamp |tail -n 50"
	@echo "info         : kubectl cluster-info"
	@echo "dump         : kubectl cluster-info dump |grep -i error"
	@echo "nodes        : K8s Node(s) status"
	@echo "pods         : kubectl get pods -A -o wide -w"
	@echo "podcidr      : PodCIDR and per node"
	$(INFO) "🧪  Test"
	@echo "uniq         : K8s requires each node have a unique hostname, product ID, and network device MAC"
	@echo "iostat       : Disk I/O : See '*_await' (req/resp latency [ms]) and '%util'(ization)"
	@echo "fio          : etcd fsync 99-th percentile latency"
	@echo "iperf        : Network I/O : Pod Network Bandwidth test"
	@echo "bench        : ApacheBench (ab) load tests"
	@echo "  -health    : Load test K8s-API endpoint"
	@echo "  -e2e       : Load test Ingress-E2E-Test endpoint"
	$(INFO) "🛠️  Maintenance : Host"
	@echo "userrc       : Configure targets' bash shell (See https://${ADMIN_USER_CONF}.git)"
	@echo "reboot       : Reboot all (K8S_NODES) : ${K8S_NODES}"
	@echo "  -soft      : drain ➔  reboot ➔  uncordon"
	@echo "  -hard      : reboot ${K8S_NODES}"
	$(INFO) "🛠️  Maintenance : K8s"
	@echo "prune        : Delete all (problemed) Pods of STATUS: ${ADMIN_PODS_PRUNE}"
	@echo "crictl       : containerd status"
	@echo "  -images    : Images in containerd cache"
	@echo "  -ps        : Containers of containerd"
	@echo "  -pods      : Pods of containerd"
	@echo "  -ready     : Delete all containerd Pods in 'NotReady' status"
	@echo "etcd         : etcdctl … : Command per 'make etcd-*' recipe"
	@echo "  -logs      : Logs of etcd-* Pods, sans 'info' level, --since=${ADMIN_K8S_LOG_SINCE}s"
	@echo "  -status    : etcdctl {status,health,member list}"
	@echo "  -snapshot  : etcdctl snapshot run on each node"
	@echo "  -defrag    : etcdctl defrag run on each node"
	@echo "  -p99       : etcd fsync 99-th percentile latency"
	$(INFO) "🛠️  Maintenance : Meta"
	@echo "env          : Print the make environment"
	@echo "mode         : Fix folder and file modes of this project"
	@echo "eol          : Fix line endings : Convert all CRLF to LF"
	@echo "html         : Process all markdown (MD) to HTML"
	@echo "commit       : Commit and push this source"

env :
	$(INFO) 'Environment'
	@echo "PWD=${PRJ_ROOT}"
	@env |grep DOMAIN_ |grep -v HALB
	@echo
	@env |grep HALB_ |sort
	@echo
	@env |grep K8S_ |grep -v ADMIN |sort
	@echo
	@env |grep ADMIN_ |sort

eol :
	find . -type f ! -path '*/.git/*' -exec dos2unix {} \+
mode :
	find . -type d ! -path './.git/*' -exec chmod 755 "{}" \;
	find . -type f ! -path './.git/*' -exec chmod 660 "{}" \;
#	find . -type f ! -path './.git/*' -iname '*.sh' -exec chmod 755 "{}" \;
tree :
	tree -d |tee tree-d
html :
	find . -type f ! -path './.git/*' -name '*.md' -exec md2html.exe "{}" \;
commit push : html mode
	gc && git push && gl && gs


##############################################################################
## Recipes : Cluster

# Scan subnet (CIDR) for IP addresses in use (running machines).
# - Manually validate that HALB_VIP is set to an *unused* address (within subnet CIDR).
# - Note this does not guarantee that an available VIP will remain so.
# - Protecting a VIP requires network admin.
scan :
	sudo nmap -sn ${HALB_CIDR} \
	    |tee ${ADMIN_SRC_DIR}/logs/${LOG_PRE}.scan.nmap.${UTC}.log
#	sudo arp-scan --interface ${HALB_DEVICE} --localnet \
#	    |tee ${ADMIN_SRC_DIR}/logs/${LOG_PRE}.scan.arp-scan.${UTC}.log

status hello :
	@ansibash 'printf "%12s: %s\n" SELinux $$(getenforce) \
	    && printf "%12s: %s\n" firewalld $$(systemctl is-active firewalld.service) \
	    && printf "%12s: %s\n" haproxy $$(systemctl is-active haproxy) \
	    && printf "%12s: %s\n" keepalived $$(systemctl is-active keepalived) \
	    && printf "%12s: %s\n" containerd $$(systemctl is-active containerd) \
	    && printf "%12s: %s\n" kubelet $$(systemctl is-active kubelet) \
	    && printf "%12s: %s\n" Kernel $$(uname -r) \
	    && printf "%12s:%s\n" uptime "$$(uptime)" \
	'
sealert :
	ansibash 'sudo sealert -l "*" |grep -e == -e "Source Path" -e "Last Seen" |grep -v 2024 |grep -B1 -e == -e "Last Seen"'
net :
	ansibash '\
	    sudo nmcli dev status; \
	    ip -brief addr; \
	'
ruleset :
	ansibash sudo nft list ruleset
iptables :
	ansibash sudo iptables -L -n -v
ipvs :
	ansibash sudo ipvsadm -L -n

uniq :
	@echo -e "ℹ️  K8s requires each node have unique: 1. Product UUID 2. Network device MAC 3. hostname"
	ansibash -s scripts/uniq.sh
psrss :
	ansibash -s scripts/psrss.sh
pscpu :
	ansibash -s scripts/pscpu.sh

podcidr :
	kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.podCIDR}{"\n"}{end}'
	@echo "PodCIDR ${K8S_POD_CIDR}"

# Configure bash shell of target hosts using the declared Git project
userrc :
	ansibash 'git clone https://github.com/sempernow/userrc 2>/dev/null || echo ok'
	ansibash 'pushd userrc && git pull && make sync-user && make user && echo ✅ Updated!'

reboot : reboot-soft
reboot-hard :
	@echo -e "  ⚠️ : HARD reboot of hosts: ${ADMIN_TARGET_LIST}"
	ansibash sudo reboot
reboot-soft :
	bash make.recipes.sh rebootSoft ${K8S_NODES}
upgrade :
	ansibash 'sudo dnf makecache || echo "⚠️  ERR : $$?"' 
	ansibash 'sudo dnf -y --color=never upgrade || echo "⚠️  ERR : $$?"' \
	    |tee ${ADMIN_SRC_DIR}/logs/${LOG_PRE}.upgrade.${UTC}.log

rootca :
	bash make.recipes.sh rootCA

conf-sudoer :
	bash make.recipes.sh sudoer \
	    |tee ${ADMIN_SRC_DIR}/logs/${LOG_PRE}.conf-sudoer.${UTC}.log

conf : conf-kernel conf-selinux conf-swap reboot
conf-kernel :
	ansibash -u ${ADMIN_SRC_DIR}/scripts/configure-kernel.sh
	ansibash 'sudo bash configure-kernel.sh || echo "⚠️  ERR : $$?"' \
	    |tee ${ADMIN_SRC_DIR}/logs/${LOG_PRE}.conf-kernel.${UTC}.log
conf-selinux :
	ansibash -u ${ADMIN_SRC_DIR}/scripts/configure-selinux.sh
	ansibash 'sudo bash configure-selinux.sh enforcing || echo "⚠️  ERR : $$?"' \
	    |tee ${ADMIN_SRC_DIR}/logs/${LOG_PRE}.conf-selinux.${UTC}.log
conf-swap :
	ansibash -u ${ADMIN_SRC_DIR}/scripts/configure-swap.sh
	ansibash 'sudo bash configure-swap.sh || echo "⚠️  ERR : $$?"' \
	    |tee ${ADMIN_SRC_DIR}/logs/${LOG_PRE}.conf-swap.${UTC}.log

install installs : install-rpms install-cni install-cri install-k8s
install-rpms install-rpm :
	ansibash -u ${ADMIN_SRC_DIR}/scripts/install-rpms.sh
	ansibash 'sudo bash install-rpms.sh || echo "⚠️  ERR : $$?"' \
	    |tee ${ADMIN_SRC_DIR}/logs/${LOG_PRE}.install-rpms.${UTC}.log
install-cni :
	ansibash -u ${ADMIN_SRC_DIR}/scripts/install-cni.sh \
	ansibash 'sudo bash install-cni.sh eBPF || echo "⚠️  ERR : $$?"' \
	    |tee ${ADMIN_SRC_DIR}/logs/${LOG_PRE}.install-cni.${UTC}.log
install-cri :
	ansibash -u ${ADMIN_SRC_DIR}/scripts/install-cri.sh \
	ansibash 'sudo bash install-cri.sh || echo "⚠️  ERR : $$?"' \
	    |tee ${ADMIN_SRC_DIR}/logs/${LOG_PRE}.install-cri.${UTC}.log
install-k8s :
	ansibash -u ${ADMIN_SRC_DIR}/scripts/install-k8s.sh
	ansibash 'sudo bash install-k8s.sh ${K8S_VERSION} ${K8S_REGISTRY} || echo "⚠️  ERR : $$?"' \
	    |tee ${ADMIN_SRC_DIR}/logs/${LOG_PRE}.install-k8s.${UTC}.log

fw-disable :
	ansibash sudo systemctl disable --now firewalld
fw-enable :
	ansibash sudo systemctl enable --now firewalld

fw : fw-k8s fw-calico
fw-k8s : fw-k8s-external fw-k8s-internal
fw-k8s-external :
	ansibash -u ${ADMIN_SRC_DIR}/scripts/firewall-k8s-external.sh
	ansibash 'sudo bash firewall-k8s-external.sh ${HALB_DEVICE} ${K8S_FW_ZONE_EXTERNAL} || echo "⚠️  ERR : $$?"' \
	    |tee ${ADMIN_SRC_DIR}/logs/${LOG_PRE}.fw-k8s-external.${UTC}.log
fw-k8s-internal :
	ansibash -u ${ADMIN_SRC_DIR}/scripts/firewall-k8s-internal.sh
	ansibash 'sudo bash firewall-k8s-internal.sh \
	    ${K8S_FW_ZONE_INTERNAL} "${K8S_POD_CIDR}" "${K8S_SERVICE_CIDR}" "${K8S_HOST_CIDR}" || echo "⚠️  ERR : $$?"' \
	    |tee ${ADMIN_SRC_DIR}/logs/${LOG_PRE}.fw-k8s-internal.${UTC}.log
fw-calico :
	ansibash -u ${ADMIN_SRC_DIR}/scripts/firewall-calico.sh
	ansibash 'sudo bash firewall-calico.sh ${HALB_DEVICE} ${K8S_FW_ZONE_EXTERNAL} "${K8S_PEERS}" || echo "⚠️  ERR : $$?"' \
	    |tee ${ADMIN_SRC_DIR}/logs/${LOG_PRE}.firewall-calico.${UTC}.log

fw-remove : fw-k8s-remove fw-calico-remove
fw-k8s-remove : fw-k8s-external-remove fw-k8s-internal-remove
fw-k8s-external-remove :
	ansibash -u ${ADMIN_SRC_DIR}/scripts/firewall-k8s-external.sh
	ansibash 'sudo bash firewall-k8s-external.sh ${HALB_DEVICE} ${K8S_FW_ZONE_EXTERNAL} x || echo "⚠️  ERR : $$?"' \
	    |tee ${ADMIN_SRC_DIR}/logs/${LOG_PRE}.firewall-k8s-external-remove.${UTC}.log
fw-k8s-internal-remove :
	ansibash -u ${ADMIN_SRC_DIR}/scripts/firewall-k8s-internal.sh
	ansibash 'sudo bash firewall-k8s-internal.sh \
	    ${K8S_FW_ZONE_INTERNAL} "${K8S_POD_CIDR}" "${K8S_SERVICE_CIDR}" "${K8S_HOST_CIDR}" x || echo "⚠️  ERR : $$?"' \
	    |tee ${ADMIN_SRC_DIR}/logs/${LOG_PRE}.firewall-k8s-internal-remove.${UTC}.log
fw-calico-remove :
	ansibash -u ${ADMIN_SRC_DIR}/scripts/firewall-calico.sh
	ansibash 'sudo bash firewall-calico.sh ${HALB_DEVICE} ${K8S_FW_ZONE_EXTERNAL} "${K8S_PEERS}" remove || echo "⚠️  ERR : $$?"' \
	    |tee ${ADMIN_SRC_DIR}/logs/${LOG_PRE}.firewall-calico.${UTC}.log

fw-list : fw-list-external fw-list-internal
fw-get :
	ansibash -u ${ADMIN_SRC_DIR}/scripts/firewall-get.sh
	ansibash 'sudo bash firewall-get.sh || echo "⚠️  ERR : $$?"' \
	    |tee ${ADMIN_SRC_DIR}/logs/${LOG_PRE}.firewall-get.${UTC}.log
fw-list-external :
	ansibash 'sudo firewall-cmd --list-all --zone=${K8S_FW_ZONE_EXTERNAL}' \
	    |tee ${ADMIN_SRC_DIR}/logs/${LOG_PRE}.firewall-list-external.log
fw-list-internal :
	ansibash 'sudo firewall-cmd --list-all --zone=${K8S_FW_ZONE_INTERNAL}' \
	    |tee ${ADMIN_SRC_DIR}/logs/${LOG_PRE}.firewall-list-internal.log
fw-zone fw-zones :
	ansibash 'sudo firewall-cmd --get-active-zones'
	ansibash 'sudo firewall-cmd --get-default-zone'
fw-log fw-logs :
	ansibash "sudo journalctl --since='${ADMIN_JOURNAL_SINCE}' |grep DROP;echo All recent DROP logs from \'${ADMIN_JOURNAL_SINCE}\' until $$(date -Is)"

init-imperative :
	ssh -t ${ADMIN_USER}@${K8S_NODE_INIT} \
	    sudo kubeadm init --control-plane-endpoint "${K8S_CONTROL_ENTRYPOINT}" \
	        --kubernetes-version ${K8S_VERSION} \
	        --upload-certs \
	        --pod-network-cidr "${K8S_POD_CIDR}" \
	        --service-cidr "${K8S_SERVICE_CIDR}" \
	        --apiserver-advertise-address ${K8S_CONTROL_IP} \
	        --node-name ${K8S_NODE_INIT} \
	        --cri-socket "${K8S_CRI_SOCKET}" \
	        |tee ${ADMIN_SRC_DIR}/logs/${LOG_PRE}.kubeadm.init-imperative.${UTC}.log

# @ init-certs phase : config (K8S_KUBEADM_CONF_INIT) must not have PKI
# @ final init phase : config (K8S_KUBEADM_CONF_INIT) may have PKI, but ours does not.

init : init-purge init-gen init-push init-images init-pki init-pre init-now kubeconfig
init-purge :
	bash make.recipes.sh settings_purge
	rm -f logs/*init*.log logs/*join*.log
init-gen :
	bash make.recipes.sh settings_inject ${ADMIN_SRC_DIR}/scripts/${K8S_KUBEADM_CONF_INIT} \
	    |tee ${ADMIN_SRC_DIR}/logs/${LOG_PRE}.init-gen.${UTC}.log
init-push :
	ANSIBASH_TARGET_LIST='${K8S_NODES_CONTROL}' \
	    ansibash -u ${ADMIN_SRC_DIR}/scripts/${K8S_KUBEADM_CONF_INIT} \
	        |tee ${ADMIN_SRC_DIR}/logs/${LOG_PRE}.init-push.${UTC}.log
# kubectl krew install community-images
# kubectl community-images --mirror # List of the images
init-images :
	ANSIBASH_TARGET_LIST='${K8S_NODES_CONTROL}' \
	    ansibash sudo kubeadm config images pull -v${K8S_VERBOSITY} \
	        --config ${K8S_KUBEADM_CONF_INIT} \
	        |tee ${ADMIN_SRC_DIR}/logs/${LOG_PRE}.init-images.${UTC}.log
## Generate cluster PKI (if not exist) : Cleanup old settings
## This K8S_KUBEADM_CONF_INIT must NOT have PKI (key, hash, token)
init-pki :
	scp -p ${ADMIN_SRC_DIR}/scripts/kubeadm-init-pki.sh ${K8S_NODE_INIT}:. \
	    && ssh -t ${ADMIN_USER}@${K8S_NODE_INIT} sudo bash kubeadm-init-pki.sh ${K8S_KUBEADM_CONF_INIT} \
	    |tee ${ADMIN_SRC_DIR}/logs/${LOG_PRE}.init-pki.${UTC}.log
init-pre :
	ANSIBASH_TARGET_LIST='${K8S_NODES_CONTROL}' \
	    ansibash sudo kubeadm init phase preflight -v${K8S_VERBOSITY} \
	        --config ${K8S_KUBEADM_CONF_INIT} \
	        |tee ${ADMIN_SRC_DIR}/logs/${LOG_PRE}.init-pre.${UTC}.log
init-now :
	ssh -t ${ADMIN_USER}@${K8S_NODE_INIT} \
	    sudo kubeadm init -v${K8S_VERBOSITY} \
	        --upload-certs \
	        --config ${K8S_KUBEADM_CONF_INIT} \
	        |tee ${ADMIN_SRC_DIR}/logs/${LOG_PRE}.init-now.${UTC}.log

static-stop :
	ansibash -u ${ADMIN_SRC_DIR}/scripts/static-rotate.sh
	ansibash sudo bash static-rotate.sh stop
static-start :
	ansibash -u ${ADMIN_SRC_DIR}/scripts/static-rotate.sh
	ansibash sudo bash static-rotate.sh start

kubeconfig :
	bash make.recipes.sh kubeconfig

## init-certs is RUN ONLY IF the (bootstrap) certificate KEY HAS EXPIRED.
## Run prior to running the join-control recipe (only if key has expired).
init-certs :
	scp -p ${ADMIN_SRC_DIR}/scripts/kubeadm-init-certs.sh ${ADMIN_USER}@${K8S_NODE_INIT}:. \
	    && ssh -t ${ADMIN_USER}@${K8S_NODE_INIT} sudo bash kubeadm-init-certs.sh ${K8S_KUBEADM_CONF_INIT} \
	    |tee ${ADMIN_SRC_DIR}/logs/${LOG_PRE}.init-certs.${UTC}.log
	scp -p ${ADMIN_USER}@${K8S_NODE_INIT}:Makefile.settings Makefile.${K8S_NODE_INIT}.settings
join-control : join-prep join-now
join-prep : join-gen join-push
## K8S_CERTIFICATE_KEY must be set PRIOR TO RUNNING join-gen
join-gen :
	bash make.recipes.sh settings_inject ${ADMIN_SRC_DIR}/scripts/${K8S_KUBEADM_CONF_JOIN} \
	    |tee ${ADMIN_SRC_DIR}/logs/${LOG_PRE}.join-gen.${UTC}.log
join-push :
	ANSIBASH_TARGET_LIST='${K8S_NODES_JOIN}' \
	    ansibash -u ${ADMIN_SRC_DIR}/scripts/join-control.sh
	ANSIBASH_TARGET_LIST='${K8S_NODES_JOIN}' \
	    ansibash -u ${ADMIN_SRC_DIR}/scripts/${K8S_KUBEADM_CONF_JOIN}
	ANSIBASH_TARGET_LIST='${K8S_NODES_JOIN}' \
	    ansibash -u ~/.kube/config discovery.yaml
join-now :
	ANSIBASH_TARGET_LIST='${K8S_NODES_JOIN}' \
	    ansibash sudo bash join-control.sh ${K8S_NETWORK_DEVICE} ${K8S_KUBEADM_CONF_JOIN} \
	    |tee ${ADMIN_SRC_DIR}/logs/${LOG_PRE}.join-control.${UTC}.log
# Print command to join a node into CONTROL PLANE; same cert key/hash; new token
# join-token :
# 	@sudo kubeadm token list |awk '{printf "%25s\t%s\t%s\n",$$1,$$2,$$4}'
join-command :
	ssh -t ${ADMIN_USER}@${K8S_NODE_INIT} \
	    sudo kubeadm token create --print-join-command \
	        --certificate-key ${K8S_CERTIFICATE_KEY} \
	        |tee ${ADMIN_SRC_DIR}/logs/${LOG_PRE}.print-join-command.${UTC}.log

## _install [replace_kube_proxy|pod_ntwk_only] : Default is replace else pod on fail
kuberouter kuberouter-install :
	bash ${ADMIN_SRC_DIR}/cni/kube-router/kube-router.sh _install replace_kube_proxy \
	    |tee ${ADMIN_SRC_DIR}/logs/${LOG_PRE}.kuberouter-install.${UTC}.log
	kubectl get pod -A -o wide -w
kuberouter-teardown :
	bash ${ADMIN_SRC_DIR}/cni/kube-router/kube-router.sh _teardown \
	    |tee ${ADMIN_SRC_DIR}/logs/${LOG_PRE}.kuberouter-teardown.${UTC}.log

#cilium : cilium-gen cilium-helm
export cilium_values := values-bpf.yaml
cilium : cilium-gen cilium-cli
cilium-cli :
	bash ${ADMIN_SRC_DIR}/cni/cilium/cilium.sh install_by_cli \
	    ${cilium_values} \
	    |tee ${ADMIN_SRC_DIR}/logs/${LOG_PRE}.cilium-cli.${UTC}.log
cilium-gen :
	bash make.recipes.sh settings_inject \
	    ${ADMIN_SRC_DIR}/cni/cilium/${cilium_values} \
	    |tee ${ADMIN_SRC_DIR}/logs/${LOG_PRE}.cilium-gen.${UTC}.log
cilium-helm :
	bash ${ADMIN_SRC_DIR}/cni/cilium/cilium.sh install_by_helm \
	    ${cilium_values} \
	    |tee ${ADMIN_SRC_DIR}/logs/${LOG_PRE}.cilium-helm.${UTC}.log
cilium-teardown :
	bash ${ADMIN_SRC_DIR}/cni/cilium/cilium.sh teardown \
	    |tee ${ADMIN_SRC_DIR}/logs/${LOG_PRE}.cilium-teardown.${UTC}.log

calico_manifest := calico.v3.29.3.yaml
calico_operator := custom-resources-bpf-bgp.yaml
calico-pull :
	bash cni/calico/calico-pull.sh
#calico : calico-operator
calico : calico-manifest
calicoctl :
	@echo -e "\n🔍 kubectl get tigerastatuses (If installed by operator method.)"
	@kubectl get tigerastatuses 2>/dev/null && kubectl get tigerastatuses || true \
	    |tee -a ${ADMIN_SRC_DIR}/logs/${LOG_PRE}.callico-status.log 
	@echo -e "\n🔍 calicoctl node status"
	ansibash sudo /usr/local/bin/calicoctl node status \
	    |tee ${ADMIN_SRC_DIR}/logs/${LOG_PRE}.callico-status.log
	@echo -e "🔍 kubectl calico get ippool"
	@kubectl calico get ippool \
	    |tee -a ${ADMIN_SRC_DIR}/logs/${LOG_PRE}.callico-status.log
	@echo -e "🔍 kubectl calico ipam show --show-blocks"
	@kubectl calico ipam show --show-blocks \
	    |tee -a ${ADMIN_SRC_DIR}/logs/${LOG_PRE}.callico-status.log
	@echo -e "\n🔍 kubectl calico show --ip=${K8S_CONTROL_IP}"
	@kubectl calico ipam show --ip=${K8S_CONTROL_IP} \
	    |tee -a ${ADMIN_SRC_DIR}/logs/${LOG_PRE}.callico-status.log
	@echo -e "\n🔍 kubectl calico ipam show --show-configuration"
	@kubectl calico ipam show --show-configuration \
	    |tee -a ${ADMIN_SRC_DIR}/logs/${LOG_PRE}.callico-status.log
	@echo -e "\n🔍 kubectl calico ipam check"
	@kubectl calico ipam check \
	    |tee -a ${ADMIN_SRC_DIR}/logs/${LOG_PRE}.callico-status.log
calico-restart :
	kubectl -n kube-system rollout restart ds/calico-node
	kubectl -n kube-system rollout status  ds/calico-node
	kubectl -n kube-system rollout restart deploy/calico-kube-controllers
	kubectl -n kube-system rollout status deploy/calico-kube-controllers
calico-status :
	@kubectl get pod,ds,deploy,cm -A |grep -e calico -e NAME |sed 's/NAMESPACE/\nNAMESPACE/'
calico-manifest :
	kubectl apply -f ${ADMIN_SRC_DIR}/cni/calico/manifest-method/${calico_manifest} \
	    |tee ${ADMIN_SRC_DIR}/logs/${LOG_PRE}.calico-manifest.${UTC}.log
calico-operator : calico-operator-gen
	bash ${ADMIN_SRC_DIR}/cni/calico/operator-method/calico-operator.sh apply ${calico_operator}
calico-operator-gen :
	bash make.recipes.sh settings_inject \
	    ${ADMIN_SRC_DIR}/cni/calico/operator-method/${calico_operator} \
	    |tee ${ADMIN_SRC_DIR}/logs/${LOG_PRE}.calico-operator-gen.${UTC}.log
calico-teardown :
	bash ${ADMIN_SRC_DIR}/cni/calico/operator-method/calico-operator.sh teardown ${calico_operator} || echo
	kubectl delete -f ${ADMIN_SRC_DIR}/cni/calico/manifest-method/calico.yaml || echo
	kubectl delete -f ${ADMIN_SRC_DIR}/cni/calico/manifest-method/crds.yaml || echo

export selector := non-cni
kubeproxy-cleanup :
	kubectl patch ds -n kube-system kube-proxy -p '{"spec":{"template":{"spec":{"nodeSelector":{"${selector}": "true"}}}}}' || echo
	ansibash -u scripts/kube-proxy-cleanup.sh
	ansibash sudo bash kube-proxy-cleanup.sh
kubeproxy-restore :
	kubectl patch ds -n kube-system kube-proxy \
	    --type=json \
	    -p='[{"op": "remove", "path": "/spec/template/spec/nodeSelector/${selector}"}]'

journal journald journalctl :
	ansibash "sudo journalctl --no-pager -u kubelet --since='${ADMIN_JOURNAL_SINCE}' |grep -i error"
version :
	type jq >/dev/null 2>&1 \
	    && curl -fksS https://${K8S_FQDN}:8443/version |jq . \
	    || curl -fksS https://${K8S_CONTROL_ENTRYPOINT}/version \
	    || echo "ERR : $$?"
health :
	@bash make.recipes.sh health
events :
	kubectl get events -A --sort-by=.lastTimestamp |tail -n 50
export port := 5551
psk :
	ansibash psk
pods pod watch :
	kubectl get pod -A -o wide -w
nodes node :
	@kubectl get node && echo
	@type yq >/dev/null 2>&1 \
	    && kubectl get node -o yaml \
	        |yq '.items[]? | [{"name": .metadata.name, "trueConditions": (.status.conditions[] | select(.status == "True")), "nodeInfo": .status.nodeInfo}]' \
	            || echo REQUIREs yq
apiserver :
	@echo "ℹ️  Timeouts at all K8s API Pods (kube-apiserver) since ${ADMIN_K8S_LOG_SINCE} (ADMIN_K8S_LOG_SINCE)"
	@printf "%s\n" ${K8S_NODES} |xargs -I{} kubectl -n kube-system logs pod/kube-apiserver-{} --timestamps --since=${ADMIN_K8S_LOG_SINCE} \
	    |grep -e timeout -e time-elapsed || echo "    … NONE logged."

bench : bench-health bench-e2e
bench-health :
	@echo -e "\n📊  K8s API"
	type -t ab && ab -c 100 -n 10000 https://${K8S_CONTROL_ENTRYPOINT}/readyz?verbose || echo "⚠️  REQUIREs ab"
bench-e2e :
	@echo -e "\n📊  Ingress E2E"
	kubectl -n test-ingress get ingress test-ingress-tls \
	    && kubectl -n test-ingress get pod foo \
	    && type -t ab \
	    && ab -c 100 -n 10000 https://e2e.kube.lime.lan/foo/hostname || echo

iperf :
	bash ${ADMIN_SRC_DIR}/observability/metrics/iperf3/k8s-iperf.sh ${port} || echo
iostat :
	ansibash iostat -xmd 2 5
fio : etcd-p99
crictl : crictl-images crictl-ps crictl-pods
crictl-ps crictl-ctnr crictl-container crictl-containers :
	ansibash sudo crictl ps
crictl-pods crictl-pod :
	ansibash sudo crictl pods
crictl-images :
	ansibash sudo crictl images
images :
	kubectl get po -A -o jsonpath='{range .items[*]}{.spec.initContainers[].image}{"\n"}{.spec.containers[*].image}{"\n"}{end}' |sort -u
crictl-ready crictl-pod-ready crictl-pods-ready crictl-prune :
	ansibash 'sudo crictl pods |grep NotReady |cut -d" " -f1 |xargs -n1 sudo crictl stopp'
	ansibash 'sudo crictl pods |grep NotReady |cut -d" " -f1 |xargs -n1 sudo crictl rmp'
prune :
	bash make.recipes.sh prune
#	bash scripts/kubectl-mass-delete-pods.sh StatusUnk
info :
	kubectl cluster-info
dump :
	kubectl cluster-info dump |grep -i error
etcd-logs etcd-log :
	bash make.recipes.sh etcdLogs ${ADMIN_K8S_LOG_SINCE}
etcd-p99 etcd-fio :
	ansibash -u ${ADMIN_SRC_DIR}/scripts/etcd.sh
	ansibash sudo bash etcd.sh p99_2 /var/lib/etcd \
	    |tee ${ADMIN_SRC_DIR}/logs/${LOG_PRE}.etcd-p99.${UTC}.log
etcd-status :
	ansibash -u ${ADMIN_SRC_DIR}/scripts/etcd.sh
	ansibash 'sudo bash etcd.sh status ${K8S_NODES_CONTROL} || echo "⚠️  ERR : $$?"' \
	    |tee ${ADMIN_SRC_DIR}/logs/${LOG_PRE}.etcd-status.${UTC}.log
etcd-status-local :
	ansibash -u ${ADMIN_SRC_DIR}/scripts/etcd.sh
	ansibash 'sudo bash etcd.sh local || echo "⚠️  ERR : $$?"' \
	    |tee ${ADMIN_SRC_DIR}/logs/${LOG_PRE}.etcd-status.${UTC}.log
etcd-defrag :
	ansibash -u ${ADMIN_SRC_DIR}/scripts/etcd.sh
	ansibash 'sudo bash etcd.sh defrag|| echo "⚠️  ERR : $$?"' \
	    |tee ${ADMIN_SRC_DIR}/logs/${LOG_PRE}.etcd-defrag.${UTC}.log
etcd-snapshot:
	ansibash -u ${ADMIN_SRC_DIR}/scripts/etcd.sh
	ansibash 'sudo bash etcd.sh snapshot || echo "⚠️  ERR : $$?"' \
	    |tee ${ADMIN_SRC_DIR}/logs/${LOG_PRE}.etcd-snapshot.${UTC}.log

metrics metrics-up :
	bash ${ADMIN_SRC_DIR}/observability/metrics/metrics-server/metrics-server.sh apply
metrics-down:
	bash ${ADMIN_SRC_DIR}/observability/metrics/metrics-server/metrics-server.sh delete
dashboard :
	bash ${ADMIN_SRC_DIR}/observability/metrics/dashboard/dashboard.sh

# k apply -f observability/metrics/dashboard/recommended.yaml
# k -n kubernetes-dashboard create token kubernetes-dashboard
# printf "\n  %s\n" Access @ http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/
# k proxy

ingress := ingress/ingress-nginx/ingress-nginx.sh
## Unset HALB unless the Ingress is configured for it.
export HALB ?= yes
ingress-nginx :
	@echo "  Recipes for ingress-nginx-* : up down get values secret secret-parse template manifest diff e2e e2e-tls"
ingress-nginx-up : ingress-nginx-values ingress-nginx-secret
#	bash ${ADMIN_SRC_DIR}/${ingress} upManifest
	bash ${ADMIN_SRC_DIR}/${ingress} upChart
ingress-nginx-get ingress-nginx-status :
	bash ${ADMIN_SRC_DIR}/${ingress} get
ingress-nginx-values :
	bash ${ADMIN_SRC_DIR}/${ingress} values
ingress-nginx-secret :
	bash ${ADMIN_SRC_DIR}/${ingress} secret
ingress-nginx-secret-parse ingress-nginx-parse :
	bash ${ADMIN_SRC_DIR}/${ingress} parse
ingress-nginx-diff :
	bash ${ADMIN_SRC_DIR}/${ingress} diff
ingress-nginx-template :
	bash ${ADMIN_SRC_DIR}/${ingress} template
ingress-nginx-manifest :
	bash ${ADMIN_SRC_DIR}/${ingress} manifest
ingress-nginx-e2e :
	bash ${ADMIN_SRC_DIR}/ingress/ingress-nginx/e2e/test-ingress.sh e2e http https || echo ERR $$?
ingress-nginx-e2e-tls :
	bash ${ADMIN_SRC_DIR}/ingress/ingress-nginx/e2e/test-ingress.sh e2e https || echo ERR $$?
ingress-nginx-e2e-down ingress-nginx-e2e-tls-down ingress-nginx-e2e-teardown :
	bash ${ADMIN_SRC_DIR}/ingress/ingress-nginx/e2e/test-ingress.sh teardown || echo ERR $$?
ingress-nginx-down ingress-nginx-teardown :
	bash ${ADMIN_SRC_DIR}/${ingress} teardown

trivy :
	bash ${ADMIN_SRC_DIR}/security/trivy/trivy-operator-install.sh

#csi_nfs_dir := csi/nfs-subdir-external-provisioner
csi_nfs_dir := csi/csi-driver-nfs
csi-nfs : csi-nfs2
csi-nfs-down : csi-nfs2-down
csi-nfs-test : csi-nfs2-test
csi-nfs-test-down : csi-nfs2-test-down
csi-nfs2 :
	pushd ${csi_nfs_dir} \
	    && bash csi-driver-nfs.sh install
csi-nfs2-down :
	pushd ${csi_nfs_dir} \
	    && bash csi-driver-nfs.sh teardown
csi-nfs2-test : 
	kubectl apply -f ${csi_nfs_dir}/csi-driver-nfs-test.yaml 
csi-nfs2-test-down : 
	kubectl delete -f ${csi_nfs_dir}/csi-driver-nfs-test.yaml 
csi-nfs1 :
	pushd csi/nfs-subdir-external-provisioner \
	    && bash nfs-subdir-provisioner.sh
csi-nfs1-test : 
	kubectl apply -f csi/nfs-subdir-external-provisioner/app.test-nfs.yaml 

csi-smb : 
	@echo "🛠️  WIP" 
	bash ${ADMIN_SRC_DIR}/csi/csi-driver-smb/csi-driver-smb.sh prep
csi-local :
	bash ${ADMIN_SRC_DIR}/csi/local-path-provisioner/local-path-provisioner.sh
csi-rook-up :
	bash ${ADMIN_SRC_DIR}/csi/rook/rook.sh up
rbd := sdb__VERIFY_OR_MODIFY
## Reboot after rook teardown
csi-rook-down :
	bash ${ADMIN_SRC_DIR}/csi/rook/rook.sh down
	ansibash -u ${ADMIN_SRC_DIR}/csi/rook/rook.sh
	ansibash sudo bash ./rook.sh host_teardown
	ansibash 'sudo wipefs --all /dev/${rbd} && sudo dd if=/dev/zero of=/dev/${rbd} bs=1M count=10'

efk := logging/elastic/efk-chatgpt/stack.sh
efk-apply :
	bash ${ADMIN_SRC_DIR}/${efk} apply
efk-forward :
	bash ${ADMIN_SRC_DIR}/${efk} forward
efk-delete :
	bash ${ADMIN_SRC_DIR}/${efk} delete
efk-verify :
	bash ${ADMIN_SRC_DIR}/${efk} verify

loki := logging/loki/stack.sh
loki-install :
	bash ${ADMIN_SRC_DIR}/${loki} upgrade
loki-delete :
	bash ${ADMIN_SRC_DIR}/${loki} uninstall

kps :=observability/metrics/prometheus-grafana/kps/stack.sh
prom-install prom-apply :
	bash ${ADMIN_SRC_DIR}/${kps} install
prom-access :
	bash ${ADMIN_SRC_DIR}/${kps} access
prom-delete prom-uninstall:
	pkill kubectl \
	    && echo "ℹ️ : Killing all kubectl processes" \
	    || echo "ℹ️ : No kubectl processes were running"
	bash ${ADMIN_SRC_DIR}/${kps} delete

#teardown : calico-teardown cilium-teardown kuberouter-teardown
teardown :
	ansibash -u ${ADMIN_SRC_DIR}/scripts/teardown.sh
	ansibash sudo bash teardown.sh
