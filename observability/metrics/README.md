# [`nicolaka/netshoot`](https://github.com/nicolaka/netshoot "GitHub") | [@ hub.docker.com](https://hub.docker.com/r/nicolaka/netshoot/tags)

Box for Debugging

>a Docker Networking Trouble-shooting Swiss-Army Container


```bash
img=nicolaka/netshoot
k run nbox -it --rm \
    --env TARGET_HOST=$ip \
    --env TARGET_PORT=$p  \
    --image=$img  -- \
    bash
```
```bash
nbox:~# nmap -p 5500-5559 -dd $TARGET_HOST 2>/dev/null |grep open
Discovered open port 5555/tcp on 10.244.182.128
5555/tcp open   freeciv         syn-ack ttl 63
```

```bash
netstat -tulpn
tcpdump -i eth0 port $TARGET_PORT -c 1 -Xvv
...
```

__List of tools__

```bash
apache2-utils
bash
bind-tools
bird
bridge-utils
busybox-extras
calicoctl
conntrack-tools
ctop
curl
dhcping
drill
ethtool
file
fping
httpie
iftop
iperf
iproute2
ipset
iptables
iptraf-ng
iputils
ipvsadm
jq
libc6-compat
liboping
mtr
net-snmp-tools
netcat-openbsd
netgen
nftables
ngrep
nmap
nmap-nping
openssl
py-crypto
py2-virtualenv
python2
scapy
socat
strace
tcpdump
tcptraceroute
termshark
tshark
util-linux
vim
websocat

```

### &nbsp;

## [`k8s-iperf`](https://github.com/sempernow/k8s-iperf "GitHub.com")

```bash
git clone git@github.com:sempernow/k8s-iperf.git
cd k8s-iperf
bash k8s-iperf.sh
```
- [__`k8s-iperf.sh`__](k8s-iperf.sh)

---

# `netperf` v. `iperf`

Here's a comprehensive comparison between **iperf** (particularly iperf3) and **netperf**:

## **Architecture & Design**

### iperf/iperf3:
- **Client-server model** with independent components
- **iperf3** is a complete rewrite with simpler codebase
- Single-threaded design in iperf3
- JSON output support in iperf3

### netperf:
- **netserver** daemon + **netperf** client
- More complex, mature codebase
- Multiple testing methodologies in one tool

## **Feature Comparison**

| Feature | iperf3 | netperf |
|---------|---------|---------|
| **TCP throughput** | ✅ Excellent | ✅ Excellent |
| **UDP throughput** | ✅ Good | ✅ Good |
| **TCP latency** | ❌ Limited | ✅ Excellent (TCP_RR) |
| **UDP latency** | ❌ Limited | ✅ Excellent (UDP_RR) |
| **Bidirectional tests** | ✅ Native | ⚠️ Complex |
| **Multiple streams** | ✅ Easy | ⚠️ Complex |
| **IPv6 support** | ✅ Full | ✅ Full |
| **CPU utilization** | ✅ Reports | ❌ No |
| **JSON output** | ✅ Yes | ❌ No |

## **Testing Capabilities**

### iperf3 Strengths:
```bash
# Easy bidirectional testing
iperf3 -c server -d

# Multiple parallel streams
iperf3 -c server -P 8

# Built-in CPU utilization reporting
iperf3 -c server --get-server-output

# Zero-copy mode for high performance
iperf3 -c server -Z
```

### netperf Strengths:
```bash
# Request/Response latency testing
netperf -H server -t TCP_RR
netperf -H server -t UDP_RR

# Transactional testing
netperf -H server -t TCP_CRR  # Connect-Request-Response

# Specific message sizes
netperf -H server -t TCP_RR -- -r 1,1 -H server
```

## **Performance Metrics**

### What iperf3 measures best:
- **Raw bandwidth** (TCP/UDP)
- **Packet loss** (UDP)
- **Jitter** (UDP)
- **CPU utilization**
- **Retransmissions**

### What netperf measures best:
- **Transaction rate** (transactions/second)
- **Request/response latency**
- **Connection establishment overhead**
- **Protocol efficiency**

## **Ease of Use**

### iperf3:
```bash
# Simple bandwidth test
iperf3 -c 192.168.1.100

# UDP test with bandwidth limit
iperf3 -c 192.168.1.100 -u -b 1G
```

### netperf:
```bash
# More complex syntax
netperf -H 192.168.1.100 -t TCP_STREAM -- -m 1448 -s 1M -S 1M

# Latency test requires understanding of RR tests
netperf -H 192.168.1.100 -t TCP_RR -- -r 64,1024
```

## **Output & Reporting**

### iperf3 Output:
```
[ ID] Interval           Transfer     Bitrate         Retr
[  5]   0.00-10.00  sec  1.10 GBytes   941 Mbits/sec    0             sender
[  5]   0.00-10.00  sec  1.10 GBytes   941 Mbits/sec                  receiver
```

### netperf Output:
```
TCP STREAM TEST from 0.0.0.0 (0.0.0.0) port 0 AF_INET to 192.168.1.100 (192.168.1.100) port 0 AF_INET
Recv   Send    Send                          
Socket Socket  Message  Elapsed              
Size   Size    Size     Time     Throughput  
bytes  bytes   bytes    secs.    10^6bits/sec  

 87380  16384  16384    10.00      946.05
```

## **Use Case Recommendations**

### Choose iperf3 when:
- You need simple bandwidth testing
- You want bidirectional testing
- You need JSON output for automation
- You care about CPU utilization
- You're testing modern networks

### Choose netperf when:
- You need transactional latency measurements
- You're testing application performance
- You need Connect-Request-Response timing
- You're working with legacy systems
- You need specific protocol testing

## **Practical Examples Comparison**

### Bandwidth Test:
**iperf3:**
```bash
iperf3 -c server -t 30 -P 4
```

**netperf:**
```bash
netperf -H server -t TCP_STREAM -l 30 -- -m 1448 -s 256K -S 256K
```

### Latency Test:
**iperf3** (limited):
```bash
# Not ideal for latency
iperf3 -c server -u -b 100M
```

**netperf** (comprehensive):
```bash
# Proper latency testing
netperf -H server -t TCP_RR -- -r 64,1024
netperf -H server -t UDP_RR -- -r 64,1024
```

## **Conclusion**

- **iperf3** is better for **throughput testing** and modern workflows
- **netperf** is better for **latency/transactional testing** and detailed protocol analysis
- **iperf3** has better user experience and output formatting
- **netperf** has more sophisticated testing methodologies

For most network administrators today, **iperf3** is the preferred tool for general bandwidth testing, while **netperf** remains valuable for specific latency-sensitive application testing.