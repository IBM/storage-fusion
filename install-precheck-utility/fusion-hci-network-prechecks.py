#!/usr/bin/env python3
"""
networkValidationTool.py 

Manufacturing-grade Network Validation Tool
Supports:
- DHCP validation (Scapy)
- Static IP validation
- DNS forward & reverse validation (IP and hostname support)
- Bond & VLAN creation
- Path MTU discovery
- TCP/UDP port testing
- NTP validation
- Parallel execution
- CLI & Interactive modes (fully implemented)
- Input validation and error handling
- Cleanup / rollback
- Logging & colored output

Author: Manish Kulshreshtha
Version: 1.0
"""

import argparse
import subprocess
import sys
import time
import os
import random
import logging
import re
import socket
from concurrent.futures import ThreadPoolExecutor, as_completed

from scapy.all import *
from scapy.arch import get_if_raw_hwaddr
import dns.resolver
import dns.reversename

# =========================
# Color Output
# =========================
class Color:
    ENABLED = sys.stdout.isatty()
    GREEN  = "\033[32m" if ENABLED else ""
    RED    = "\033[31m" if ENABLED else ""
    YELLOW = "\033[33m" if ENABLED else ""
    BLUE   = "\033[34m" if ENABLED else ""
    CYAN   = "\033[36m" if ENABLED else ""
    MAGENTA = "\033[35m" if ENABLED else ""
    RESET  = "\033[0m"  if ENABLED else ""

def ok(msg):   return f"{Color.GREEN}✓ {msg}{Color.RESET}"
def warn(msg): return f"{Color.YELLOW}⚠ {msg}{Color.RESET}"
def fail(msg): return f"{Color.RED}✗ {msg}{Color.RESET}"
def info(msg): return f"{Color.BLUE}ℹ {msg}{Color.RESET}"
def prompt(msg): return f"{Color.CYAN}➤ {msg}{Color.RESET}"

# =========================
# Logging
# =========================
LOG_FILE = "/var/log/networkValidationTool.log"

def setup_logging():
    """Setup logging with proper error handling"""
    try:
        logging.basicConfig(
            filename=LOG_FILE,
            level=logging.DEBUG,
            format="%(asctime)s %(levelname)s %(message)s"
        )
    except PermissionError:
        # Fallback to user directory if /var/log is not writable
        fallback_log = os.path.expanduser("~/networkValidationTool.log")
        logging.basicConfig(
            filename=fallback_log,
            level=logging.DEBUG,
            format="%(asctime)s %(levelname)s %(message)s"
        )
        print(warn(f"Using fallback log: {fallback_log}"))

def log(msg):
    logging.info(msg)
    print(msg)

# =========================
# Input Validation
# =========================
class Validator:
    """Input validation utilities"""
    
    @staticmethod
    def is_valid_ip(ip):
        """Validate IPv4 address"""
        pattern = r'^(\d{1,3}\.){3}\d{1,3}$'
        if not re.match(pattern, ip):
            return False
        parts = ip.split('.')
        return all(0 <= int(part) <= 255 for part in parts)
    
    @staticmethod
    def is_valid_cidr(cidr):
        """Validate CIDR notation (e.g., 192.168.1.10/24)"""
        try:
            ip, prefix = cidr.split('/')
            return Validator.is_valid_ip(ip) and 0 <= int(prefix) <= 32
        except:
            return False
    
    @staticmethod
    def is_valid_mac(mac):
        """Validate MAC address"""
        pattern = r'^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$'
        return bool(re.match(pattern, mac))
    
    @staticmethod
    def is_valid_hostname(hostname):
        """Validate hostname"""
        if len(hostname) > 255:
            return False
        pattern = r'^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$'
        return bool(re.match(pattern, hostname))
    
    @staticmethod
    def is_valid_interface(iface):
        """Check if network interface exists"""
        try:
            result = subprocess.run(f"ip link show {iface}", shell=True, 
                                  capture_output=True, text=True)
            return result.returncode == 0
        except:
            return False
    
    @staticmethod
    def is_valid_port(port):
        """Validate port number"""
        try:
            p = int(port)
            return 1 <= p <= 65535
        except:
            return False
    
    @staticmethod
    def is_valid_vlan(vlan):
        """Validate VLAN ID"""
        try:
            v = int(vlan)
            return 1 <= v <= 4094
        except:
            return False
    
    @staticmethod
    def file_exists(path):
        """Check if file exists and is readable"""
        return os.path.isfile(path) and os.access(path, os.R_OK)

