# Network Validation Tool Documentation

A comprehensive network validation and configuration tool for RHEL 9 systems, designed for manufacturing-grade network testing and deployment automation.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Usage](#usage)
- [Menu Options](#menu-options)
- [Input File Formats](#input-file-formats)
- [Technical Details](#technical-details)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)

## Overview

The Network Validation Tool (`fusion-hci-network-prechecks.py`) is a production-ready Python script for automated network configuration and validation on RHEL 9 systems. It provides an interactive menu-driven interface for:

- Creating and managing bond interfaces (LACP)
- Creating and managing VLAN interfaces
- Configuring static IP addresses
- Validating DNS resolution (with wildcard support)
- Testing DHCP server responses
- Checking NTP synchronization
- Testing TCP/UDP port connectivity
- Discovering Path MTU
- Verifying bond interface status

The tool uses `tcpdump` for reliable DHCP packet capture and `NetworkManager (nmcli)` for persistent network configuration.

## Features

### 1. Bond Interface Management

- Create IEEE 802.3ad (LACP) bond interfaces
- Automatic slave interface configuration
- Real-time bond status verification
- LACP aggregator validation
- Automatic rollback on failure

### 2. VLAN Interface Management

- Create VLAN interfaces on any parent interface
- Support for VLAN IDs 1-4094
- Automatic placeholder IP configuration for stable testing
- NetworkManager integration for persistence

### 3. Static IP Configuration

- Configure static IP with CIDR notation
- Set gateway and DNS servers
- Automatic NetworkManager profile creation
- Persistent across reboots

### 4. DNS Validation

- Forward DNS lookup (hostname → IP)
- Reverse DNS lookup (IP → hostname)
- Wildcard DNS support (*.apps.example.com)
- Mixed IP and hostname input
- Custom DNS server support
- Bidirectional validation with mismatch detection

### 5. DHCP Validation

- TCPdump-based packet capture for reliability
- Sequential MAC address testing
- Configurable timeout
- Automatic retry on transient failures
- Detailed error reporting with packet counts
- Support for DHCP relay/proxy scenarios

### 6. NTP Synchronization

- Automatic NTP client configuration
- Server synchronization verification
- Chrony integration
- Detailed synchronization status

### 7. Port Testing

- TCP port connectivity testing
- UDP port reachability testing
- Configurable timeout
- Batch port testing support

### 8. Path MTU Discovery

- Binary search algorithm for MTU detection
- Initial connectivity check (ARP cache warm-up)
- Don't Fragment (DF) bit support
- Interface-specific testing

### 9. Bond Status Verification

- Real-time bond mode display
- Slave interface status
- LACP aggregator verification
- Link state monitoring

## Requirements

### System Requirements

- **Operating System:** RHEL 9 or compatible
- **Python Version:** Python 3.6+
- **Root Access:** Required for network operations

### Python Dependencies

```bash
pip3 install scapy dnspython
```

### System Packages

```bash
dnf install -y tcpdump NetworkManager chrony
```

### Network Requirements

- NetworkManager service must be running
- Physical interfaces must be available and UP
- For DHCP testing: DHCP server must be reachable
- For DNS testing: DNS server must be reachable

## Installation

1. **Download the script:**

```bash
cd /root
curl -O https://your-repo/fusion-hci-network-prechecks.py
chmod +x fusion-hci-network-prechecks.py
```

2. **Install dependencies:**

```bash
# Python packages
pip3 install scapy dnspython

# System packages
dnf install -y tcpdump NetworkManager chrony

# Enable and start NetworkManager
systemctl enable NetworkManager
systemctl start NetworkManager
```

3. **Verify installation:**

```bash
python3 fusion-hci-network-prechecks.py --help
```

## Usage

### Interactive Mode (Default)

Simply run the script without arguments to enter interactive mode:

```bash
python3 fusion-hci-network-prechecks.py
```

The tool will display a menu with all available options.

### Command-Line Mode

Use command-line arguments for automation:

```bash
# DHCP validation
python3 fusion-hci-network-prechecks.py --dhcp bond0.1522 mac-list.txt --timeout 10

# DNS validation
python3 fusion-hci-network-prechecks.py --dns hostname-list.txt --dns-server 9.5.175.8

# Static IP configuration
python3 fusion-hci-network-prechecks.py --static bond0.1522 10.48.108.85/24 --gateway 10.48.108.1 --dns 9.5.175.8

# NTP check
python3 fusion-hci-network-prechecks.py --ntp 9.5.175.8

# Port testing
python3 fusion-hci-network-prechecks.py --ports 192.168.1.1 22,80,443 --protocol tcp

# Path MTU discovery
python3 fusion-hci-network-prechecks.py --pmtu 9.5.175.8 --interface bond0.1522
```

## Menu Options

### Main Menu

```
============================================================
ℹ Network Validation Tool - Interactive Mode
============================================================
1) Create Bond Interface
2) Create VLAN Interface
3) Static IP Configuration
4) DNS Only Validation (IP/Hostname List)
5) DHCP Validation (MAC List)
6) NTP Synchronization Check
7) TCP/UDP Port Testing
8) Path MTU Discovery
9) Verify Bond Status
10) Exit
============================================================
```

### Option 1: Create Bond Interface

Creates an IEEE 802.3ad (LACP) bond interface with specified slave interfaces.

**Inputs:**
- Bond interface name (e.g., bond0)
- Slave interfaces (comma-separated, e.g., ens1f0np0,ens1f1np1)

**Example:**
```
➤ Enter bond interface name: bond0
➤ Enter slave interfaces: ens1f0np0,ens1f1np1
```

**Output:**
- Bond creation status
- Slave interface status
- LACP aggregator verification
- Link state for each slave

### Option 2: Create VLAN Interface

Creates a VLAN interface on a parent interface (bond or physical).

**Inputs:**
- Parent interface (e.g., bond0)
- VLAN ID (1-4094)

**Example:**
```
➤ Enter parent interface: bond0
➤ Enter VLAN ID: 1522
```

**Output:**
- VLAN creation status
- Interface initialization confirmation
- Placeholder IP configuration note

### Option 3: Static IP Configuration

Configures a static IP address on an interface with optional gateway and DNS.

**Inputs:**
- Network interface (e.g., bond0.1522)
- Static IP with CIDR (e.g., 10.48.108.85/24)
- Gateway IP (optional)
- DNS server IP (optional)

**Example:**
```
➤ Enter network interface: bond0.1522
➤ Enter static IP with CIDR: 10.48.108.85/24
➤ Enter gateway IP: 10.48.108.1
➤ Enter DNS server IP: 9.5.175.8
```

### Option 4: DNS Only Validation

Validates DNS resolution for a list of IP addresses and/or hostnames.

**Inputs:**
- Path to IP/hostname list file
- DNS server IP (optional, uses system default if empty)

**Output Example:**
```
compute-1.example.com → 10.48.108.82 ✓ OK
compute-2.example.com → 10.48.108.83 ✓ OK
api.example.com → 10.48.108.13 ✓ OK
*.apps.example.com → 10.48.108.14 ✓ OK (wildcard, reverse skipped)
10.48.108.85 → servicenode-1.example.com ✓ OK
```

### Option 5: DHCP Validation

Tests DHCP server responses for a list of MAC addresses.

**Inputs:**
- Network interface (e.g., bond0.1522)
- Path to MAC address list file
- DHCP timeout in seconds (default: 5)

**Output Example:**
```
Testing 3 MAC addresses...
58:a2:e1:54:84:ca → 10.48.108.82 ✓ OK
58:a2:e1:54:88:e6 → 10.48.108.83 ✓ OK
10:70:fd:d8:6c:7c ✗ TIMEOUT (0 packets captured)
```

### Option 6: NTP Synchronization Check

Verifies NTP synchronization with a specified server.

**Input:**
```
➤ Enter NTP server: 9.5.175.8
```

**Output Example:**
```
✓ NTP synchronized with 9.5.175.8
  Stratum: 3
  Offset: 0.000123 seconds
```

### Option 7: TCP/UDP Port Testing

Tests connectivity to TCP or UDP ports on a target host.

**Output Example:**
```
Testing TCP ports on 192.168.1.1
✓ Port 22: OPEN
✓ Port 80: OPEN
✗ Port 443: CLOSED/FILTERED
```

### Option 8: Path MTU Discovery

Discovers the maximum transmission unit (MTU) to a destination.

**Output Example:**
```
Finding Path MTU to 9.5.175.8
✓ Path MTU: 1500 bytes
```

### Option 9: Verify Bond Status

Displays detailed status of a bond interface.

**Output Example:**
```
=== Bond bond0 Status ===
  Mode: IEEE 802.3ad Dynamic link aggregation
  Bond Status: up
  Slaves: 2
    ens1f0np0: up ✓ ✓ (Aggregator: 1)
    ens1f1np1: up ✓ ✓ (Aggregator: 1)
✓ LACP Status: All slaves in same aggregator - LACP properly formed
```

### Option 10: Exit

Exits the tool and performs automatic cleanup of temporary network connections, running tcpdump processes, and restores original network state.

## Input File Formats

### MAC Address List (for DHCP Validation)

```
# mac-list.txt
# One MAC address per line
# Comments start with #
58:a2:e1:54:84:ca
58:a2:e1:54:88:e6
10:70:fd:d8:6c:7c
```

### Hostname/IP List (for DNS Validation)

```
# hostname-list.txt
compute-1.example.com
compute-2.example.com
*.apps.example.com
10.48.108.85
```

## Technical Details

### DHCP Validation Architecture

The tool uses tcpdump for DHCP packet capture instead of Scapy's AsyncSniffer for improved reliability:

1. **TCPdump Process:** Spawned with BPF filter for DHCP traffic
2. **DHCP Discovery:** Sent using Scapy's sendp() with proper BOOTP padding
3. **Packet Capture:** TCPdump writes to pcap file
4. **Packet Analysis:** Scapy reads pcap file and extracts DHCP offers
5. **Cleanup:** TCPdump terminated gracefully with SIGINT

### Retry Logic

The tool implements intelligent retry logic for transient failures:

- **DHCP Validation:** Up to 3 retries per MAC address
- **Retryable Errors:** ENOBUFS, interface disappeared, tcpdump failed
- **Delay Between Retries:** 500ms to allow system recovery

## Troubleshooting

1. **DHCP Validation Timeouts:** If you see timeouts, check if the interface state is UP using `ip link show [interface]` and verify that the firewall isn't blocking DHCP traffic with `firewall-cmd --list-all`.

2. **Permission Denied Errors:** Network operations require root access. Always execute the script using `sudo python3 fusion-hci-network-prechecks.py`.

## Best Practices

1. **Network Setup Workflow:** Follow the logical order: Create Bond → Create VLAN → Configure Static IP → Validate DNS → Test NTP/Ports → Verify Bond Status.

2. **DHCP Testing:** Use sequential testing rather than parallel testing to avoid socket buffer exhaustion.

3. **Cleanup:** Always exit using Option 10 to ensure all virtual interfaces and temporary routes are safely removed from NetworkManager.

---

**Version:** 2.0 (TCPdump-based) | **Last Updated:** June 2026 | **Platform:** RHEL 9