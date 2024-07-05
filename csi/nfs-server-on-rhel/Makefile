##############################################################################
## Makefile.settings : Environment Variables for Makefile(s)
#include Makefile.settings

##############################################################################
## Environment variable rules:
## - Any TRAILING whitespace KILLS its variable value and may break recipes.
## - ESCAPE only that required by the shell (bash).
## - Environment hierarchy:
##   - Makefile environment OVERRIDEs OS environment lest set using `?=`.
##  	  - `FOO ?= bar` is overridden by parent setting; `export FOO=new`.
##  	  - `FOO :=`bar` is NOT overridden by parent setting.
##   - Docker YAML `env_file:` OVERRIDEs OS and Makefile environments.
##   - Docker YAML `environment:` OVERRIDEs YAML `env_file:`.
##   - CMD-inline OVERRIDEs ALL REGARDLESS; `make recipeX FOO=new BAR=new2`.

##############################################################################
## $(INFO) : Usage : `$(INFO) 'What ever'` prints a stylized "@ What ever".
SHELL   := /bin/bash
YELLOW  := "\e[1;33m"
RESTORE := "\e[0m"
INFO    := @bash -c 'printf $(YELLOW);echo "@ $$1";printf $(RESTORE)' MESSAGE

##############################################################################
## Project Meta

export PRJ_ROOT   := $(shell pwd)
export LOG_PREFIX := make.$(shell date '+%Y-%m-%dT%H.%M.%Z')

##############################################################################
## Cluster
export NFS_DOMAIN            ?= lime.lan
export NFS_CIDR              ?= 192.168.11.0/24
export NFS_DC_HOST           ?= dc1
export NFS_SERVER_HOST       ?= a0
export NFS_CLIENT_HOSTS      ?= a1 a2 a3
export NFS_EXPORT_PATH       ?= /srv/nfs/k8s

## ansibash
### Public-key string of ssh user must be in ~/.ssh/authorized_keys of ADMIN_USER at all targets.
#export ADMIN_USER          ?= $(shell id -un)
export ADMIN_USER          ?= u2
export ADMIN_KEY           ?= ${HOME}/.ssh/vm_lime
export ADMIN_HOST          ?= a0
export ADMIN_TARGET_LIST   ?= ${NFS_CLIENT_HOSTS} ${NFS_SERVER_HOST}
export ADMIN_SRC_DIR       ?= $(shell pwd)

export ANSIBASH_TARGET_LIST ?= ${ADMIN_TARGET_LIST}
export ANSIBASH_USER        ?= ${ADMIN_USER}

##############################################################################
## Recipes : Meta

menu :
	$(INFO) 'Provision NFS Server/Clients on RHEL9 integrated with AD and Kerberos'
	@echo "env          : Print Makefile environment"
	@echo "mode         : Fix file mode of this source"
	@echo "html         : Process all MD files to HTML"
	@echo "============== "
	@echo "lvm          : Provision LVM-based store for NFS export"
	@echo "nfs          : Provision NFS Server/Clients on RHEL9 integrated with AD and Kerberos"
	@echo "  -kerberos  : Configure server and client(s) for Kerberos"
	@echo "  -server    : Provision NFS Server on host ${NFS_SERVER_HOST}"
	@echo "  -client    : Provision NFS Client on host ${NFS_CLIENT_HOSTS}"
	@echo "============== "
	@echo "server       : Show NFS server"
	@echo "client       : Show NFS client"
	@echo "============== "
	@echo "nfs-subdir   : Install StorageClass and External Provisioner (nfs-client)"
	@echo "app          : Install test app having mount /data to the NFS"
	@echo "  -up        : Install test app having mount /data to the NFS"
	@echo "  -exec      : Execute a shell into apptest app"
	@echo "  -down      : Teardown the test app"

env :
	$(INFO) 'Environment'
	@echo "PWD=${PRJ_ROOT}"
	@env |grep ADMIN_
	@env |grep NFS_

perms mode : html
	find . -type d ! -path './.git/*' -exec chmod 0755 "{}" \;
	find . -type f ! -path './.git/*' -exec chmod 0644 "{}" \;

html :
	find . -type f ! -path './.git/*' -name '*.md' -exec md2html.exe "{}" \;


##############################################################################
## Recipes : NFS