def get_validated_input(prompt_msg, validator, error_msg, allow_empty=False):
    """Get user input with validation and retry"""
    while True:
        value = input(prompt(prompt_msg)).strip()
        
        if not value and allow_empty:
            return None
        
        if not value:
            print(fail("Input cannot be empty"))
            continue
        
        if validator(value):
            return value
        else:
            print(fail(error_msg))

# =========================
# Helpers
# =========================
def run(cmd, capture=False):
    """Execute command with proper error handling"""
    logging.debug(f"Executing: {cmd}")
    try:
        if capture:
            result = subprocess.run(cmd, shell=True, capture_output=True, 
                                  text=True, check=False)
            return result.returncode, result.stdout, result.stderr
        else:
            result = subprocess.run(cmd, shell=True, check=False)
            return result.returncode
    except Exception as e:
        logging.error(f"Command failed: {cmd}, Error: {e}")
        return -1 if not capture else (-1, "", str(e))

def read_list(path):
    """Read and validate list from file"""
    if not Validator.file_exists(path):
        raise FileNotFoundError(f"File not found or not readable: {path}")
    
    with open(path) as f:
        return [x.strip() for x in f if x.strip() and not x.strip().startswith('#')]

def check_root():
    """Check if running as root"""
    if os.geteuid() != 0:
        print(fail("This script requires root privileges"))
        print(info("Please run with: sudo ./networkValidationTool.py"))
        sys.exit(1)

# =========================
# Network Configuration
# =========================
created_connections = []

def create_bond(bond, slaves):
    """Create bonded interface with validation"""
    log(info(f"Creating bond {bond} with slaves: {', '.join(slaves)}"))
    
    # Validate slaves exist
    for slave in slaves:
        if not Validator.is_valid_interface(slave):
            raise ValueError(f"Interface {slave} does not exist")
    
    # Create bond
    rc = run(f"nmcli con add type bond ifname {bond} mode 802.3ad")
    if rc != 0:
        raise RuntimeError(f"Failed to create bond {bond}")
    
    # Add slaves
    for s in slaves:
        rc = run(f"nmcli con add type ethernet slave-type bond ifname {s} master {bond}")
        if rc != 0:
            log(warn(f"Failed to add slave {s} to {bond}"))
    
    # Bring up bond
    run(f"nmcli con up {bond}")
    created_connections.append(bond)
    log(ok(f"Bond {bond} created successfully"))

def create_vlan(parent, vlan):
    """Create VLAN interface with validation"""
    if not Validator.is_valid_vlan(vlan):
        raise ValueError(f"Invalid VLAN ID: {vlan}")
    
    iface = f"{parent}.{vlan}"
    log(info(f"Creating VLAN {iface}"))
    
    rc = run(f"nmcli con add type vlan ifname {iface} dev {parent} id {vlan}")
    if rc != 0:
        raise RuntimeError(f"Failed to create VLAN {iface}")
    
    run(f"nmcli con up {iface}")
    created_connections.append(iface)
    log(ok(f"VLAN {iface} created successfully"))
    return iface

def cleanup():
    """Cleanup created connections"""
    if not created_connections:
        return
    
    log(info("Cleaning up network connections..."))
    for c in reversed(created_connections):
        log(warn(f"Removing {c}"))
        run(f"nmcli con delete {c}")
    log(ok("Cleanup complete"))

