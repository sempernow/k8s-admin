#!/usr/bin/env bash
#####################################################################
# Configure a user : add user to groups
# - Run this script only after all (RPMs and binaries) installed.
# - Idempotent. 
#
# ARGs: [<The target user>] (default to $USER)
#####################################################################
export _USER=${1:-$USER}
groups='
    docker
    containerd
'
# Why:
# - containerd group allows user to run cri-tools (crictl, critest) 
# - docker group allows user to run docker commands against Docker engine
_addto(){
    # Add user to group ($1) : idempotent
    echo "=== @ $1"
    [[ $(groups $_USER |grep $1) ]] && {
        echo "WARN : User '$_USER' is ALREADY MEMBER of group '$1'."
        return 0
    } || {
        [[ $(cat /etc/group |grep $1) ]] || {
            echo "ERROR : Group '$1' does NOT EXIST."
            return 1
        }
        sudo usermod -aG $1 $_USER || { 
            echo "ERROR : User '$_USER' NOT added to group '$1'."
            return 1
        }
        echo "INFO : User '$_USER' added to group '$1'."
    }
}
export -f _addto
printf "%s\n" $groups |xargs -IX /bin/bash -c '_addto $1' _ X

echo "INFO : A new member cannot access the group until their next login shell."
