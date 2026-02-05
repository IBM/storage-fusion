#!/usr/bin/env python3
"""
Validate OpenShift AI Installation and LLM Serving

This script checks:
1. OpenShift AI namespace exists
2. KServe is installed
3. LLM InferenceService is deployed and ready
4. LLM endpoint is accessible
"""

import os
import sys
import subprocess
import json
import requests
from typing import Dict, List, Optional

def run_oc_command(cmd: List[str]) -> Dict:
    """Run oc command and return JSON result"""
    try:
        result = subprocess.run(
            ["oc"] + cmd + ["-o", "json"],
            capture_output=True,
            text=True,
            check=True
        )
        return json.loads(result.stdout)
    except subprocess.CalledProcessError as e:
        print(f"❌ Error running oc command: {' '.join(cmd)}")
        print(f"   {e.stderr}")
        return {}
    except json.JSONDecodeError:
        return {}

def check_namespace(namespace: str) -> bool:
    """Check if namespace exists"""
    print(f"📦 Checking namespace: {namespace}...")
    result = run_oc_command(["get", "namespace", namespace])
    if result.get("metadata", {}).get("name") == namespace:
        print(f"   ✅ Namespace '{namespace}' exists")
        return True
    else:
        print(f"   ❌ Namespace '{namespace}' not found")
        return False

def check_kserve_installed() -> bool:
    """Check if KServe is installed"""
    print("🔍 Checking KServe installation...")
    
    # Check for KServe CRDs
    crds = [
        "inferenceservices.serving.kserve.io",
        "servingruntimes.serving.kserve.io"
    ]
    
    all_found = True
    for crd in crds:
        result = run_oc_command(["get", "crd", crd])
        if result.get("metadata", {}).get("name") == crd:
            print(f"   ✅ CRD '{crd}' found")
        else:
            print(f"   ❌ CRD '{crd}' not found")
            all_found = False
    
    return all_found

def check_llm_service(namespace: str, service_name: str) -> Optional[Dict]:
    """Check if LLM InferenceService exists and is ready"""
    print(f"🤖 Checking LLM InferenceService: {service_name}...")
    
    result = run_oc_command(["get", "inferenceservice", service_name, "-n", namespace])
    
    if not result.get("metadata"):
        print(f"   ❌ InferenceService '{service_name}' not found")
        return None
    
    # Check status
    status = result.get("status", {})
    conditions = status.get("conditions", [])
    
    ready = False
    for condition in conditions:
        if condition.get("type") == "Ready":
            ready = condition.get("status") == "True"
            break
    
    if ready:
        print(f"   ✅ InferenceService '{service_name}' is Ready")
        
        # Get endpoint URL
        url = status.get("url", "")
        if url:
            print(f"   📍 Endpoint: {url}")
        
        return {
            "name": service_name,
            "namespace": namespace,
            "url": url,
            "ready": True
        }
    else:
        print(f"   ⏳ InferenceService '{service_name}' is not ready yet")
        return {
            "name": service_name,
            "namespace": namespace,
            "ready": False
        }

def check_llm_endpoint(endpoint: str, timeout: int = 10) -> bool:
    """Check if LLM endpoint is accessible"""
    print(f"🌐 Checking LLM endpoint: {endpoint}...")
    
    try:
        # Try health endpoint first
        health_url = endpoint.replace("/v1/completions", "/health")
        response = requests.get(health_url, timeout=timeout)
        if response.status_code == 200:
            print(f"   ✅ LLM endpoint is accessible")
            return True
    except:
        pass
    
    # Try completions endpoint
    try:
        payload = {
            "prompt": "test",
            "max_tokens": 5
        }
        headers = {
            "Content-Type": "application/json",
            "Authorization": "Bearer EMPTY"
        }
        response = requests.post(
            endpoint,
            json=payload,
            headers=headers,
            timeout=timeout
        )
        if response.status_code == 200:
            print(f"   ✅ LLM endpoint is accessible and responding")
            return True
        else:
            print(f"   ⚠️  LLM endpoint returned status: {response.status_code}")
            return False
    except requests.exceptions.RequestException as e:
        print(f"   ❌ Cannot reach LLM endpoint: {e}")
        return False