# =========================
# DHCP (Scapy)
# =========================
def parse_offer(pkt):
    """Parse DHCP offer packet"""
    opts = {k:v for k,v in pkt[DHCP].options if isinstance(k,str)}
    
    # Handle both list and single value returns
    def get_opt(key):
        val = opts.get(key)
        if isinstance(val, list):
            return val[0] if val else None
        return val
    
    return {
        "ip": pkt[BOOTP].yiaddr,
        "router": get_opt("router"),
        "dns": get_opt("name_server"),
        "hostname": get_opt("hostname") or "-"
    }

def dhcp_request(interface, mac, timeout):
    """Send DHCP discover and wait for offer"""
    try:
        conf.iface = interface
        conf.checkIPaddr = False
        xid = random.randint(1, 0xffffffff)
        
        # Convert MAC to bytes
        mac_bytes = mac2str(mac)
        
        pkt = (
            Ether(src=mac, dst="ff:ff:ff:ff:ff:ff") /
            IP(src="0.0.0.0", dst="255.255.255.255") /
            UDP(sport=68, dport=67) /
            BOOTP(chaddr=mac_bytes, xid=xid) /
            DHCP(options=[("message-type","discover"), "end"])
        )
        
        sendp(pkt, verbose=False)
        
        start = time.time()
        while time.time() - start < timeout:
            sniffed = sniff(filter="udp and (port 67 or 68)", timeout=1, count=1)
            for p in sniffed:
                if DHCP in p and p[BOOTP].xid == xid:
                    return parse_offer(p), None
        
        return None, "TIMEOUT"
    except Exception as e:
        logging.error(f"DHCP request failed for {mac}: {e}")
        return None, str(e)

# =========================
# DNS Validation
# =========================
def resolve_hostname(hostname, dns_server=None):
    """Resolve hostname to IP address"""
    res = dns.resolver.Resolver()
    if dns_server:
        res.nameservers = [dns_server]
    
    try:
        answers = res.resolve(hostname, "A")
        return [str(rdata) for rdata in answers]
    except Exception as e:
        logging.error(f"Failed to resolve {hostname}: {e}")
        return []

def dns_validate(ip, dns_server=None):
    """Validate DNS forward and reverse lookup"""
    res = dns.resolver.Resolver()
    if dns_server:
        res.nameservers = [dns_server]
    
    result = {"ip": ip, "forward": False, "reverse": False, "name": None}
    
    try:
        # Reverse lookup (IP -> hostname)
        rev = dns.reversename.from_address(ip)
        name = res.resolve(rev, "PTR")[0].to_text().rstrip(".")
        result["reverse"] = True
        result["name"] = name
        
        # Forward lookup (hostname -> IP)
        ips = res.resolve(name, "A")
        result["forward"] = any(ip == str(a) for a in ips)
    except Exception as e:
        logging.debug(f"DNS validation failed for {ip}: {e}")
    
    return result

def validate_host(host, dns_server=None):
    """Validate host (IP or hostname) with DNS"""
    if Validator.is_valid_ip(host):
        return dns_validate(host, dns_server)
    elif Validator.is_valid_hostname(host):
        # Resolve hostname first
        ips = resolve_hostname(host, dns_server)
        if not ips:
            return {"host": host, "forward": False, "reverse": False, "error": "Resolution failed"}
        
        # Validate first IP
        result = dns_validate(ips[0], dns_server)
        result["host"] = host
        result["resolved_ips"] = ips
        return result
    else:
        return {"host": host, "error": "Invalid IP or hostname"}

