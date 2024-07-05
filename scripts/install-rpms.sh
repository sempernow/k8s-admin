#!/usr/bin/env bash
######################################
# Install RPMs : K8s deps and tools
######################################
[[ "$(id -u)" -ne 0 ]] && {
    echo "⚠️  ERR : MUST run as root" >&2

    exit 11
}

ok(){
    # K8s dependency
    dnf -y --color=never install conntrack || return 22

    # Tools
    all='
    dnf-plugins-core
    selinux-policy
    selinux-policy-targeted 
    libselinux-utils
    policycoreutils
    setools 
    setroubleshoot 
    setroubleshoot-server 
    policycoreutils-python-utils 
    gcc 
    make 
    ansible 
    ansible-core 
    iproute-tc 
    bash-completion 
    bind-utils 
    tar 
    nc 
    socat 
    rsync 
    lsof 
    wget 
    curl 
    net-tools 
    ipvsadm 
    tcpdump 
    traceroute 
    nmap 
    arp-scan 
    git 
    httpd 
    httpd-tools 
    jq 
    vim 
    tree 
    htop 
    sysstat 
    fio 
    pciutils 
    '
    dnf -y --color=never install $all || return 33
}
ok || exit $?

securityProfile(){

    ## DISA STIG tools
    all='
    scap-security-guide 
    openscap-scanner 
    aide 
    policycoreutils 
    policycoreutils-python-utils 
    setroubleshoot-server 
    setools 
    setools-console 
    selinux-policy-devel
    rsyslog 
    audit 
    tmux 
    vim-enhanced 
    bash-completion 
    tar
    '
    dnf -y --color=never install $all || return 44

    ## Config
    stig(){
        # Initialize AIDE:
        sudo aide --init
        sudo cp /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz

        rhelVerXML=ssg-rhel9-ds.xml 

        # Run an OSCAP Scan to Check Compliance
        sudo oscap xccdf eval \
            --profile xccdf_org.ssgproject.content_profile_stig \
            --report stig-scan-report.html /usr/share/xml/scap/ssg/content/$rhelVerXML

        # Run an OSCAP Scan to Remediate (Use with Caution!):
        # Automatic remediation is powerful but can break functionality.
        # Test this in a non-production environment first!
        # This command will attempt to automatically fix all the rules it can. 
        sudo oscap xccdf eval \
            --profile xccdf_org.ssgproject.content_profile_stig \
            --remediate /usr/share/xml/scap/ssg/content/$rhelVerXML
    }
}
#securityProfile || exit $?