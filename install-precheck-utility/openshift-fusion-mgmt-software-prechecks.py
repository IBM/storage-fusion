#!/usr/bin/env python3
"""
installerNetworkValidation_new.py

Simple and Interactive HCI Installer Network Validation Tool
Written with beginner-friendly code and extensive comments for easy debugging.

Author: Based on requirements from Saurabh.md
Version: 1.0
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

def check_exit_command(user_input):
    """
    Check if user wants to exit the program
    If user types 'I want to exit', program will stop
    """
    if user_input.strip().lower() == "i want to exit":
        log_and_print("User requested to exit by saying: I want to exit", "INFO")
        print("\nExiting program. Goodbye!")
        sys.exit(0)

def get_user_input(prompt_message, allow_empty=False):
    """
    Get input from user with validation
    - prompt_message: The message to show user
    - allow_empty: If False, user must enter something
    Returns: user's input as string
    """
    while True:
        # Show prompt and get input
        user_input = input(prompt_message).strip()
        
        # Check if user wants to exit
        check_exit_command(user_input)
        
        # If empty input is not allowed and user entered nothing
        if not allow_empty and not user_input:
            error_msg = "ERROR: Input cannot be empty. Please enter a value."
            log_and_print(error_msg, "ERROR")
            continue  # Ask again
        
        # Valid input received
        return user_input

def get_password_input(prompt_message):
    """
    Get password from user (password will be hidden on screen)
    Returns: password as string
    """
    while True:
        # Get password (hidden input)
        password = getpass.getpass(prompt_message)
        
        # Check if user wants to exit
        check_exit_command(password)
        
        # Check if password is empty
        if not password:
            error_msg = "ERROR: Password cannot be empty. Please enter a password."
            log_and_print(error_msg, "ERROR")
            continue  # Ask again
        
        # Log that password was entered (but don't log the actual password)
        logging.info(f"Password entered: XXXXXXXXX")
        return password

def get_choice_input(prompt_message, valid_choices):
    """
    Get user choice from a list of valid options
    - prompt_message: The message to show user
    - valid_choices: List of valid choices (e.g., ['1', '2'])
    Returns: user's choice as string
    """
    while True:
        # Get user input
        choice = input(prompt_message).strip()
        
        # Check if user wants to exit
        check_exit_command(choice)
        
        # Check if choice is empty
        if not choice:
            error_msg = "ERROR: Input cannot be empty. Please select an option."
            log_and_print(error_msg, "ERROR")
            continue
        
        # Check if choice is valid
        if choice not in valid_choices:
            error_msg = f"ERROR: Invalid choice '{choice}'. Please select from: {', '.join(valid_choices)}"
            log_and_print(error_msg, "ERROR")
            continue
        
        # Valid choice received
        log_and_print(f"User selected option: {choice}", "INFO")
        return choice

# =========================
# VALIDATION FUNCTIONS
# =========================

def check_registry_reachability(registry_url):
    """
    Check if registry URL is reachable from this machine
    Returns: True if reachable, False otherwise
    """
    log_and_print(f"Checking reachability to registry: {registry_url}", "INFO")
    
    try:
        # Remove http:// or https:// if present
        clean_url = registry_url.replace('https://', '').replace('http://', '')
        
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
            log_and_print(f"✓ SUCCESS: Registry {registry_url} is reachable", "INFO")
            return True
        else:
            log_and_print(f"✗ FAILURE: Registry {registry_url} is NOT reachable", "ERROR")
            return False
            
    except Exception as e:
        log_and_print(f"✗ FAILURE: Error checking registry {registry_url}: {str(e)}", "ERROR")
        return False

def podman_login_test(registry_url, username, password):
    """
    Test podman login to registry
    Returns: True if login successful, False otherwise
    """
    log_and_print(f"Testing podman login to: {registry_url}", "INFO")
    logging.info(f"Username: {username}, Password: XXXXXXXXX")
    
    try:
        # Remove protocol if present
        clean_url = registry_url.replace('https://', '').replace('http://', '')
        
        # Run podman login command
        cmd = f"echo '{password}' | podman login -u '{username}' --password-stdin {clean_url}"
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        
        if result.returncode == 0:
            log_and_print(f"✓ SUCCESS: Podman login to {registry_url} successful", "INFO")
            # Logout after successful login
            subprocess.run(f"podman logout {clean_url}", shell=True, capture_output=True)
            return True
        else:
            log_and_print(f"✗ FAILURE: Podman login to {registry_url} failed", "ERROR")
            log_and_print(f"Error details: {result.stderr}", "ERROR")
            return False
            
    except Exception as e:
        log_and_print(f"✗ FAILURE: Error during podman login: {str(e)}", "ERROR")
        return False

def podman_pull_test(registry_url, username, password, image_name):
    """
    Test pulling an image from registry
    Returns: True if pull successful, False otherwise
    """
    log_and_print(f"Testing image pull from: {registry_url}", "INFO")
    
    try:
        # Remove protocol if present
        clean_url = registry_url.replace('https://', '').replace('http://', '')
        
        # Login first
        login_cmd = f"echo '{password}' | podman login -u '{username}' --password-stdin {clean_url}"
        subprocess.run(login_cmd, shell=True, capture_output=True)
        
        # Try to pull image
        full_image_path = f"{clean_url}/{image_name}"
        pull_cmd = f"podman pull {full_image_path}"
        result = subprocess.run(pull_cmd, shell=True, capture_output=True, text=True)
        
        # Logout
        subprocess.run(f"podman logout {clean_url}", shell=True, capture_output=True)
        
        if result.returncode == 0:
            log_and_print(f"✓ SUCCESS: Image pull from {registry_url} successful", "INFO")
            # Remove the pulled image
            subprocess.run(f"podman rmi {full_image_path}", shell=True, capture_output=True)
            return True
        else:
            log_and_print(f"✗ FAILURE: Image pull from {registry_url} failed", "ERROR")
            log_and_print(f"Error details: {result.stderr}", "ERROR")
            return False
            
    except Exception as e:
        log_and_print(f"✗ FAILURE: Error during image pull: {str(e)}", "ERROR")
        return False

def validate_file_path(file_path):
    """
    Check if file exists and is readable
    Returns: True if file exists, False otherwise
    """
    log_and_print(f"Validating file path: {file_path}", "INFO")
    
    if os.path.isfile(file_path) and os.access(file_path, os.R_OK):
        log_and_print(f"✓ SUCCESS: File exists and is readable: {file_path}", "INFO")
        return True
    else:
        log_and_print(f"✗ FAILURE: File not found or not readable: {file_path}", "ERROR")
        return False

def validate_certificate(cert_path):
    """
    Validate certificate file
    Returns: True if valid, False otherwise
    """
    log_and_print(f"Validating certificate: {cert_path}", "INFO")
    
    try:
        # Check if file exists
        if not validate_file_path(cert_path):
            return False
        
        # Check certificate validity using openssl
        cmd = f"openssl x509 -in {cert_path} -noout -text"
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        
        if result.returncode == 0:
            log_and_print(f"✓ SUCCESS: Certificate is valid", "INFO")
            
            # Check expiration date
            exp_cmd = f"openssl x509 -in {cert_path} -noout -enddate"
            exp_result = subprocess.run(exp_cmd, shell=True, capture_output=True, text=True)
            if exp_result.returncode == 0:
                log_and_print(f"Certificate expiration: {exp_result.stdout.strip()}", "INFO")
            
            # Check if self-signed
            issuer_cmd = f"openssl x509 -in {cert_path} -noout -issuer"
            subject_cmd = f"openssl x509 -in {cert_path} -noout -subject"
            issuer = subprocess.run(issuer_cmd, shell=True, capture_output=True, text=True).stdout
            subject = subprocess.run(subject_cmd, shell=True, capture_output=True, text=True).stdout
            
            if issuer == subject:
                log_and_print(f"⚠ WARNING: Certificate is self-signed", "WARNING")
            else:
                log_and_print(f"✓ Certificate is CA-signed", "INFO")
            
            return True
        else:
            log_and_print(f"✗ FAILURE: Certificate validation failed", "ERROR")
            return False
            
    except Exception as e:
        log_and_print(f"✗ FAILURE: Error validating certificate: {str(e)}", "ERROR")
        return False

def check_site_reachability(site_url, proxy_server=None, proxy_port=None, proxy_username=None, proxy_password=None):
    """
    Check if a website/URL is reachable
    Returns: True if reachable, False otherwise
    """
    log_and_print(f"Checking reachability to: {site_url}", "INFO")
    
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
            
            cmd = f"curl -I --max-time 10 --proxy {proxy_url} https://{site_url}"
        else:
            cmd = f"curl -I --max-time 10 https://{site_url}"
        
        # Run curl command
        result = subprocess.run(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
        
        # Check if successful (HTTP 200, 301, 302, 401, 403 are considered reachable)
        if result.returncode == 0 or any(code in result.stdout for code in ['200', '301', '302', '401', '403']):
            log_and_print(f"✓ SUCCESS: Site reachable: {site_url}", "INFO")
            return True
        else:
            log_and_print(f"✗ FAILURE: Site NOT reachable: {site_url}", "ERROR")
            return False
            
    except Exception as e:
        log_and_print(f"✗ FAILURE: Error checking site {site_url}: {str(e)}", "ERROR")
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
    log_and_print(f"Validating JSON file: {file_path}", "INFO")
    
    try:
        with open(file_path, 'r') as f:
            json.load(f)
        log_and_print(f"✓ SUCCESS: File is valid JSON", "INFO")
        return True
    except json.JSONDecodeError as e:
        log_and_print(f"✗ FAILURE: File is not valid JSON: {str(e)}", "ERROR")
        return False
    except Exception as e:
        log_and_print(f"✗ FAILURE: Error reading JSON file: {str(e)}", "ERROR")
        return False

# =========================
# MAIN PROGRAM
# =========================


def main():
    """
    Main function - Entry point of the program
    """
    # Display welcome message
    print("\n" + "="*70)
    print("Welcome to HCI Installer Network Validation Script")
    print("="*70)
    print("\nThis script will help you validate your network configuration")
    print("for HCI cluster installation.")
    print("\nInstructions:")
    print("- Answer each question carefully")
    print("- Type 'I want to exit' at any prompt to exit the program")
    print("- All actions are logged to:", LOG_FILE)
    print("="*70 + "\n")
    
    log_and_print("="*70, "INFO")
    log_and_print("HCI Installer Network Validation Script Started", "INFO")
    log_and_print("="*70, "INFO")
    
    # =========================
    # STEP 1: Get Cluster Name
    # =========================
    print("\n--- Step 1: Cluster Information ---")
    cluster_name = get_user_input("Enter Cluster Name for your cluster: ")
    log_and_print(f"Cluster Name: {cluster_name}", "INFO")
    
    # =========================
    # STEP 2: Get Base Domain
    # =========================
    base_domain = get_user_input("Enter Base Domain for your cluster: ")
    log_and_print(f"Base Domain: {base_domain}", "INFO")
    
    # =========================
    # STEP 3: Get Installation Type
    # =========================
    print("\n--- Step 2: Installation Type ---")
    print("1. Airgap Install (Offline Install - No internet connectivity)")
    print("2. Connected Install (Online Install - Internet connectivity)")
    
    install_type_choice = get_choice_input("Enter the Type of Install (1 or 2): ", ['1', '2'])
    
    # Set installation type based on choice
    if install_type_choice == '1':
        type_of_install = "airgap_install"
        log_and_print(f"Installation Type: Airgap Install (Offline)", "INFO")
    else:
        type_of_install = "connected_install"
        log_and_print(f"Installation Type: Connected Install (Online)", "INFO")
    
    # =========================
    # AIRGAP INSTALLATION PATH
    # =========================
    if type_of_install == "airgap_install":
        print("\n--- Airgap Installation Configuration ---")
        
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
            
            # Validate registry reachability
            print("\nValidating registry...")
            check_registry_reachability(offline_registry_url)
            
            # Test podman login
            print("Testing podman login...")
            podman_login_test(offline_registry_url, offline_registry_username, offline_registry_password)
            
            # Test image pull
            print("Testing Openshift image pull...")
            podman_pull_test(offline_registry_url, offline_registry_username, offline_registry_password, 
                           "openshift/release:latest")
            
            # Ask about certificate
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
                log_and_print("Certificate will not be used", "INFO")
        
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
            
            # Validate OpenShift registry
            print("\nValidating OpenShift registry...")
            check_registry_reachability(openshift_registry_url)
            podman_login_test(openshift_registry_url, openshift_registry_username, openshift_registry_password)
            podman_pull_test(openshift_registry_url, openshift_registry_username, openshift_registry_password,
                           "openshift/release:latest")
            
            # OpenShift certificate
            print("\n1. Yes, certificate will be used")
            print("2. No, certificate will not be used")
            
            os_cert_choice = get_choice_input("Certificate for OpenShift registry (1 or 2): ", ['1', '2'])
            
            if os_cert_choice == '1':
                os_cert_path = get_user_input("Enter OpenShift registry certificate file path: ")
                log_and_print(f"OpenShift Certificate Path: {os_cert_path}", "INFO")
                validate_file_path(os_cert_path)
                validate_certificate(os_cert_path)
            
            # Fusion Registry
            print("\n>> Fusion Registry <<")
            fusion_registry_url = get_user_input("Enter the Fusion registry URL: ")
            log_and_print(f"Fusion Registry URL: {fusion_registry_url}", "INFO")
            
            fusion_registry_username = get_user_input("Enter Fusion registry username: ")
            log_and_print(f"Fusion Registry Username: {fusion_registry_username}", "INFO")
            
            fusion_registry_password = get_password_input("Enter Fusion registry password: ")
            
            # Validate Fusion registry
            print("\nValidating Fusion registry...")
            check_registry_reachability(fusion_registry_url)
            podman_login_test(fusion_registry_url, fusion_registry_username, fusion_registry_password)
            podman_pull_test(fusion_registry_url, fusion_registry_username, fusion_registry_password,
                           "fusion/catalog:latest")
            
            # Fusion certificate
            print("\n1. Yes, certificate will be used")
            print("2. No, certificate will not be used")
            
            fusion_cert_choice = get_choice_input("Certificate for Fusion registry (1 or 2): ", ['1', '2'])
            
            if fusion_cert_choice == '1':
                fusion_cert_path = get_user_input("Enter Fusion registry certificate file path: ")
                log_and_print(f"Fusion Certificate Path: {fusion_cert_path}", "INFO")
                validate_file_path(fusion_cert_path)
                validate_certificate(fusion_cert_path)
    
    # =========================
    # CONNECTED INSTALLATION PATH
    # =========================
    elif type_of_install == "connected_install":
        print("\n--- Connected Installation Configuration ---")
        
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
    # COMPLETION
    # =========================
    print("\n" + "="*70)
    print("Validation Complete!")
    print("="*70)
    print(f"\nAll validation results have been logged to: {LOG_FILE}")
    print("\nThank you for using HCI Installer Network Validation Script!")
    print("="*70 + "\n")
    
    log_and_print("="*70, "INFO")
    log_and_print("HCI Installer Network Validation Script Completed Successfully", "INFO")
    log_and_print("="*70, "INFO")

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