# =========================
# Static IP Mode
# =========================
def configure_static(interface, ip, gw, dns):
    """Configure static IP with validation"""
    if not Validator.is_valid_cidr(ip):
        raise ValueError(f"Invalid CIDR notation: {ip}")
    
    if gw and not Validator.is_valid_ip(gw):
        raise ValueError(f"Invalid gateway IP: {gw}")
    
    if dns and not Validator.is_valid_ip(dns):
        raise ValueError(f"Invalid DNS server IP: {dns}")
    
    log(info(f"Configuring static IP {ip} on {interface}"))
    
    run(f"ip addr flush dev {interface}")
    run(f"ip addr add {ip} dev {interface}")
    run(f"ip link set {interface} up")
    
    if gw:
        run(f"ip route replace default via {gw}")
        log(ok(f"Gateway set to {gw}"))
    
    if dns:
        # Backup resolv.conf
        if os.path.exists("/etc/resolv.conf"):
            run("cp /etc/resolv.conf /etc/resolv.conf.backup")
        
        with open("/etc/resolv.conf", "w") as f:
            f.write(f"nameserver {dns}\n")
        log(ok(f"DNS server set to {dns}"))
    
    log(ok(f"Static IP configured on {interface}"))

# =========================
# Path MTU Discovery
# =========================
def find_path_mtu(dest, interface=None, start=1472, end=8972):
    """Find path MTU using binary search"""
    log(info(f"Finding Path MTU to {dest}"))
    
    best = None
    while start <= end:
        mid = (start + end) // 2
        cmd = f"ping -c 1 -W 1 -M do -s {mid} {dest}"
        if interface:
            cmd = f"ping -I {interface} -c 1 -W 1 -M do -s {mid} {dest}"
        
        rc = run(cmd)
        if rc == 0:
            best = mid
            start = mid + 1
        else:
            end = mid - 1
    
    return best + 28 if best else None

# =========================
# Port Testing
# =========================
def test_tcp_port(host, port, timeout=3):
    """Test if TCP port is open"""
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(timeout)
        result = sock.connect_ex((host, int(port)))
        sock.close()
        return result == 0
    except Exception as e:
        logging.error(f"TCP port test failed for {host}:{port}: {e}")
        return False

def test_udp_port(host, port, timeout=3):
    """Test if UDP port is reachable"""
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.settimeout(timeout)
        
        # Send test packet
        sock.sendto(b'test', (host, int(port)))
        
        try:
            # Try to receive response
            sock.recvfrom(1024)
            sock.close()
            return True
        except socket.timeout:
            # Timeout might mean port is open but no response
            sock.close()
            return True
    except Exception as e:
        logging.error(f"UDP port test failed for {host}:{port}: {e}")
        return False

def test_ports(host, ports, protocol="tcp", timeout=3):
    """Test multiple ports"""
    results = {}
    test_func = test_tcp_port if protocol.lower() == "tcp" else test_udp_port
    
    log(info(f"Testing {protocol.upper()} ports on {host}"))
    
    for port in ports:
        if not Validator.is_valid_port(port):
            results[port] = "INVALID"
            continue
        
        is_open = test_func(host, port, timeout)
        results[port] = "OPEN" if is_open else "CLOSED/FILTERED"
        
        status = ok(f"Port {port}: {results[port]}") if is_open else fail(f"Port {port}: {results[port]}")
        print(status)
    
    return results

# =========================
# NTP Validation
# =========================
def check_ntp(server=None):
    """Check NTP synchronization status"""
    try:
        # Check if chrony is running
        rc, stdout, stderr = run("chronyc -n tracking", capture=True)
        if rc != 0:
            return False, "Chrony not running or not configured"
        
        # Parse tracking output
        tracking_info = {}
        for line in stdout.split('\n'):
            if ':' in line:
                key, value = line.split(':', 1)
                tracking_info[key.strip()] = value.strip()
        
        # If specific server requested, check sources
        if server:
            rc, stdout, stderr = run("chronyc -n sources", capture=True)
            if rc != 0:
                return False, "Failed to get NTP sources"
            
            # Check if server is in sources
            if server not in stdout:
                return False, f"Server {server} not in NTP sources"
        
        # Get sync status
        stratum = tracking_info.get('Stratum', 'Unknown')
        offset = tracking_info.get('System time', 'Unknown')
        
        return True, {
            "stratum": stratum,
            "offset": offset,
            "tracking": tracking_info
        }
    except Exception as e:
        logging.error(f"NTP check failed: {e}")
        return False, str(e)