def get_llm_pods(namespace: str, service_name: str) -> List[Dict]:
    """Get LLM pods"""
    print(f"🔍 Checking LLM pods for '{service_name}'...")
    
    label_selector = f"serving.kserve.io/inferenceservice={service_name}"
    result = run_oc_command(["get", "pods", "-n", namespace, "-l", label_selector])
    
    items = result.get("items", [])
    pods = []
    for item in items:
        pod_name = item.get("metadata", {}).get("name", "")
        status = item.get("status", {}).get("phase", "Unknown")
        pods.append({
            "name": pod_name,
            "status": status
        })
        print(f"   📦 Pod: {pod_name} - Status: {status}")
    
    return pods

def main():
    """Main validation function"""
    print("=" * 60)
    print("🔍 OpenShift AI Validation")
    print("=" * 60)
    print()
    
    # Configuration
    dsc_namespace = os.getenv("DSC_NAMESPACE", "default-dsc")
    llm_service_name = os.getenv("LLM_SERVICE_NAME", "granite-llm")
    llm_endpoint = os.getenv("LLM_ENDPOINT", "")
    
    results = {
        "namespace": False,
        "kserve": False,
        "llm_service": False,
        "llm_endpoint": False
    }
    
    # 1. Check namespace
    results["namespace"] = check_namespace(dsc_namespace)
    print()
    
    if not results["namespace"]:
        print("❌ Namespace not found. Please deploy OpenShift AI first.")
        sys.exit(1)
    
    # 2. Check KServe
    results["kserve"] = check_kserve_installed()
    print()
    
    if not results["kserve"]:
        print("❌ KServe not installed. Please install KServe on OpenShift AI.")
        sys.exit(1)
    
    # 3. Check LLM service
    llm_info = check_llm_service(dsc_namespace, llm_service_name)
    print()
    
    if llm_info:
        results["llm_service"] = llm_info.get("ready", False)
        
        # Get pods
        pods = get_llm_pods(dsc_namespace, llm_service_name)
        print()
        
        # 4. Check endpoint
        if llm_info.get("url"):
            endpoint = f"{llm_info['url']}/v1/completions"
        elif llm_endpoint:
            endpoint = llm_endpoint
        else:
            # Try to construct endpoint from service
            endpoint = f"http://{llm_service_name}-predictor-default.{dsc_namespace}.svc.cluster.local:8080/v1/completions"
        
        results["llm_endpoint"] = check_llm_endpoint(endpoint)
        print()
    else:
        print("❌ LLM InferenceService not found or not ready.")
        sys.exit(1)
    
    # Summary
    print("=" * 60)
    print("📊 Validation Summary")
    print("=" * 60)
    print(f"Namespace:        {'✅' if results['namespace'] else '❌'}")
    print(f"KServe:           {'✅' if results['kserve'] else '❌'}")
    print(f"LLM Service:     {'✅' if results['llm_service'] else '❌'}")
    print(f"LLM Endpoint:    {'✅' if results['llm_endpoint'] else '❌'}")
    print()
    
    if all(results.values()):
        print("✅ All checks passed! OpenShift AI is ready.")
        print()
        print("📝 Next steps:")
        print("   1. Set LLM_ENDPOINT environment variable:")
        if llm_info.get("url"):
            print(f"      export LLM_ENDPOINT={llm_info['url']}/v1/completions")
        else:
            print(f"      export LLM_ENDPOINT={endpoint}")
        print("   2. Configure CAS endpoint")
        print("   3. Deploy chat application via GitOps")
        sys.exit(0)
    else:
        print("❌ Some checks failed. Please fix the issues above.")
        sys.exit(1)

if __name__ == "__main__":
    main()