lvm :
	scp -p ${PRJ_ROOT}/provision-lvm-data-nfs.sh ${ADMIN_USER}@${ADMIN_HOST}:.
	ssh ${ADMIN_USER}@${NFS_SERVER_HOST} sudo bash provision-lvm-data-nfs.sh

# UPDATE : Configure for K8s nfs exclusively (no NFS mounts at any host)
#nfs : nfs-kerberos nfs-server nfs-clients

nfs-kerberos :
	ansibash -u ${PRJ_ROOT}/kerberos/etc.krb5.conf
	ansibash -u ${PRJ_ROOT}/kerberos/etc.sssd.conf
	ansibash -u ${PRJ_ROOT}/etc.chrony.conf
	ansibash 'sudo cp -p etc.chrony.conf /etc/chrony.conf \
	    && sudo chown root:chrony /etc/chrony.conf \
	'
	ansibash 'sudo cp -p etc.krb5.conf /etc/krb5.conf \
	    && sudo chown root:root /etc/krb5.conf \
	'
	ansibash 'sudo cp -p etc.sssd.conf /etc/sssd/sssd.conf \
	    && sudo chown root:root /etc/sssd/sssd.conf \
	    && sudo chmod 600 /etc/sssd/sssd.conf \
	'

nfs-server : lvm
	scp -p ${PRJ_ROOT}/install-nfs-server.sh ${ADMIN_USER}@${ADMIN_HOST}:.
	ansibash sudo systemctl disable --now nfs-server
	ssh ${ADMIN_USER}@${NFS_SERVER_HOST} sudo bash install-nfs-server.sh \
	    ${NFS_EXPORT_PATH} ${NFS_CIDR} ${NFS_DC_HOST}.${NFS_DOMAIN}

nfs-clients nfs-client :
	ANSIBASH_TARGET_LIST="${NFS_CLIENT_HOSTS}" \
		&& ansibash -u ${PRJ_ROOT}/install-nfs-client.sh
	ANSIBASH_TARGET_LIST="${NFS_CLIENT_HOSTS}" \
	    && ansibash sudo systemctl disable --now nfs-client.target
	ANSIBASH_TARGET_LIST="${NFS_CLIENT_HOSTS}" \
	    && ansibash sudo bash install-nfs-client.sh \
	        ${NFS_SERVER_HOST}.${NFS_DOMAIN} ${NFS_EXPORT_PATH} ${NFS_EXPORT_PATH} ${NFS_DC_HOST}.${NFS_DOMAIN}

server :
	ssh ${ADMIN_USER}@${NFS_SERVER_HOST} '\
		sudo journalctl -u nfs-server \
		&& showmount -e localhost \
		&& sudo exportfs -v \
		&& klist \
		&& ls -ahlZR ${NFS_EXPORT_PATH} \
		&& getent group ad-nfsanon \
		&& id nfsanon \
		&& id u1 \
		&& id u2 \
	'

file := $(shell date '+%F_%H.%M.%S')
client :
	ANSIBASH_TARGET_LIST="${NFS_CLIENT_HOSTS}" && ansibash '\
	    df -hT |grep nfs \
		    && mount |grep nfs \
	        && ls -hl /mnt \
	        && ls -hl ${NFS_EXPORT_PATH} \
	        && touch ${NFS_EXPORT_PATH}/${file} \
	        && ls -hl ${NFS_EXPORT_PATH}/${file} \
	        && rm ${NFS_EXPORT_PATH}/${file} \
	'

nfs-subdir :
	pushd ../nfs-subdir-external-provisioner \
		&& bash nfs-subdir-provisioner.sh

app app-up up :
	ssh ${ADMIN_USER}@${NFS_SERVER_HOST} mkdir -p ${NFS_EXPORT_PATH}/test-nfs-pv
	kubectl get pv test-nfs-pv || kubectl -n default apply -f test-nfs-pv.yaml
	kubectl -n default apply -f test-nfs-app.yaml
	sleep 5 && ssh ${ADMIN_USER}@${NFS_SERVER_HOST} ls -ahlRZ ${NFS_EXPORT_PATH}
app-exec exec :
	kubectl -n default exec -it test-nfs-pod -- ls -ahlR /data
app-down down :
	kubectl -n default delete -f test-nfs-app.yaml || echo ok
	kubectl -n default delete -f test-nfs-pv.yaml || echo ok
	ssh ${ADMIN_USER}@${NFS_SERVER_HOST} sudo rm -f ${NFS_EXPORT_PATH}/test-nfs-pv/*