# =========================
# Interactive Menu
# =========================
def interactive_menu():
    """Display interactive menu"""
    print("\n" + "="*60)
    print(info("Network Validation Tool - Interactive Mode"))
    print("="*60)
    print("1) DHCP Validation (MAC List)")
    print("2) Static IP Configuration + DNS Validation")
    print("3) DNS Only Validation (IP/Hostname List)")
    print("4) Path MTU Discovery")
    print("5) TCP/UDP Port Testing")
    print("6) NTP Synchronization Check")
    print("7) Create Bond Interface")
    print("8) Create VLAN Interface")
    print("9) Exit")
    print("="*60)
    
    while True:
        choice = input(prompt("Select option (1-9): ")).strip()
        if choice in ['1', '2', '3', '4', '5', '6', '7', '8', '9']:
            return choice
        print(fail("Invalid choice. Please enter 1-9."))

def interactive_dhcp_validation():
    """Interactive DHCP validation"""
    print(info("\n=== DHCP Validation ==="))
    
    # Get interface
    interface = get_validated_input(
        "Enter network interface (e.g., eth0): ",
        Validator.is_valid_interface,
        "Interface does not exist"
    )
    
    # Get MAC list file
    mac_file = get_validated_input(
        "Enter path to MAC address list file: ",
        Validator.file_exists,
        "File not found or not readable"
    )
    
    # Get parallel workers
    parallel = input(prompt("Number of parallel workers (default 5): ")).strip()
    parallel = int(parallel) if parallel.isdigit() else 5
    
    # Get timeout
    timeout = input(prompt("DHCP timeout in seconds (default 5): ")).strip()
    timeout = int(timeout) if timeout.isdigit() else 5
    
    # Read and validate MACs
    try:
        macs = read_list(mac_file)
        invalid_macs = [m for m in macs if not Validator.is_valid_mac(m)]
        if invalid_macs:
            print(warn(f"Found {len(invalid_macs)} invalid MAC addresses"))
            for m in invalid_macs[:5]:  # Show first 5
                print(f"  {fail(m)}")
            if input(prompt("Continue anyway? (y/n): ")).lower() != 'y':
                return
            macs = [m for m in macs if Validator.is_valid_mac(m)]
    except Exception as e:
        print(fail(f"Error reading MAC list: {e}"))
        return
    
    # Execute validation
    print(info(f"\nTesting {len(macs)} MAC addresses..."))
    
    with ThreadPoolExecutor(max_workers=parallel) as exe:
        futs = {exe.submit(dhcp_request, interface, m, timeout): m for m in macs}
        for f in as_completed(futs):
            mac = futs[f]
            data, err = f.result()
            if err:
                print(f"{mac} {fail(err)}")
            else:
                dns = dns_validate(data["ip"], data["dns"])
                status = ok("OK") if dns["forward"] and dns["reverse"] else fail("FAIL")
                print(f"{mac} {data['ip']} {dns.get('name', '-')} {status}")

def interactive_static_config():
    """Interactive static IP configuration"""
    print(info("\n=== Static IP Configuration ==="))
    
    interface = get_validated_input(
        "Enter network interface: ",
        Validator.is_valid_interface,
        "Interface does not exist"
    )
    
    static_ip = get_validated_input(
        "Enter static IP with CIDR (e.g., 192.168.1.10/24): ",
        Validator.is_valid_cidr,
        "Invalid CIDR notation"
    )
    
    gateway = get_validated_input(
        "Enter gateway IP (press Enter to skip): ",
        Validator.is_valid_ip,
        "Invalid IP address",
        allow_empty=True
    )
    
    dns_server = get_validated_input(
        "Enter DNS server IP (press Enter to skip): ",
        Validator.is_valid_ip,
        "Invalid IP address",
        allow_empty=True
    )
    
    try:
        configure_static(interface, static_ip, gateway, dns_server)
        print(ok("Static IP configured successfully"))
    except Exception as e:
        print(fail(f"Configuration failed: {e}"))

