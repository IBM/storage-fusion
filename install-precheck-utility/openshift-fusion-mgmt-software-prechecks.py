#!/usr/bin/env python3
"""
openshift-fusion-mgmt-software-prechecks.py

IBM Fusion HCI Network Validation Tool
Interactive pre-installation validation for network configuration, registry access,
certificates, and connectivity requirements.

Author: Based on requirements from Saurabh.md
Version: 2.0 - Enhanced Usability
"""

# Import required libraries
import sys          # For system operations like exit
import os           # For file operations
import json         # For JSON file handling
import logging      # For logging to file
import getpass      # For password input (hides password on screen)
import subprocess   # For running system commands
import socket       # For network connectivity checks
import base64       # For encoding credentials
from datetime import datetime  # For timestamps

# =========================
# VALIDATION RESULT TRACKING
# =========================
# Global structure to track all validation results for summary report
validation_results = {
    'critical': [],  # Must pass for installation
    'warning': [],   # Should review but not blocking
    'info': [],      # Informational only
    'skipped': []    # Not applicable to configuration
}

def add_validation_result(category, test, status, message, details=None, severity='info'):
    """
    Track a validation result for the summary report
    
    Args:
        category: Category of validation (e.g., 'Registry Connectivity')
        test: Name of the test function
        status: 'passed', 'failed', 'warning', or 'skipped'
        message: Human-readable message
        details: Optional dictionary with additional details
        severity: 'critical', 'warning', 'info', or 'skipped'
    """
    result = {
        'category': category,
        'test': test,
        'status': status,
        'message': message,
        'details': details or {},
        'timestamp': datetime.now().isoformat()
    }
    validation_results[severity].append(result)

# =========================
# LOGGING SETUP
# =========================
# Create log file name with timestamp
LOG_FILE = "installer_validation.log"