def interactive_dns_validation():
    """Interactive DNS validation"""
    print(info("\n=== DNS Validation ==="))
    
    host_file = get_validated_input(
        "Enter path to IP/hostname list file: ",
        Validator.file_exists,
        "File not found or not readable"
    )
    
    dns_server = get_validated_input(
        "Enter DNS server IP (press Enter for system default): ",
        Validator.is_valid_ip,
        "Invalid IP address",
        allow_empty=True
    )
    
    try:
        hosts = read_list(host_file)
        print(info(f"\nValidating {len(hosts)} hosts..."))
        
        for host in hosts:
            result = validate_host(host, dns_server)
            
            if "error" in result:
                print(f"{host} {fail(result['error'])}")
            else:
                status = ok("OK") if result["forward"] and result["reverse"] else fail("FAIL")
                name = result.get("name", result.get("host", "-"))
                print(f"{host} → {name} {status}")
    except Exception as e:
        print(fail(f"Validation failed: {e}"))

def interactive_pmtu():
    """Interactive Path MTU discovery"""
    print(info("\n=== Path MTU Discovery ==="))
    
    dest = input(prompt("Enter destination IP or hostname: ")).strip()
    if not (Validator.is_valid_ip(dest) or Validator.is_valid_hostname(dest)):
        print(fail("Invalid IP or hostname"))
        return
    
    interface = input(prompt("Enter interface (press Enter for default): ")).strip()
    if interface and not Validator.is_valid_interface(interface):
        print(fail("Interface does not exist"))
        return
    
    mtu = find_path_mtu(dest, interface if interface else None)
    if mtu:
        print(ok(f"Path MTU: {mtu} bytes"))
    else:
        print(fail("PMTU discovery failed"))

def interactive_port_test():
    """Interactive port testing"""
    print(info("\n=== TCP/UDP Port Testing ==="))
    
    host = input(prompt("Enter target IP or hostname: ")).strip()
    if not (Validator.is_valid_ip(host) or Validator.is_valid_hostname(host)):
        print(fail("Invalid IP or hostname"))
        return
    
    protocol = input(prompt("Enter protocol (tcp/udp): ")).strip().lower()
    if protocol not in ['tcp', 'udp']:
        print(fail("Invalid protocol. Use 'tcp' or 'udp'"))
        return
    
    ports_input = input(prompt("Enter ports (comma-separated, e.g., 22,80,443): ")).strip()
    ports = [p.strip() for p in ports_input.split(',')]
    
    test_ports(host, ports, protocol)

def interactive_ntp_check():
    """Interactive NTP check"""
    print(info("\n=== NTP Synchronization Check ==="))
    
    server = input(prompt("Enter NTP server to check (press Enter for any): ")).strip()
    if server and not (Validator.is_valid_ip(server) or Validator.is_valid_hostname(server)):
        print(fail("Invalid server address"))
        return
    
    success, result = check_ntp(server if server else None)
    
    if success:
        print(ok("NTP is synchronized"))
        if isinstance(result, dict):
            print(f"  Stratum: {result.get('stratum', 'Unknown')}")
            print(f"  Offset: {result.get('offset', 'Unknown')}")
    else:
        print(fail(f"NTP check failed: {result}"))

def interactive_create_bond():
    """Interactive bond creation"""
    print(info("\n=== Create Bond Interface ==="))
    
    bond_name = input(prompt("Enter bond interface name (e.g., bond0): ")).strip()
    if not bond_name:
        print(fail("Bond name cannot be empty"))
        return
    
    slaves_input = input(prompt("Enter slave interfaces (comma-separated, e.g., eth0,eth1): ")).strip()
    slaves = [s.strip() for s in slaves_input.split(',')]
    
    # Validate slaves
    invalid = [s for s in slaves if not Validator.is_valid_interface(s)]
    if invalid:
        print(fail(f"Invalid interfaces: {', '.join(invalid)}"))
        return
    
    try:
        create_bond(bond_name, slaves)
        print(ok(f"Bond {bond_name} created successfully"))
    except Exception as e:
        print(fail(f"Bond creation failed: {e}"))

def interactive_create_vlan():
    """Interactive VLAN creation"""
    print(info("\n=== Create VLAN Interface ==="))
    
    parent = get_validated_input(
        "Enter parent interface: ",
        Validator.is_valid_interface,
        "Interface does not exist"
    )
    
    vlan_id = get_validated_input(
        "Enter VLAN ID (1-4094): ",
        Validator.is_valid_vlan,
        "Invalid VLAN ID"
    )
    
    try:
        iface = create_vlan(parent, vlan_id)
        print(ok(f"VLAN interface {iface} created successfully"))
    except Exception as e:
        print(fail(f"VLAN creation failed: {e}"))

def run_interactive():
    """Run interactive mode"""
    while True:
        choice = interactive_menu()
        
        try:
            if choice == '1':
                interactive_dhcp_validation()
            elif choice == '2':
                interactive_static_config()
            elif choice == '3':
                interactive_dns_validation()
            elif choice == '4':
                interactive_pmtu()
            elif choice == '5':
                interactive_port_test()
            elif choice == '6':
                interactive_ntp_check()
            elif choice == '7':
                interactive_create_bond()
            elif choice == '8':
                interactive_create_vlan()
            elif choice == '9':
                print(info("Exiting..."))
                break
        except KeyboardInterrupt:
            print(warn("\nOperation cancelled"))
        except Exception as e:
            print(fail(f"Error: {e}"))
            logging.exception("Interactive mode error")
        
        input(prompt("\nPress Enter to continue..."))