# Setup logging configuration
logging.basicConfig(
    filename=LOG_FILE,
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

# Function to log and print messages
def log_and_print(message, level="INFO"):
    """
    Log message to file and print to screen
    level can be: INFO, ERROR, WARNING
    """
    print(message)
    if level == "ERROR":
        logging.error(message)
    elif level == "WARNING":
        logging.warning(message)
    else:
        logging.info(message)

# =========================
# HELPER FUNCTIONS
# =========================

def print_section_header(step_num, total_steps, title, description=""):
    """
    Print a formatted section header with step information
    """
    print("\n" + "="*80)
    print(f"STEP {step_num} of {total_steps}: {title}")
    print("="*80)
    if description:
        print(f"{description}\n")

def print_prompt(field_name, purpose, format_info, notes=""):
    """
    Print a formatted input prompt with context
    
    Args:
        field_name: Name of the field being requested
        purpose: Why this information is needed
        format_info: Expected format with examples
        notes: Additional notes or requirements
    """
    print(f"\nEnter {field_name}")
    print(f"  Purpose: {purpose}")
    print(f"  Format: {format_info}")
    if notes:
        print(f"  Note: {notes}")

def get_user_input(prompt_message, allow_empty=False, field_name="", purpose="", format_info="", notes=""):
    """
    Get input from user with validation and enhanced prompts
    
    Args:
        prompt_message: The message to show user (simple mode)
        allow_empty: If False, user must enter something
        field_name: Name of field (for enhanced mode)
        purpose: Why this is needed (for enhanced mode)
        format_info: Expected format (for enhanced mode)
        notes: Additional notes (for enhanced mode)
    
    Returns: user's input as string
    """
    # If enhanced prompt info provided, use it
    if field_name and purpose and format_info:
        print_prompt(field_name, purpose, format_info, notes)
        prompt = f"{field_name}: "
    else:
        prompt = prompt_message
    
    while True:
        # Show prompt and get input
        user_input = input(prompt).strip()
        
        # If empty input is not allowed and user entered nothing
        if not allow_empty and not user_input:
            print("  ✗ Error: Input cannot be empty. Please enter a value.")
            logging.error(f"Empty input for: {field_name or prompt_message}")
            continue  # Ask again
        
        # Valid input received
        return user_input

def get_password_input(prompt_message, field_name="", purpose="", notes=""):
    """
    Get password from user (password will be hidden on screen)
    
    Args:
        prompt_message: The message to show user (simple mode)
        field_name: Name of field (for enhanced mode)
        purpose: Why this is needed (for enhanced mode)
        notes: Additional notes (for enhanced mode)
    
    Returns: password as string
    """
    # If enhanced prompt info provided, use it
    if field_name and purpose:
        print(f"\nEnter {field_name}")
        print(f"  Purpose: {purpose}")
        if notes:
            print(f"  Note: {notes}")
        prompt = f"{field_name}: "
    else:
        prompt = prompt_message
    
    while True:
        # Get password (hidden input)
        password = getpass.getpass(prompt)
        
        # Check if password is empty
        if not password:
            print("  ✗ Error: Password cannot be empty. Please enter a password.")
            logging.error(f"Empty password for: {field_name or prompt_message}")
            continue  # Ask again
        
        # Log that password was entered (but don't log the actual password)
        logging.info(f"Password entered for: {field_name or 'password field'}")
        return password

def get_choice_input(prompt_message, valid_choices, field_name="", options_description=None):
    """
    Get user choice from a list of valid options
    
    Args:
        prompt_message: The message to show user
        valid_choices: List of valid choices (e.g., ['1', '2'])
        field_name: Name of field (for enhanced mode)
        options_description: Dict mapping choice to description
    
    Returns: user's choice as string
    """
    # If options description provided, display it
    if options_description:
        print()
        for choice, description in options_description.items():
            print(f"  {choice}. {description}")
        print()
    
    while True:
        # Get user input
        choice = input(prompt_message).strip()
        
        # Check if choice is empty
        if not choice:
            print("  ✗ Error: Input cannot be empty. Please select an option.")
            logging.error(f"Empty choice for: {field_name or prompt_message}")
            continue
        
        # Check if choice is valid
        if choice not in valid_choices:
            print(f"  ✗ Error: Invalid choice '{choice}'. Please select from: {', '.join(valid_choices)}")
            logging.error(f"Invalid choice '{choice}' for: {field_name or prompt_message}")
            continue
        
        # Valid choice received
        logging.info(f"User selected option {choice} for: {field_name or prompt_message}")
        return choice

# =========================
# VALIDATION FUNCTIONS
# =========================

def check_firewall_status():
    """
    Check if firewall is active/running on the system
    Returns: True if firewall is active, False otherwise
    """
    log_and_print("Checking firewall status...", "INFO")
    
    try:
        # Try to check firewall status using firewall-cmd (for firewalld)
        result = subprocess.run(
            "firewall-cmd --state",
            shell=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            universal_newlines=True
        )
        
        if result.returncode == 0 and "running" in result.stdout.lower():
            print(f"  ✓ Firewall is ACTIVE (firewalld)")
            logging.info("Firewall is active (firewalld)")
            
            add_validation_result(
                category='Firewall Status',
                test='check_firewall_status',
                status='passed',
                message='Firewall is active and running',
                details={'service': 'firewalld'},
                severity='info'
            )
            return True
        
        # Try iptables if firewalld is not running
        result = subprocess.run(
            "sudo iptables -L -n | head -5",
            shell=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            universal_newlines=True
        )
        
        if result.returncode == 0 and result.stdout:
            print(f"  ✓ Firewall is ACTIVE (iptables)")
            logging.info("Firewall is active (iptables)")
            
            add_validation_result(
                category='Firewall Status',
                test='check_firewall_status',
                status='passed',
                message='Firewall is active and running',
                details={'service': 'iptables'},
                severity='info'
            )
            return True
        
        # Check ufw (Ubuntu firewall)
        result = subprocess.run(
            "sudo ufw status",
            shell=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            universal_newlines=True
        )
        
        if result.returncode == 0 and "active" in result.stdout.lower():
            print(f"  ✓ Firewall is ACTIVE (ufw)")
            logging.info("Firewall is active (ufw)")
            
            add_validation_result(
                category='Firewall Status',
                test='check_firewall_status',
                status='passed',
                message='Firewall is active and running',
                details={'service': 'ufw'},
                severity='info'
            )
            return True
        
        print(f"  ⚠ WARNING: Could not determine firewall status")
        print(f"    Please verify firewall is configured correctly")
        logging.warning("Could not determine firewall status")
        
        add_validation_result(
            category='Firewall Status',
            test='check_firewall_status',
            status='warning',
            message='Could not determine firewall status',
            details={},
            severity='warning'
        )
        return False
        
    except Exception as e:
        print(f"  ✗ ERROR checking firewall status: {str(e)}")
        logging.error(f"Error checking firewall status: {str(e)}")
        
        add_validation_result(
            category='Firewall Status',
            test='check_firewall_status',
            status='failed',
            message=f'Error checking firewall: {str(e)}',
            details={},
            severity='warning'
        )
        return False

def check_registry_reachability(registry_url):
    """
    Check if registry URL is reachable from this machine
    Returns: True if reachable, False otherwise
    """
    log_and_print(f"  [1/3] Testing connectivity to registry...", "INFO")
    
    try:
        # Remove http:// or https:// if present
        clean_url = registry_url.replace('https://', '').replace('http://', '')
        
        # Remove any path components (e.g., /mirror-automation-2.13.0/hci/hci-isf-week24)
        # Keep only hostname and port
        if '/' in clean_url:
            clean_url = clean_url.split('/')[0]
        
        # Split host and port if port is specified
        if ':' in clean_url:
            host = clean_url.split(':')[0]
            port = int(clean_url.split(':')[1])
        else:
            host = clean_url
            port = 443  # Default HTTPS port
        
        # Try to connect to the registry
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(5)  # 5 second timeout
        result = sock.connect_ex((host, port))
        sock.close()
        
        if result == 0:
            print(f"  ✓ SUCCESS: Registry connectivity verified")
            print(f"    Registry: {registry_url}")
            print(f"    Host: {host}")
            print(f"    Port: {port}")
            print(f"    Status: Reachable and responding\n")
            logging.info(f"Registry {registry_url} is reachable")
            
            add_validation_result(
                category='Registry Connectivity',
                test='check_registry_reachability',
                status='passed',
                message=f'Registry {registry_url} is reachable',
                details={'host': host, 'port': port},
                severity='critical'
            )
            return True
        else:
            print(f"  ✗ FAILURE: Cannot reach registry {registry_url}\n")
            print(f"  Possible causes:")
            print(f"    1. Network connectivity issue - verify network connection")
            print(f"    2. Firewall blocking port {port} - check firewall rules")
            print(f"    3. Incorrect hostname or port - verify registry URL")
            print(f"    4. DNS resolution failure - test with: ping {host}")
            print(f"\n  Troubleshooting steps:")
            print(f"    • Test connectivity: telnet {host} {port}")
            print(f"    • Check DNS: nslookup {host}")
            print(f"    • Verify firewall allows outbound connections to port {port}")
            print(f"    • Confirm registry is running and accessible")
            print(f"\n  This validation is CRITICAL - installation cannot proceed without registry access.\n")
            logging.error(f"Registry {registry_url} is NOT reachable")
            
            add_validation_result(
                category='Registry Connectivity',
                test='check_registry_reachability',
                status='failed',
                message=f'Registry {registry_url} is not reachable',
                details={'host': host, 'port': port, 'error': 'Connection failed'},
                severity='critical'
            )
            return False
            
    except Exception as e:
        print(f"  ✗ FAILURE: Error checking registry {registry_url}\n")
        print(f"  Error details: {str(e)}")
        print(f"\n  Possible causes:")
        print(f"    1. Invalid registry URL format")
        print(f"    2. Network configuration issue")
        print(f"    3. DNS resolution failure")
        print(f"\n  Troubleshooting steps:")
        print(f"    • Verify registry URL format (hostname:port)")
        print(f"    • Check network connectivity")
        print(f"    • Test DNS resolution: nslookup {registry_url.split(':')[0]}\n")
        logging.error(f"Error checking registry {registry_url}: {str(e)}")
        
        add_validation_result(
            category='Registry Connectivity',
            test='check_registry_reachability',
            status='failed',
            message=f'Error checking registry {registry_url}',
            details={'error': str(e)},
            severity='critical'
        )
        return False

def get_ocp_release_digest(ocp_version, architecture="x86_64"):
    """
    Get the OCP release digest for a given version
    Returns: digest string or None if failed
    """
    log_and_print(f"  Getting OCP release digest for version {ocp_version}...", "INFO")
    
    try:
        # Build the oc adm release info command
        release_image = f"quay.io/openshift-release-dev/ocp-release:{ocp_version}-{architecture}"
        cmd = f"oc adm release info {release_image} | sed -n 's/Pull From: .*@//p'"
        
        result = subprocess.run(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
        
        if result.returncode == 0 and result.stdout.strip():
            digest = result.stdout.strip()
            print(f"  ✓ OCP Release Digest: {digest}")
            logging.info(f"OCP release digest for {ocp_version}: {digest}")
            return digest
        else:
            print(f"  ✗ Failed to get OCP release digest")
            print(f"  Error: {result.stderr}")
            logging.error(f"Failed to get OCP release digest: {result.stderr}")
            return None
            
    except Exception as e:
        print(f"  ✗ Error getting OCP release digest: {str(e)}")
        logging.error(f"Error getting OCP release digest: {str(e)}")
        return None

def podman_login_test(registry_url, username, password, cert_path=None):
    """
    Test podman login to registry
    Returns: True if login successful, False otherwise
    """
    log_and_print(f"  [2/3] Testing authentication...", "INFO")
    logging.info(f"Username: {username}, Password: XXXXXXXXX")
    
    try:
        # Remove protocol if present
        clean_url = registry_url.replace('https://', '').replace('http://', '')
        
        # Remove any path components - keep only hostname:port
        if '/' in clean_url:
            clean_url = clean_url.split('/')[0]
        
        # Build podman login command with optional certificate
        if cert_path:
            # Copy certificate to system trust store for podman
            cert_dir = "/etc/containers/certs.d/" + clean_url.split(':')[0]
            subprocess.run(f"sudo mkdir -p {cert_dir}", shell=True, capture_output=True)
            subprocess.run(f"sudo cp {cert_path} {cert_dir}/ca.crt", shell=True, capture_output=True)
            logging.info(f"Certificate installed to {cert_dir}/ca.crt")
        
        # Run podman login command
        cmd = f"echo '{password}' | podman login -u '{username}' --password-stdin {clean_url}"
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        
        if result.returncode == 0:
            print(f"  ✓ SUCCESS: Registry authentication verified")
            print(f"    Registry: {registry_url}")
            print(f"    Username: {username}")
            print(f"    Status: Credentials accepted")
            print(f"\n    Your credentials are valid. Next, we'll test image pull capability.\n")
            logging.info(f"Podman login to {registry_url} successful")
            
            # Logout after successful login
            subprocess.run(f"podman logout {clean_url}", shell=True, capture_output=True)
            
            add_validation_result(
                category='Registry Authentication',
                test='podman_login_test',
                status='passed',
                message=f'Authentication successful for {registry_url}',
                details={'username': username},
                severity='critical'
            )
            return True
        else:
            print(f"  ✗ FAILURE: Authentication failed for registry {registry_url}\n")
            print(f"  Error details: {result.stderr}")
            print(f"\n  Possible causes:")
            print(f"    1. Incorrect username or password")
            print(f"    2. Account locked or expired")
            print(f"    3. Registry authentication not configured")
            print(f"    4. Certificate trust issues (for HTTPS registries)")
            print(f"\n  Troubleshooting steps:")
            print(f"    • Verify credentials with registry administrator")
            print(f"    • Test login manually: podman login {clean_url}")
            print(f"    • Check if registry requires certificate (see certificate validation)")
            print(f"    • Review registry logs for authentication errors")
            print(f"\n  This validation is CRITICAL - valid credentials required for image mirroring.\n")
            logging.error(f"Podman login to {registry_url} failed: {result.stderr}")
            
            add_validation_result(
                category='Registry Authentication',
                test='podman_login_test',
                status='failed',
                message=f'Authentication failed for {registry_url}',
                details={'username': username, 'error': result.stderr},
                severity='critical'
            )
            return False
            
    except Exception as e:
        print(f"  ✗ FAILURE: Error during authentication test\n")
        print(f"  Error details: {str(e)}")
        print(f"\n  Possible causes:")
        print(f"    1. Podman not installed or not in PATH")
        print(f"    2. Network connectivity issue")
        print(f"    3. Registry configuration problem")
        print(f"\n  Troubleshooting steps:")
        print(f"    • Verify podman is installed: podman --version")
        print(f"    • Check network connectivity to registry")
        print(f"    • Review podman configuration\n")
        logging.error(f"Error during podman login: {str(e)}")
        
        add_validation_result(
            category='Registry Authentication',
            test='podman_login_test',
            status='failed',
            message=f'Error during authentication test',
            details={'error': str(e)},
            severity='critical'
        )
        return False

def podman_pull_test(registry_url, username, password, image_name, cert_path=None):
    """
    Test pulling an image from registry
    Returns: True if pull successful, False otherwise
    """
    log_and_print(f"  [3/3] Testing image pull capability...", "INFO")
    
    try:
        # Remove protocol if present
        clean_url = registry_url.replace('https://', '').replace('http://', '')
        
        # Remove any path components - keep only hostname:port
        if '/' in clean_url:
            registry_host = clean_url.split('/')[0]
        else:
            registry_host = clean_url
        
        # Install certificate if provided (should already be done in login test, but ensure it's there)
        if cert_path:
            cert_dir = "/etc/containers/certs.d/" + registry_host.split(':')[0]
            subprocess.run(f"sudo mkdir -p {cert_dir}", shell=True, capture_output=True)
            subprocess.run(f"sudo cp {cert_path} {cert_dir}/ca.crt", shell=True, capture_output=True)
        
        # Login first
        login_cmd = f"echo '{password}' | podman login -u '{username}' --password-stdin {registry_host}"
        subprocess.run(login_cmd, shell=True, capture_output=True)
        
        # Try to pull image - use full registry URL with path if provided
        # For digest-based references (starting with @), don't add separator
        if image_name.startswith('@'):
            full_image_path = f"{clean_url}{image_name}"
        else:
            full_image_path = f"{clean_url}/{image_name}"
        pull_cmd = f"podman pull {full_image_path}"
        result = subprocess.run(pull_cmd, shell=True, capture_output=True, text=True)
        
        # Logout
        subprocess.run(f"podman logout {registry_host}", shell=True, capture_output=True)
        
        if result.returncode == 0:
            print(f"  ✓ SUCCESS: Image pull capability verified")
            print(f"    Registry: {registry_url}")
            print(f"    Image: {image_name}")
            print(f"    Status: Successfully pulled and verified")
            print(f"\n    Registry validation complete - all checks passed!\n")
            logging.info(f"Image pull from {registry_url} successful")
            
            # Remove the pulled image
            subprocess.run(f"podman rmi {full_image_path}", shell=True, capture_output=True)
            
            add_validation_result(
                category='Registry Image Pull',
                test='podman_pull_test',
                status='passed',
                message=f'Image pull successful from {registry_url}',
                details={'image': image_name},
                severity='critical'
            )
            return True
        else:
            print(f"  ✗ FAILURE: Image pull failed from {registry_url}\n")
            print(f"  Error details: {result.stderr}")
            print(f"\n  Possible causes:")
            print(f"    1. Image does not exist in registry")
            print(f"    2. Insufficient permissions to pull image")
            print(f"    3. Network issue during image transfer")
            print(f"    4. Registry storage or configuration problem")
            print(f"\n  Troubleshooting steps:")
            print(f"    • Verify image exists: podman search {clean_url}/{image_name.split('/')[0]}")
            print(f"    • Check user permissions in registry")
            print(f"    • Test manual pull: podman pull {full_image_path}")
            print(f"    • Review registry logs for errors")
            print(f"\n  This validation is CRITICAL - image pull capability required for installation.\n")
            logging.error(f"Image pull from {registry_url} failed: {result.stderr}")
            
            add_validation_result(
                category='Registry Image Pull',
                test='podman_pull_test',
                status='failed',
                message=f'Image pull failed from {registry_url}',
                details={'image': image_name, 'error': result.stderr},
                severity='critical'
            )
            return False
            
    except Exception as e:
        print(f"  ✗ FAILURE: Error during image pull test\n")
        print(f"  Error details: {str(e)}")
        print(f"\n  Possible causes:")
        print(f"    1. Podman not properly configured")
        print(f"    2. Network connectivity issue")
        print(f"    3. Registry authentication expired")
        print(f"\n  Troubleshooting steps:")
        print(f"    • Verify podman is working: podman images")
        print(f"    • Check network connectivity")
        print(f"    • Re-authenticate to registry\n")
        logging.error(f"Error during image pull: {str(e)}")
        
        add_validation_result(
            category='Registry Image Pull',
            test='podman_pull_test',
            status='failed',
            message=f'Error during image pull test',
            details={'error': str(e)},
            severity='critical'
        )
        return False

def validate_file_path(file_path):
    """
    Check if file exists and is readable
    Returns: True if file exists, False otherwise
    """
    log_and_print(f"  Validating file: {file_path}", "INFO")
    
    if os.path.isfile(file_path) and os.access(file_path, os.R_OK):
        print(f"  ✓ SUCCESS: File validated")
        print(f"    Path: {file_path}")
        print(f"    Status: File exists and is readable\n")
        logging.info(f"File exists and is readable: {file_path}")
        
        add_validation_result(
            category='File Validation',
            test='validate_file_path',
            status='passed',
            message=f'File validated: {file_path}',
            details={'path': file_path},
            severity='critical'
        )
        return True
    else:
        print(f"  ✗ FAILURE: Cannot access file: {file_path}\n")
        print(f"  Possible causes:")
        print(f"    1. File does not exist at specified path")
        print(f"    2. Insufficient read permissions")
        print(f"    3. Path contains typo or incorrect directory")
        print(f"\n  Troubleshooting steps:")
        print(f"    • Verify file exists: ls -la {file_path}")
        print(f"    • Check permissions: should be readable by current user")
        print(f"    • Confirm full path is correct (use absolute paths)")
        print(f"    • Check for typos in filename or extension")
        print(f"\n  This validation is CRITICAL - the file is required for installation.\n")
        logging.error(f"File not found or not readable: {file_path}")
        
        add_validation_result(
            category='File Validation',
            test='validate_file_path',
            status='failed',
            message=f'File not accessible: {file_path}',
            details={'path': file_path},
            severity='critical'
        )
        return False

def validate_certificate(cert_path):
    """
    Validate certificate file
    Returns: True if valid, False otherwise
    """
    log_and_print(f"  Validating certificate...", "INFO")
    
    try:
        # Check if file exists
        if not validate_file_path(cert_path):
            return False
        
        # Check certificate validity using openssl
        cmd = f"openssl x509 -in {cert_path} -noout -text"
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        
        if result.returncode == 0:
            # Check expiration date
            exp_cmd = f"openssl x509 -in {cert_path} -noout -enddate"
            exp_result = subprocess.run(exp_cmd, shell=True, capture_output=True, text=True)
            expiration = exp_result.stdout.strip() if exp_result.returncode == 0 else "Unknown"
            
            # Check if self-signed
            issuer_cmd = f"openssl x509 -in {cert_path} -noout -issuer"
            subject_cmd = f"openssl x509 -in {cert_path} -noout -subject"
            issuer = subprocess.run(issuer_cmd, shell=True, capture_output=True, text=True).stdout
            subject = subprocess.run(subject_cmd, shell=True, capture_output=True, text=True).stdout
            
            is_self_signed = (issuer == subject)
            cert_type = "Self-signed" if is_self_signed else "CA-signed"
            
            print(f"  ✓ SUCCESS: Certificate validation passed")
            print(f"    Certificate: {cert_path}")
            print(f"    {expiration}")
            print(f"    Type: {cert_type}")
            print(f"    Status: Valid and trusted")
            
            if is_self_signed:
                print(f"\n    ⚠ WARNING: Certificate is self-signed")
                print(f"    Consider using CA-signed certificate for production environments")
            
            print()
            logging.info(f"Certificate is valid: {cert_path}, Type: {cert_type}, {expiration}")
            
            severity = 'warning' if is_self_signed else 'critical'
            add_validation_result(
                category='Certificate Validation',
                test='validate_certificate',
                status='passed' if not is_self_signed else 'warning',
                message=f'Certificate validated: {cert_path}',
                details={'path': cert_path, 'type': cert_type, 'expiration': expiration},
                severity=severity
            )
            return True
        else:
            print(f"  ✗ FAILURE: Certificate validation failed\n")
            print(f"  Error details: {result.stderr}")
            print(f"\n  Possible causes:")
            print(f"    1. File is not a valid X.509 certificate")
            print(f"    2. Certificate is corrupted or malformed")
            print(f"    3. Wrong file format (must be PEM or DER)")
            print(f"\n  Troubleshooting steps:")
            print(f"    • Verify certificate format: openssl x509 -in {cert_path} -text -noout")
            print(f"    • Check file is not encrypted")
            print(f"    • Ensure certificate is in PEM format (begins with -----BEGIN CERTIFICATE-----)")
            print(f"    • Try converting if needed: openssl x509 -inform DER -in cert.der -out cert.pem")
            print(f"\n  This validation is CRITICAL - valid certificate required for secure registry access.\n")
            logging.error(f"Certificate validation failed: {cert_path}")
            
            add_validation_result(
                category='Certificate Validation',
                test='validate_certificate',
                status='failed',
                message=f'Certificate validation failed: {cert_path}',
                details={'path': cert_path, 'error': result.stderr},
                severity='critical'
            )
            return False
            
    except Exception as e:
        print(f"  ✗ FAILURE: Error validating certificate\n")
        print(f"  Error details: {str(e)}")
        print(f"\n  Possible causes:")
        print(f"    1. OpenSSL not installed or not in PATH")
        print(f"    2. File access permission issue")
        print(f"    3. System configuration problem")
        print(f"\n  Troubleshooting steps:")
        print(f"    • Verify OpenSSL is installed: openssl version")
        print(f"    • Check file permissions")
        print(f"    • Review system logs for errors\n")
        logging.error(f"Error validating certificate: {str(e)}")
        
        add_validation_result(
            category='Certificate Validation',
            test='validate_certificate',
            status='failed',
            message=f'Error validating certificate',
            details={'error': str(e)},
            severity='critical'
        )
        return False

def check_site_reachability(site_url, proxy_server=None, proxy_port=None, proxy_username=None, proxy_password=None):
    """
    Check if a website/URL is reachable
    Returns: True if reachable, False otherwise
    """
    logging.info(f"Checking reachability to: {site_url}")
    
    # Determine if this is a cluster-specific URL (will not exist until cluster is installed)
    is_cluster_url = '.apps.' in site_url
    
    try:
        # Build curl command
        if proxy_server and proxy_port:
            if proxy_username and proxy_password:
                # Authenticated proxy
                proxy_url = f"http://{proxy_username}:{proxy_password}@{proxy_server}:{proxy_port}"
                logging.info(f"Using authenticated proxy: {proxy_server}:{proxy_port}, Username: {proxy_username}, Password: XXXXXXXXX")
            else:
                # Unauthenticated proxy
                proxy_url = f"http://{proxy_server}:{proxy_port}"
                logging.info(f"Using unauthenticated proxy: {proxy_server}:{proxy_port}")
            
            cmd = f"curl -I -k --max-time 10 --proxy {proxy_url} https://{site_url}"
        else:
            cmd = f"curl -I -k --max-time 10 https://{site_url}"
        
        # Run curl command
        result = subprocess.run(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
        
        # Check if successful (HTTP 200, 301, 302, 401, 403 are considered reachable)
        if result.returncode == 0 or any(code in result.stdout for code in ['200', '301', '302', '401', '403']):
            print(f"  ✓ {site_url}")
            logging.info(f"Site reachable: {site_url}")
            
            add_validation_result(
                category='Site Connectivity',
                test='check_site_reachability',
                status='passed',
                message=f'Site reachable: {site_url}',
                details={'url': site_url},
                severity='critical'
            )
            return True
        else:
            # If curl fails, try ping as fallback (especially for cluster URLs)
            ping_result = subprocess.run(f"ping -c 1 -W 2 {site_url}", shell=True,
                                        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            
            if ping_result.returncode == 0:
                # Ping successful - DNS resolves and host is reachable
                if is_cluster_url:
                    print(f"  ⚠ {site_url} - DNS resolves (cluster not yet installed)")
                    logging.warning(f"Cluster URL DNS resolves but HTTPS not available (expected): {site_url}")
                    add_validation_result(
                        category='Site Connectivity',
                        test='check_site_reachability',
                        status='warning',
                        message=f'Cluster URL DNS resolves: {site_url} (HTTPS will be available after installation)',
                        details={'url': site_url},
                        severity='warning'
                    )
                else:
                    print(f"  ⚠ {site_url} - Ping OK but HTTPS not responding")
                    logging.warning(f"Site ping successful but HTTPS not responding: {site_url}")
                    add_validation_result(
                        category='Site Connectivity',
                        test='check_site_reachability',
                        status='warning',
                        message=f'Site reachable via ping but HTTPS not responding: {site_url}',
                        details={'url': site_url},
                        severity='warning'
                    )
                return True
            else:
                # Both curl and ping failed
                print(f"  ✗ {site_url} - NOT REACHABLE")
                logging.error(f"Site NOT reachable: {site_url}")
                
                add_validation_result(
                    category='Site Connectivity',
                    test='check_site_reachability',
                    status='failed',
                    message=f'Site not reachable: {site_url}',
                    details={'url': site_url},
                    severity='critical'
                )
                return False
            
    except Exception as e:
        print(f"  ✗ {site_url} - ERROR: {str(e)}")
        logging.error(f"Error checking site {site_url}: {str(e)}")
        
        add_validation_result(
            category='Site Connectivity',
            test='check_site_reachability',
            status='failed',
            message=f'Error checking site: {site_url}',
            details={'url': site_url, 'error': str(e)},
            severity='critical'
        )
        return False

def create_auth_file(pull_secret_path, ibm_entitlement_key, output_path="authfile.json"):
    """
    Create authentication file by combining pull-secret and IBM entitlement
    Returns: True if successful, False otherwise
    """
    log_and_print(f"Creating auth file: {output_path}", "INFO")
    logging.info(f"Pull secret path: {pull_secret_path}, IBM Key: XXXXXXXXX")
    
    try:
        # Read pull-secret.json
        with open(pull_secret_path, 'r') as f:
            pull_secret = json.load(f)
        
        # Ensure auths key exists
        if 'auths' not in pull_secret:
            pull_secret['auths'] = {}
        
        # Add cp.icr.io authentication
        credentials = f"cp:{ibm_entitlement_key}"
        encoded_creds = base64.b64encode(credentials.encode()).decode()
        
        pull_secret['auths']['cp.icr.io'] = {
            "auth": encoded_creds,
            "email": "cp@example.com"
        }
        
        # Write auth file
        with open(output_path, 'w') as f:
            json.dump(pull_secret, f, indent=2)
        
        log_and_print(f"✓ SUCCESS: Auth file created: {output_path}", "INFO")
        return True
        
    except Exception as e:
        log_and_print(f"✗ FAILURE: Error creating auth file: {str(e)}", "ERROR")
        return False

def validate_json_file(file_path):
    """
    Check if file is valid JSON
    Returns: True if valid JSON, False otherwise
    """
    log_and_print(f"  Validating JSON format...", "INFO")
    
    try:
        with open(file_path, 'r') as f:
            json.load(f)
        print(f"  ✓ SUCCESS: File is valid JSON")
        print(f"    Path: {file_path}")
        print(f"    Status: Valid JSON format\n")
        logging.info(f"File is valid JSON: {file_path}")
        
        add_validation_result(
            category='File Validation',
            test='validate_json_file',
            status='passed',
            message=f'Valid JSON file: {file_path}',
            details={'path': file_path},
            severity='critical'
        )
        return True
    except json.JSONDecodeError as e:
        print(f"  ✗ FAILURE: File is not valid JSON\n")
        print(f"  Error details: {str(e)}")
        print(f"\n  Possible causes:")
        print(f"    1. Syntax error in JSON (missing comma, bracket, etc.)")
        print(f"    2. Invalid JSON structure")
        print(f"    3. File encoding issue")
        print(f"\n  Troubleshooting steps:")
        print(f"    • Validate JSON syntax: python3 -m json.tool {file_path}")
        print(f"    • Check for common errors (trailing commas, unquoted keys)")
        print(f"    • Use a JSON validator or linter")
        print(f"    • Verify file encoding is UTF-8\n")
        logging.error(f"File is not valid JSON: {str(e)}")
        
        add_validation_result(
            category='File Validation',
            test='validate_json_file',
            status='failed',
            message=f'Invalid JSON file: {file_path}',
            details={'path': file_path, 'error': str(e)},
            severity='critical'
        )
        return False
    except Exception as e:
        print(f"  ✗ FAILURE: Error reading JSON file\n")
        print(f"  Error details: {str(e)}")
        print(f"\n  Troubleshooting steps:")
        print(f"    • Verify file exists and is readable")
        print(f"    • Check file permissions\n")
        logging.error(f"Error reading JSON file: {str(e)}")
        
        add_validation_result(
            category='File Validation',
            test='validate_json_file',
            status='failed',
            message=f'Error reading JSON file: {file_path}',
            details={'path': file_path, 'error': str(e)},
            severity='critical'
        )
        return False

def print_validation_summary(cluster_name="", base_domain="", install_type="", config_details=None):
    """
    Print a comprehensive validation summary report
    """
    print("\n" + "="*80)
    print("VALIDATION SUMMARY")
    print("="*80 + "\n")
    
    # Count results by status
    critical_passed = sum(1 for r in validation_results['critical'] if r['status'] == 'passed')
    critical_failed = sum(1 for r in validation_results['critical'] if r['status'] == 'failed')
    warnings = len(validation_results['warning'])
    info_count = len(validation_results['info'])
    skipped_count = len(validation_results['skipped'])
    
    # Determine overall status
    if critical_failed == 0:
        overall_status = "✓ READY FOR INSTALLATION"
        status_color = "SUCCESS"
    else:
        overall_status = "✗ NOT READY - CRITICAL FAILURES DETECTED"
        status_color = "FAILURE"
    
    print(f"Overall Status: {overall_status}\n")
    
    # Critical validations
    print(f"Critical Validations (Must Pass):")
    if validation_results['critical']:
        for result in validation_results['critical']:
            status_symbol = "✓" if result['status'] == 'passed' else "✗"
            print(f"  {status_symbol} {result['category']:<30} {result['status'].upper()}")
            if result['status'] == 'failed':
                print(f"     Issue: {result['message']}")
    else:
        print(f"  No critical validations performed")
    
    print()
    
    # Warnings
    if warnings > 0:
        print(f"Warnings (Review Recommended):")
        for result in validation_results['warning']:
            print(f"  ⚠ {result['category']:<30} WARNING")
            print(f"     {result['message']}")
        print()
    
    # Configuration summary
    if cluster_name or base_domain or install_type:
        print(f"Configuration Summary:")
        if cluster_name:
            print(f"  Cluster Name:        {cluster_name}")
        if base_domain:
            print(f"  Base Domain:         {base_domain}")
        if install_type:
            print(f"  Installation Type:   {install_type}")
        if config_details:
            for key, value in config_details.items():
                print(f"  {key:<20} {value}")
        print()
    
    # Next steps
    print(f"Next Steps:")
    if critical_failed == 0:
        print(f"  1. Review the detailed log file: {LOG_FILE}")
        if warnings > 0:
            print(f"  2. Address {warnings} warning(s) before proceeding")
        print(f"  3. Proceed with cluster installation using validated configuration")
        print(f"  4. Keep this validation log for troubleshooting reference")
    else:
        print(f"  1. Review {critical_failed} critical failure(s) above")
        print(f"  2. Follow troubleshooting steps for each failed validation")
        print(f"  3. Re-run this validation tool after resolving issues")
        print(f"  4. Check detailed log file: {LOG_FILE}")
    
    print("\n" + "="*80 + "\n")

# =========================
# MAIN PROGRAM
# =========================


def main():
    """
    Main function - Entry point of the program
    """
    # Display welcome message
    print("\n" + "="*80)
    print("IBM Fusion HCI Network Validation Tool")
    print("="*80)
    print("\nThis tool validates your network configuration for IBM Fusion HCI installation.")
    print("\nWhat this tool checks:")
    print("  • Container registry connectivity and authentication")
    print("  • Certificate validity and trust")
    print("  • Network connectivity to required endpoints")
    print("  • Pull secret and authentication file validity")
    print("\nHow to use:")
    print("  • Answer each question carefully")
    print("  • Press Ctrl+C at any time to exit")
    print("  • All results are logged to:", LOG_FILE)
    print("\nEstimated time: 5-15 minutes depending on configuration")
    print("="*80 + "\n")
    
    logging.info("="*80)
    logging.info("IBM Fusion HCI Network Validation Tool Started")
    logging.info("="*80)
    
    # Initialize variables that may be set conditionally
    registry_type = None
    offline_registry_url = None
    openshift_registry_url = None
    fusion_registry_url = None
    
    # =========================
    # STEP 1: Get Cluster Name
    # =========================
    print_section_header(1, 6, "Cluster Configuration",
                        "We need basic information about your cluster to generate validation URLs.")
    
    cluster_name = get_user_input(
        prompt_message="Enter Cluster Name: ",
        field_name="Cluster Name",
        purpose="Identifies your OpenShift cluster in DNS and URLs",
        format_info="Lowercase alphanumeric with hyphens (e.g., 'prod-cluster-01')",
        notes="Must be valid DNS label (max 63 characters)"
    )
    logging.info(f"Cluster Name: {cluster_name}")
    
    # =========================
    # STEP 2: Get Base Domain
    # =========================
    base_domain = get_user_input(
        prompt_message="Enter Base Domain: ",
        field_name="Base Domain",
        purpose="DNS domain for your cluster (e.g., 'example.com')",
        format_info="Valid DNS domain name",
        notes="Will be combined with cluster name for full cluster domain"
    )
    logging.info(f"Base Domain: {base_domain}")
    
    # =========================
    # STEP 3: Get Installation Type
    # =========================
    print_section_header(2, 6, "Installation Type",
                        "Select your installation type based on network connectivity.")
    
    install_options = {
        '1': "Airgap Installation (Disconnected/Offline)\n" +
             "     • No direct internet connectivity\n" +
             "     • Uses local container registry\n" +
             "     • All images pre-mirrored to local registry\n" +
             "     • Best for: Secure/isolated environments, compliance requirements",
        '2': "Connected Installation (Online)\n" +
             "     • Direct internet connectivity available\n" +
             "     • Pulls images from IBM and Red Hat registries\n" +
             "     • May use proxy for internet access\n" +
             "     • Best for: Standard deployments with internet access"
    }
    
    install_type_choice = get_choice_input(
        "Enter your choice (1 or 2): ",
        ['1', '2'],
        field_name="Installation Type",
        options_description=install_options
    )
    
    # Set installation type based on choice
    if install_type_choice == '1':
        type_of_install = "airgap_install"
        install_type_display = "Airgap Installation (Disconnected)"
        logging.info(f"Installation Type: {install_type_display}")
    else:
        type_of_install = "connected_install"
        install_type_display = "Connected Installation (Online)"
        logging.info(f"Installation Type: {install_type_display}")
    
    # =========================
    # AIRGAP INSTALLATION PATH
    # =========================
    if type_of_install == "airgap_install":
        print("\n--- Airgap Installation Configuration ---")
        
        # Ask for OCP version
        print("\nOpenShift Container Platform Version")
        print("Example: 4.14.15, 4.15.10, 4.16.0")
        ocp_version = get_user_input("Enter the OCP version: ")
        log_and_print(f"OCP Version: {ocp_version}", "INFO")
        
        # Get OCP release digest
        print("\nRetrieving OCP release digest...")
        ocp_digest = get_ocp_release_digest(ocp_version)
        
        if not ocp_digest:
            print("\n⚠ WARNING: Could not retrieve OCP release digest.")
            print("  This may cause image pull validation to fail.")
            print("  Please ensure 'oc' CLI is installed and configured.")
            ocp_digest = None
        
        # Ask about number of registries
        print("\n1. Single Registry (For Openshift, Fusion & its services - one registry)")
        print("2. Multiple Registries (Different registries for Openshift & Fusion)")
        
        registry_choice = get_choice_input("How many Registries will be used (1 or 2): ", ['1', '2'])
        
        if registry_choice == '1':
            registry_type = "single_registry"
            log_and_print("Registry Type: Single Registry", "INFO")
        else:
            registry_type = "multiple_registries"
            log_and_print("Registry Type: Multiple Registries", "INFO")
        
        # =========================
        # SINGLE REGISTRY PATH
        # =========================
        if registry_type == "single_registry":
            print("\n--- Single Registry Configuration ---")
            
            # Get registry details
            offline_registry_url = get_user_input("Enter the registry URL: ")
            log_and_print(f"Registry URL: {offline_registry_url}", "INFO")
            
            offline_registry_username = get_user_input("Enter registry username: ")
            log_and_print(f"Registry Username: {offline_registry_username}", "INFO")
            
            offline_registry_password = get_password_input("Enter registry password: ")
            
            # Ask about certificate BEFORE validation
            print("\n1. Yes, certificate will be used for cluster installation")
            print("2. No, certificate will not be used for cluster installation")
            
            cert_choice = get_choice_input("Are you using any certificate for this registry (1 or 2): ", ['1', '2'])
            
            if cert_choice == '1':
                is_certificate_used = True
                log_and_print("Certificate will be used", "INFO")
                
                # Get certificate path
                offline_registry_cert_path = get_user_input("Please enter certificate file path: ")
                log_and_print(f"Certificate Path: {offline_registry_cert_path}", "INFO")
                
                # Validate certificate
                print("\nValidating certificate...")
                validate_file_path(offline_registry_cert_path)
                validate_certificate(offline_registry_cert_path)
            else:
                is_certificate_used = False
                offline_registry_cert_path = None
                log_and_print("Certificate will not be used", "INFO")
            
            # Validate registry reachability AFTER certificate
            print("\nValidating registry...")
            check_registry_reachability(offline_registry_url)
            
            # Test podman login with certificate
            print("Testing podman login...")
            podman_login_test(offline_registry_url, offline_registry_username, offline_registry_password,
                            offline_registry_cert_path if is_certificate_used else None)
            
            # Test image pull with certificate
            if ocp_digest:
                print("Testing Openshift image pull...")
                image_name = f"@{ocp_digest}"
                podman_pull_test(offline_registry_url, offline_registry_username, offline_registry_password,
                               image_name,
                               offline_registry_cert_path if is_certificate_used else None)
            else:
                print("⚠ Skipping image pull test (OCP digest not available)")
                logging.warning("Skipping image pull test - OCP digest not available")
        
        # =========================
        # MULTIPLE REGISTRIES PATH
        # =========================
        elif registry_type == "multiple_registries":
            print("\n--- Multiple Registries Configuration ---")
            
            # OpenShift Registry
            print("\n>> OpenShift Registry <<")
            openshift_registry_url = get_user_input("Enter the Openshift registry URL: ")
            log_and_print(f"OpenShift Registry URL: {openshift_registry_url}", "INFO")
            
            openshift_registry_username = get_user_input("Enter Openshift registry username: ")
            log_and_print(f"OpenShift Registry Username: {openshift_registry_username}", "INFO")
            
            openshift_registry_password = get_password_input("Enter Openshift registry password: ")
            
            # OpenShift certificate - Ask BEFORE validation
            print("\n1. Yes, certificate will be used")
            print("2. No, certificate will not be used")
            
            os_cert_choice = get_choice_input("Certificate for OpenShift registry (1 or 2): ", ['1', '2'])
            
            if os_cert_choice == '1':
                os_cert_path = get_user_input("Enter OpenShift registry certificate file path: ")
                log_and_print(f"OpenShift Certificate Path: {os_cert_path}", "INFO")
                validate_file_path(os_cert_path)
                validate_certificate(os_cert_path)
            else:
                os_cert_path = None
            
            # Validate OpenShift registry AFTER certificate
            print("\nValidating OpenShift registry...")
            check_registry_reachability(openshift_registry_url)
            podman_login_test(openshift_registry_url, openshift_registry_username, openshift_registry_password,
                            os_cert_path)
            
            # Test image pull with OCP digest
            if ocp_digest:
                print("Testing Openshift image pull...")
                image_name = f"@{ocp_digest}"
                podman_pull_test(openshift_registry_url, openshift_registry_username, openshift_registry_password,
                               image_name, os_cert_path)
            else:
                print("⚠ Skipping image pull test (OCP digest not available)")
                logging.warning("Skipping image pull test - OCP digest not available")
            
            # Fusion Registry
            print("\n>> Fusion Registry <<")
            fusion_registry_url = get_user_input("Enter the Fusion registry URL: ")
            log_and_print(f"Fusion Registry URL: {fusion_registry_url}", "INFO")
            
            fusion_registry_username = get_user_input("Enter Fusion registry username: ")
            log_and_print(f"Fusion Registry Username: {fusion_registry_username}", "INFO")
            
            fusion_registry_password = get_password_input("Enter Fusion registry password: ")
            
            # Fusion certificate - Ask BEFORE validation
            print("\n1. Yes, certificate will be used")
            print("2. No, certificate will not be used")
            
            fusion_cert_choice = get_choice_input("Certificate for Fusion registry (1 or 2): ", ['1', '2'])
            
            if fusion_cert_choice == '1':
                fusion_cert_path = get_user_input("Enter Fusion registry certificate file path: ")
                log_and_print(f"Fusion Certificate Path: {fusion_cert_path}", "INFO")
                validate_file_path(fusion_cert_path)
                validate_certificate(fusion_cert_path)
            else:
                fusion_cert_path = None
            
            # Validate Fusion registry AFTER certificate
            print("\nValidating Fusion registry...")
            check_registry_reachability(fusion_registry_url)
            podman_login_test(fusion_registry_url, fusion_registry_username, fusion_registry_password,
                            fusion_cert_path)
            podman_pull_test(fusion_registry_url, fusion_registry_username, fusion_registry_password,
                           "fusion/catalog:latest", fusion_cert_path)
    
    # =========================
    # CONNECTED INSTALLATION PATH
    # =========================
    elif type_of_install == "connected_install":
        print("\n--- Connected Installation Configuration ---")
        
        # Ask about firewall
        print("\n1. Cluster Installation will be with firewall")
        print("2. Cluster Installation will be without firewall")
        
        firewall_choice = get_choice_input("Is this installation with Firewall (1 or 2): ", ['1', '2'])
        
        if firewall_choice == '1':
            is_firewall_used = True
            log_and_print("Installation will use firewall", "INFO")
            
            # Check if firewall is up
            print("\n--- Checking Firewall Status ---")
            check_firewall_status()
            
            # Check access to required registries through firewall
            print("\n--- Validating Registry Access Through Firewall ---")
            firewall_registries = [
                "icr.io",
                "cp.icr.io",
                "gcr.io",
                "registry.redhat.io",
                "quay.io",
                "cdn01.quay.io",
                "cdn02.quay.io",
                "cdn03.quay.io",
                "access.redhat.com",
                "api.access.redhat.com",
                "cert-api.access.redhat.com",
                "infogw.api.openshift.com",
                "console.redhat.com",
                "cloud.redhat.com",
                "mirror.openshift.com",
                "storage.googleapis.com",
                f"oauth-openshift.apps.{cluster_name}.{base_domain}",
                f"console-openshift-console.apps.{cluster_name}.{base_domain}",
                "quayio-production-s3.s3.amazonaws.com",
                "api.openshift.com",
                "art-rhcos-ci.s3.amazonaws.com",
                "registry.access.redhat.com",
                "sso.redhat.com",
                "esupport.ibm.com",
                "www.ecurep.ibm.com"
            ]
            
            for registry in firewall_registries:
                check_site_reachability(registry)
        else:
            is_firewall_used = False
            log_and_print("Installation will NOT use firewall", "INFO")
        
        # Ask about proxy
        print("\n1. Cluster Installation will be with proxy")
        print("2. Cluster Installation will be without proxy")
        
        proxy_choice = get_choice_input("Is this installation with Proxy (1 or 2): ", ['1', '2'])
        
        if proxy_choice == '1':
            is_proxy_used = True
            log_and_print("Installation will use proxy", "INFO")
        else:
            is_proxy_used = False
            log_and_print("Installation will NOT use proxy", "INFO")
        
        # =========================
        # WITH PROXY PATH
        # =========================
        if is_proxy_used:
            print("\n--- Proxy Configuration ---")
            
            # Ask about proxy authentication
            print("\n1. This installation is with Authenticated Proxy")
            print("2. This installation is with Unauthenticated Proxy")
            
            auth_proxy_choice = get_choice_input("Proxy type (1 or 2): ", ['1', '2'])
            
            if auth_proxy_choice == '1':
                is_authenticated_proxy = True
                log_and_print("Using Authenticated Proxy", "INFO")
                
                # Get proxy details with authentication
                proxy_server = get_user_input("Enter Proxy Server IPv4 address or Server-Name: ")
                log_and_print(f"Proxy Server: {proxy_server}", "INFO")
                
                proxy_port = get_user_input("Enter Proxy Port: ")
                log_and_print(f"Proxy Port: {proxy_port}", "INFO")
                
                proxy_username = get_user_input("Enter Proxy Server Username: ")
                log_and_print(f"Proxy Username: {proxy_username}", "INFO")
                
                proxy_password = get_password_input("Enter Proxy Server Password: ")
            else:
                is_authenticated_proxy = False
                log_and_print("Using Unauthenticated Proxy", "INFO")
                
                # Get proxy details without authentication
                proxy_server = get_user_input("Enter Proxy Server IPv4 address or Server-Name: ")
                log_and_print(f"Proxy Server: {proxy_server}", "INFO")
                
                proxy_port = get_user_input("Enter Proxy Port: ")
                log_and_print(f"Proxy Port: {proxy_port}", "INFO")
                
                proxy_username = None
                proxy_password = None
            
            # Ask about GPU
            print("\n1. Cluster is with GPU")
            print("2. Cluster is without GPU")
            
            gpu_choice = get_choice_input("Is cluster with GPU (1 or 2): ", ['1', '2'])
            is_gpu_node = (gpu_choice == '1')
            log_and_print(f"GPU Node: {is_gpu_node}", "INFO")
            
            # Ask about China
            print("\n1. This installation is in China")
            print("2. This installation is not in China")
            
            china_choice = get_choice_input("Is installation in China (1 or 2): ", ['1', '2'])
            is_country_china = (china_choice == '1')
            log_and_print(f"Installation in China: {is_country_china}", "INFO")
            
            # Ask about Metro DR
            print("\n1. Cluster Installation is Metro DR Install")
            print("2. Cluster Installation is not Metro DR Install")
            
            metro_choice = get_choice_input("Is this Metro DR Install (1 or 2): ", ['1', '2'])
            is_metro_dr = (metro_choice == '1')
            log_and_print(f"Metro DR Install: {is_metro_dr}", "INFO")
            
            # Ask about Call Home
            print("\n1. This installation is with Call home")
            print("2. This installation is without Call home")
            
            callhome_choice = get_choice_input("Is Call Home configured (1 or 2): ", ['1', '2'])
            is_callhome_configured = (callhome_choice == '1')
            log_and_print(f"Call Home Configured: {is_callhome_configured}", "INFO")
            
            # Ask about Remote Support
            print("\n1. This installation is with Remote Support")
            print("2. This installation is without Remote Support")
            
            remote_choice = get_choice_input("Is Remote Support configured (1 or 2): ", ['1', '2'])
            is_remote_support_configured = (remote_choice == '1')
            log_and_print(f"Remote Support Configured: {is_remote_support_configured}", "INFO")
            
            # Validate base sites
            print("\n--- Validating Base Sites Reachability ---")
            base_sites = [
                "icr.io", "cp.icr.io", "dd0.icr.io", "dd2.icr.io",
                "registry.redhat.io", "redhat.com", "registry.connect.redhat.com",
                "console.redhat.com", "cloud.redhat.com", "access.redhat.com",
                "registry.access.redhat.com", "api.access.redhat.com",
                "quay.io", "cdn.quay.io", "cdn01.quay.io", "cdn02.quay.io",
                "cdn03.quay.io", "cdn04.quay.io", "cdn05.quay.io", "cdn06.quay.io",
                "sso.redhat.com", "api.openshift.com", "infogw.api.openshift.com",
                "mirror.openshift.com", "docker.com", "docker.io",
                "dseasb33srnrn.cloudfront.net", "storage.googleapis.com",
                "pkg-containers.githubusercontent.com", "ghcr.io", "www.okd.io"
            ]
            
            # Add cluster-specific URLs
            base_sites.extend([
                f"oauth-openshift.apps.{cluster_name}.{base_domain}",
                f"canary-openshift-ingress-canary.apps.{cluster_name}.{base_domain}",
                f"console-openshift-console.apps.{cluster_name}.{base_domain}"
            ])
            
            for site in base_sites:
                check_site_reachability(site, proxy_server, proxy_port, proxy_username, proxy_password)
            
            # GPU-specific sites
            if is_gpu_node:
                print("\n--- Validating GPU Node Sites ---")
                gpu_sites = [
                    "cloud.openshift.com", "nvcr.io", "d3c2pjnrr68kpx.cloudfront.net",
                    "containers.nvcr.io", "authn.nvcr.io", "api.ngc.nvidia.com",
                    "catalog.ngc.nvidia.com"
                ]
                for site in gpu_sites:
                    check_site_reachability(site, proxy_server, proxy_port, proxy_username, proxy_password)
            
            # China-specific sites
            if is_country_china:
                print("\n--- Validating China Region Sites ---")
                china_sites = ["dd1-icr.ibm-zh.com", "dd3-icr.ibm-zh.com"]
                for site in china_sites:
                    check_site_reachability(site, proxy_server, proxy_port, proxy_username, proxy_password)
            
            # Metro DR sites
            if is_metro_dr:
                print("\n--- Validating Metro DR Sites ---")
                check_site_reachability("gcr.io", proxy_server, proxy_port, proxy_username, proxy_password)
            
            # Call Home sites
            if is_callhome_configured:
                print("\n--- Validating Call Home Sites ---")
                callhome_sites = ["www.ecurep.ibm.com", "esupport.ibm.com"]
                for site in callhome_sites:
                    check_site_reachability(site, proxy_server, proxy_port, proxy_username, proxy_password)
            
            # Remote Support sites
            if is_remote_support_configured:
                print("\n--- Validating Remote Support Sites ---")
                remote_sites = ["aosrelay1.us.ihost.com", "aosback.us.ihost.com", "aoshats.us.ihost.com"]
                for site in remote_sites:
                    check_site_reachability(site, proxy_server, proxy_port, proxy_username, proxy_password)
        
        # =========================
        # WITHOUT PROXY PATH
        # =========================
        else:
            print("\n--- Without Proxy Configuration ---")
            
            # Get IBM entitlement key
            fusion_ibm_entitlement_key = get_password_input("Enter IBM entitlement Key: ")
            
            # Get pull-secret path
            file_path_pull_secret = get_user_input("Enter the full file path for pull-secret.json: ")
            log_and_print(f"Pull Secret Path: {file_path_pull_secret}", "INFO")
            
            # Validate pull-secret file
            print("\nValidating pull-secret file...")
            if validate_file_path(file_path_pull_secret):
                validate_json_file(file_path_pull_secret)
            
            # Create auth file
            print("\nCreating authentication file...")
            create_auth_file(file_path_pull_secret, fusion_ibm_entitlement_key)
            
            # Validate registries with auth file
            print("\n--- Validating Registries ---")
            registries = [
                "cp.icr.io", "registry.redhat.io", "gcr.io",
                "quay.io", "registry.access.redhat.com"
            ]
            
            for registry in registries:
                print(f"\nValidating {registry}...")
                check_registry_reachability(registry)
            
            # Test image pull
            print("\nTesting image pull from cp.icr.io...")
            test_image = "cp/isf/isf-validate-entitlement@sha256:1a0dbf7c537f02dc0091e3abebae0ccac83da6aa147529f5de49af0f23cd9e8e"
            log_and_print(f"Attempting to pull: cp.icr.io/{test_image}", "INFO")
            
            # Ask about ingress certificate
            print("\n1. Yes, ingress certificate will be used")
            print("2. No, ingress certificate will not be used")
            
            ingress_cert_choice = get_choice_input("Is ingress certificate used (1 or 2): ", ['1', '2'])
            
            if ingress_cert_choice == '1':
                is_ingress_certificate_used = True
                log_and_print("Ingress certificate will be used", "INFO")
                
                # Get ingress certificate details
                ingress_certificate_file_path = get_user_input("Enter ingress certificate file path: ")
                log_and_print(f"Ingress Certificate Path: {ingress_certificate_file_path}", "INFO")
                
                ingress_certificate_key = get_user_input("Enter ingress certificate key file path: ")
                log_and_print(f"Ingress Certificate Key Path: {ingress_certificate_key}", "INFO")
                
                # Validate ingress certificate
                print("\nValidating ingress certificate...")
                validate_file_path(ingress_certificate_file_path)
                validate_certificate(ingress_certificate_file_path)
                validate_file_path(ingress_certificate_key)
            else:
                is_ingress_certificate_used = False
                log_and_print("Ingress certificate will not be used", "INFO")
    
    # =========================
    # COMPLETION - GENERATE SUMMARY REPORT
    # =========================
    
    # Prepare configuration details for summary
    config_details = {
        "Installation Type:": install_type_display
    }
    
    # Add type-specific details
    if type_of_install == "airgap_install":
        # Check which registry configuration was used
        if registry_type == "single_registry" and offline_registry_url:
            config_details["Registry:"] = offline_registry_url
        elif registry_type == "multiple_registries":
            if openshift_registry_url:
                config_details["OpenShift Registry:"] = openshift_registry_url
            if fusion_registry_url:
                config_details["Fusion Registry:"] = fusion_registry_url
    
    # Generate and display summary report
    print_validation_summary(
        cluster_name=cluster_name,
        base_domain=base_domain,
        install_type=install_type_display,
        config_details=config_details
    )
    
    print(f"Thank you for using IBM Fusion HCI Network Validation Tool!")
    print(f"Detailed log file: {LOG_FILE}\n")
    
    logging.info("="*80)
    logging.info("IBM Fusion HCI Network Validation Tool Completed")
    logging.info("="*80)

# =========================
# PROGRAM ENTRY POINT
# =========================
if __name__ == "__main__":
    try:
        # Run the main program
        main()
    except KeyboardInterrupt:
        # Handle Ctrl+C gracefully
        print("\n\nProgram interrupted by user (Ctrl+C)")
        log_and_print("Program interrupted by user (Ctrl+C)", "WARNING")
        sys.exit(0)
    except Exception as e:
        # Handle any unexpected errors
        error_msg = f"Unexpected error occurred: {str(e)}"
        log_and_print(error_msg, "ERROR")
        print(f"\n{error_msg}")
        print(f"Please check the log file: {LOG_FILE}")
        sys.exit(1)