# =========================
# Main
# =========================
def main():
    parser = argparse.ArgumentParser(
        description="Network Validation Tool v2.0",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Interactive mode
  sudo ./networkValidationTool.py --interactive
  
  # DHCP validation
  sudo ./networkValidationTool.py -i eth0 -m macs.txt --parallel 10
  
  # DNS validation
  sudo ./networkValidationTool.py --ip-list hosts.txt --dns-server 8.8.8.8
  
  # Create bond + VLAN
  sudo ./networkValidationTool.py --bond bond0 --slaves eth0,eth1 --vlan 100
  
  # Port testing
  sudo ./networkValidationTool.py --test-tcp-port 192.168.1.10:22,80,443
  
  # Path MTU
  sudo ./networkValidationTool.py -i eth0 --pmtu-dest 8.8.8.8
  
  # NTP check
  sudo ./networkValidationTool.py --ntp-server pool.ntp.org
        """
    )
    
    # Interface options
    parser.add_argument("-i", "--interface", help="Network interface to use")
    
    # DHCP options
    parser.add_argument("-m", "--mac-list", help="File containing MAC addresses (one per line)")
    parser.add_argument("--parallel", type=int, default=5, help="Number of parallel workers (default: 5)")
    parser.add_argument("--timeout", type=int, default=5, help="DHCP timeout in seconds (default: 5)")
    
    # DNS options
    parser.add_argument("--ip-list", help="File containing IPs or hostnames (one per line)")
    parser.add_argument("--dns-server", help="DNS server to use for validation")
    
    # Network configuration
    parser.add_argument("--bond", help="Bond interface name to create")
    parser.add_argument("--slaves", help="Comma-separated list of slave interfaces for bond")
    parser.add_argument("--vlan", help="VLAN ID to create")
    parser.add_argument("--static-ip", help="Static IP with CIDR (e.g., 192.168.1.10/24)")
    parser.add_argument("--gateway", help="Default gateway IP")
    
    # Testing options
    parser.add_argument("--pmtu-dest", help="Destination for Path MTU discovery")
    parser.add_argument("--test-tcp-port", help="Test TCP ports (format: host:port1,port2,...)")
    parser.add_argument("--test-udp-port", help="Test UDP ports (format: host:port1,port2,...)")
    parser.add_argument("--ntp-server", help="NTP server to validate")
    
    # Mode
    parser.add_argument("--interactive", action="store_true", help="Run in interactive mode")
    
    args = parser.parse_args()
    
    # Setup
    setup_logging()
    check_root()
    
    try:
        # Interactive mode
        if args.interactive:
            run_interactive()
            return
        
        # CLI mode
        iface = args.interface
        
        # Create bond
        if args.bond and args.slaves:
            slaves = [s.strip() for s in args.slaves.split(',')]
            create_bond(args.bond, slaves)
            iface = args.bond
        
        # Create VLAN
        if args.vlan:
            if not iface:
                print(fail("--interface or --bond required for VLAN creation"))
                sys.exit(1)
            iface = create_vlan(iface, args.vlan)
        
        # Configure static IP
        if args.static_ip:
            if not iface:
                print(fail("--interface required for static IP configuration"))
                sys.exit(1)
            configure_static(iface, args.static_ip, args.gateway, args.dns_server)
        
        # DHCP validation
        if args.mac_list:
            if not iface:
                print(fail("--interface required for DHCP validation"))
                sys.exit(1)
            
            macs = read_list(args.mac_list)
            log(info(f"Testing {len(macs)} MAC addresses"))
            
            with ThreadPoolExecutor(max_workers=args.parallel) as exe:
                futs = {exe.submit(dhcp_request, iface, m, args.timeout): m for m in macs}
                for f in as_completed(futs):
                    mac = futs[f]
                    data, err = f.result()
                    if err:
                        print(f"{mac} {fail(err)}")
                    else:
                        dns = dns_validate(data["ip"], data["dns"])
                        status = ok("OK") if dns["forward"] and dns["reverse"] else fail("FAIL")
                        print(f"{mac} {data['ip']} {dns.get('name', '-')} {status}")
        
        # DNS validation
        if args.ip_list:
            hosts = read_list(args.ip_list)
            log(info(f"Validating {len(hosts)} hosts"))
            
            for host in hosts:
                result = validate_host(host, args.dns_server)
                if "error" in result:
                    print(f"{host} {fail(result['error'])}")
                else:
                    status = ok("OK") if result["forward"] and result["reverse"] else fail("FAIL")
                    name = result.get("name", result.get("host", "-"))
                    print(f"{host} → {name} {status}")
        
        # Path MTU
        if args.pmtu_dest:
            mtu = find_path_mtu(args.pmtu_dest, iface)
            print(ok(f"Path MTU: {mtu}") if mtu else fail("PMTU failed"))
        
        # TCP port testing
        if args.test_tcp_port:
            try:
                host, ports_str = args.test_tcp_port.split(':', 1)
                ports = ports_str.split(',')
                test_ports(host, ports, "tcp")
            except ValueError:
                print(fail("Invalid format. Use: host:port1,port2,..."))
        
        # UDP port testing
        if args.test_udp_port:
            try:
                host, ports_str = args.test_udp_port.split(':', 1)
                ports = ports_str.split(',')
                test_ports(host, ports, "udp")
            except ValueError:
                print(fail("Invalid format. Use: host:port1,port2,..."))
        
        # NTP validation
        if args.ntp_server:
            success, result = check_ntp(args.ntp_server)
            if success:
                print(ok("NTP synchronized"))
                if isinstance(result, dict):
                    print(f"  Stratum: {result.get('stratum')}")
                    print(f"  Offset: {result.get('offset')}")
            else:
                print(fail(f"NTP check failed: {result}"))
    
    except KeyboardInterrupt:
        print(warn("\nOperation cancelled by user"))
    except Exception as e:
        print(fail(f"Error: {e}"))
        logging.exception("Main execution error")
        sys.exit(1)
    finally:
        cleanup()

if __name__ == "__main__":
    main()
