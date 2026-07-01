#!/usr/bin/env python3
"""
Model Registry GitOps Reconciler

This reconciler watches for model definitions in ConfigMaps and ensures
they are registered in the OpenShift AI Model Registry (MLflow).

It handles:
- Downloading models from Hugging Face
- Uploading to ODF storage
- Registering with MLflow Model Registry
- Updating model catalog ConfigMaps
"""

import os
import sys
import time
import logging
import yaml
import shutil
from typing import Dict, List, Optional, Any
from dataclasses import dataclass
import ssl

# Configure SSL to not verify certificates for self-signed certs
# Set environment variables before any imports
if os.getenv("REGISTRY_VERIFY_SSL", "false").lower() != "true":
    # Disable SSL verification globally for Python
    os.environ['PYTHONHTTPSVERIFY'] = '0'
    os.environ['CURL_CA_BUNDLE'] = ''
    os.environ['REQUESTS_CA_BUNDLE'] = ''
    # Set SSL context to not verify
    ssl._create_default_https_context = ssl._create_unverified_context

import boto3
from botocore.client import Config
from kubernetes import client, config, watch
from huggingface_hub import snapshot_download, login
from model_registry import ModelRegistry

# Configure logging
logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO"),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


@dataclass
class ModelDefinition:
    """Represents a model definition from YAML"""
    name: str
    model_name: str
    version: str
    description: str
    base_model: Dict[str, Any]
    storage: Dict[str, Any]
    metadata: Dict[str, Any]
    governance: Optional[Dict[str, Any]] = None
    tags: Optional[List[str]] = None


class ModelRegistryReconciler:
    """Reconciles model definitions with Model Registry"""

    def __init__(self):
        """Initialize the reconciler"""
        # Load Kubernetes config
        try:
            config.load_incluster_config()
            logger.info("Loaded in-cluster Kubernetes config")
        except:
            config.load_kube_config()
            logger.info("Loaded local Kubernetes config")

        self.k8s_core = client.CoreV1Api()
        
        # Configurable namespace settings
        self.namespace = os.getenv("NAMESPACE", "model-registry-gitops")
        self.target_namespace = os.getenv("TARGET_NAMESPACE", "rhoai-model-registries")
        self.registry_namespace = os.getenv("REGISTRY_NAMESPACE", "rhoai-model-registries")
        
        # Configurable OBC name
        self.obc_name = os.getenv("OBC_NAME", "model-registry-artifacts")
        
        # Model Registry configuration
        registry_host = os.getenv("REGISTRY_HOST", f"model-registry.{self.registry_namespace}.svc.cluster.local")
        registry_port = int(os.getenv("REGISTRY_PORT", "8443"))
        registry_secure = os.getenv("REGISTRY_SECURE", "true").lower() == "true"
        verify_ssl = os.getenv("REGISTRY_VERIFY_SSL", "false").lower() == "true"
        
        # Get service account token for authentication
        user_token = None
        if registry_secure:
            try:
                with open('/var/run/secrets/kubernetes.io/serviceaccount/token', 'r') as f:
                    user_token = f.read().strip()
                logger.info("Loaded service account token for authentication")
            except Exception as e:
                logger.warning(f"Could not load service account token: {e}")
        
        # Construct full server URL with protocol
        protocol = "https" if registry_secure else "http"
        server_url = f"{protocol}://{registry_host}"
        
        # Log SSL verification status
        if registry_secure and not verify_ssl:
            logger.warning("SSL verification disabled for self-signed certificates")
        
        self.registry = ModelRegistry(
            server_address=server_url,
            port=registry_port,
            author="GitOps Reconciler",
            is_secure=registry_secure,
            user_token=user_token
        )
        logger.info(f"Connected to Model Registry at {server_url}:{registry_port} (SSL verify: {verify_ssl})")

        # S3 configuration
        self.s3_config = self._load_s3_config()
        self.s3_client = self._create_s3_client()

        # Hugging Face token
        self.hf_token = self._load_hf_token()
        if self.hf_token:
            login(token=self.hf_token)
            logger.info("Authenticated with Hugging Face")

        # Reconciliation state
        self.reconcile_interval = int(os.getenv("RECONCILE_INTERVAL", "300"))
        self.processed_models = set()
        self.sequential_delay = int(os.getenv("SEQUENTIAL_DELAY", "30"))  # Delay between models in seconds
        self.cleanup_after_upload = os.getenv("CLEANUP_AFTER_UPLOAD", "true").lower() == "true"

    def _load_s3_config(self) -> Dict[str, str]:
        """Load S3 configuration from secret and configmap"""
        try:
            # Read credentials from secret (using configurable OBC name)
            secret = self.k8s_core.read_namespaced_secret(
                self.obc_name,
                self.target_namespace
            )

            # Read bucket info from configmap (using configurable OBC name)
            configmap = self.k8s_core.read_namespaced_config_map(
                self.obc_name,
                self.target_namespace
            )

            import base64
            bucket_host = configmap.data.get("BUCKET_HOST", "")
            bucket_port = configmap.data.get("BUCKET_PORT", "443")
            bucket_name = configmap.data.get("BUCKET_NAME", "")

            # Construct endpoint URL
            endpoint = f"https://{bucket_host}:{bucket_port}" if bucket_host else ""

            config = {
                "access_key": base64.b64decode(secret.data.get("AWS_ACCESS_KEY_ID", "")).decode(),
                "secret_key": base64.b64decode(secret.data.get("AWS_SECRET_ACCESS_KEY", "")).decode(),
                "endpoint": endpoint,
                "bucket": bucket_name,
            }
            logger.info(f"Loaded S3 config: endpoint={config['endpoint']}, bucket={config['bucket']}")
            return config
        except Exception as e:
            logger.error(f"Failed to load S3 config: {e}")
            raise

    def _create_s3_client(self):
        """Create S3 client"""
        return boto3.client(
            's3',
            endpoint_url=self.s3_config["endpoint"],
            aws_access_key_id=self.s3_config["access_key"],
            aws_secret_access_key=self.s3_config["secret_key"],
            config=Config(signature_version='s3v4'),
            verify=False  # For self-signed certs in ODF
        )

    def _load_hf_token(self) -> Optional[str]:
        """Load Hugging Face token from secret"""
        try:
            secret = self.k8s_core.read_namespaced_secret(
                "huggingface-token",
                self.target_namespace
            )
            import base64
            token = base64.b64decode(secret.data.get("token", "")).decode()
            return token if token else None
        except:
            logger.info("No Hugging Face token found (only public models will work)")
            return None

    def parse_model_definition(self, yaml_content: str) -> Optional[ModelDefinition]:
        """Parse model definition from YAML"""
        try:
            data = yaml.safe_load(yaml_content)

            # Validate required fields
            if data.get("apiVersion") != "v1" or data.get("kind") != "ModelVersion":
                logger.warning(f"Invalid apiVersion or kind: {data.get('apiVersion')}, {data.get('kind')}")
                return None

            metadata = data.get("metadata", {})
            spec = data.get("spec", {})

            return ModelDefinition(
                name=metadata.get("name"),
                model_name=spec.get("modelName"),
                version=spec.get("version", "1.0.0"),
                description=spec.get("description", ""),
                base_model=spec.get("baseModel", {}),
                storage=spec.get("storage", {}),
                metadata=spec.get("metadata", {}),
                governance=spec.get("governance"),
                tags=spec.get("tags", [])
            )
        except Exception as e:
            logger.error(f"Failed to parse model definition: {e}")
            return None

    def download_from_huggingface(self, model_def: ModelDefinition) -> Optional[str]:
        """Download model from Hugging Face"""
        try:
            hf_repo = model_def.base_model.get("name")
            if not hf_repo:
                logger.error("No Hugging Face repository specified")
                return None

            logger.info(f"=" * 80)
            logger.info(f"🔽 DOWNLOADING MODEL WEIGHTS: {model_def.name}")
            logger.info(f"  📦 Model Name: {model_def.model_name}")
            logger.info(f"  🏷️  Version: {model_def.version}")
            logger.info(f"  🤗 Hugging Face Repo: {hf_repo}")
            logger.info(f"  💾 Expected Size: {model_def.storage.get('size', 'unknown')}")
            logger.info(f"  📂 Cache Directory: /tmp/hf_cache")
            logger.info(f"=" * 80)
            logger.info(f"⏳ Starting download... This may take several minutes depending on model size.")

            local_dir = snapshot_download(
                repo_id=hf_repo,
                cache_dir="/tmp/hf_cache",
                token=self.hf_token if self.hf_token else None,
                allow_patterns=["*.json", "*.safetensors", "*.model",
                                "tokenizer*", "*.txt", "*.bin"],
                ignore_patterns=["*.msgpack", "*.h5", "*.ot"],
                resume_download=True
            )

            logger.info(f"✅ Download complete! Model saved to: {local_dir}")
            logger.info(f"=" * 80)
            return local_dir
        except Exception as e:
            logger.error(f"Failed to download from Hugging Face: {e}")
            if "401" in str(e) or "gated" in str(e).lower():
                logger.error(f"Model {hf_repo} requires authentication.Please configure Hugging Face token.")
            return None

    def upload_to_s3(self, local_dir: str, model_def: ModelDefinition) -> Optional[str]:
        """Upload model to S3/ODF storage"""
        try:
            bucket = self.s3_config["bucket"]
            s3_prefix = f"{model_def.name}/{model_def.version}"

            logger.info(f"UPLOADING TO S3: {model_def.name}")
            logger.info(f"  Bucket: {bucket}")
            logger.info(f"  Prefix: {s3_prefix}")

            # Ensure bucket exists
            try:
                self.s3_client.head_bucket(Bucket=bucket)
            except:
                logger.info(f"Creating bucket {bucket}...")
                self.s3_client.create_bucket(Bucket=bucket)

            # Upload files
            file_count = 0
            for root, dirs, files in os.walk(local_dir):
                for file in files:
                    local_path = os.path.join(root, file)
                    relative_path = os.path.relpath(local_path, local_dir)
                    s3_key = os.path.join(s3_prefix, relative_path)

                    self.s3_client.upload_file(local_path, bucket, s3_key)
                    file_count += 1

            logger.info(f"Uploaded {file_count} files")

            # Construct S3 URI
            endpoint = self.s3_config["endpoint"]
            s3_uri = f"{endpoint}/{bucket}/{s3_prefix}"
            return s3_uri
        except Exception as e:
            logger.error(f"Failed to upload to S3: {e}")
            return None

    def register_model(self, model_def: ModelDefinition, s3_uri: str) -> bool:
        """Register model with Model Registry"""
        try:
            logger.info(f"Registering model {model_def.model_name} version {model_def.version}...")

            # Check if model already exists
            try:
                existing_model = self.registry.get_registered_model(model_def.model_name)
                try:
                    existing_version = self.registry.get_model_version(model_def.model_name, model_def.version)
                    logger.info(f"Model {model_def.model_name} version {model_def.version} already exists")
                    return True
                except:
                    logger.info(f"Registering new version {model_def.version}")
            except:
                logger.info(f"Registering new model {model_def.model_name}")

            # Register the model
            model = self.registry.register_model(
                model_def.model_name,
                s3_uri,
                model_format_name="safetensors",
                model_format_version="1.0",
                version=model_def.version,
                description=model_def.description,
                metadata={
                    "source": model_def.base_model.get("source", "unknown"),
                    "hf_id": model_def.base_model.get("name", ""),
                    "storage": "odf",
                    "governance_status": model_def.governance.get("complianceStatus") if model_def.governance else "unknown"
                }
            )

            logger.info(f"Successfully registered model {model.name} (ID: {model.id})")
            return True
        except Exception as e:
            logger.error(f"Failed to register model: {e}")
            import traceback
            traceback.print_exc()
            return False

    def update_catalog(self, model_def: ModelDefinition, s3_uri: str) -> bool:
        """Update model catalog ConfigMap"""
        try:
            cm_name = "model-catalog-sources"

            # Get or create ConfigMap
            try:
                cm = self.k8s_core.read_namespaced_config_map(cm_name, self.target_namespace)
                logger.info(f"Updating existing ConfigMap {cm_name}")
            except:
                logger.info(f"Creating new ConfigMap {cm_name}")
                cm = client.V1ConfigMap(
                    metadata=client.V1ObjectMeta(name=cm_name, namespace=self.target_namespace),
                    data={}
                )

            # Ensure sources.yaml exists
            if "sources.yaml" not in cm.data:
                cm.data["sources.yaml"] = yaml.dump({
                    "catalogs": [{
                        "name": "Custom Models",
                        "id": "custom-models",
                        "type": "yaml",
                        "properties": {
                            "yamlCatalogPath": "/data/user-sources/custom-models.yaml"
                        }
                    }]
                })

            # Parse or create custom-models.yaml
            if "custom-models.yaml" in cm.data:
                custom_models = yaml.safe_load(cm.data["custom-models.yaml"])
                if not isinstance(custom_models, dict):
                    custom_models = {"models": []}
                if "models" not in custom_models:
                    custom_models["models"] = []
                if not isinstance(custom_models["models"], list):
                    custom_models["models"] = []
            else:
                custom_models = {"models": []}

            # Create model entry
            model_entry = {
                "name": model_def.name,
                "description": model_def.description,
                "customProperties": {
                    "model_type": {
                        "metadataType": "MetadataStringValue",
                        "string_value": "generative"
                    },
                    "author": {
                        "metadataType": "MetadataStringValue",
                        "string_value": model_def.base_model.get("source", "unknown")
                    },
                    "version": {
                        "metadataType": "MetadataStringValue",
                        "string_value": model_def.version
                    },
                    "source": {
                        "metadataType": "MetadataStringValue",
                        "string_value": model_def.base_model.get("source", "unknown")
                    }
                },
                "artifacts": [{
                    "name": "model-artifact",
                    "uri": f"s3://{self.s3_config['bucket']}/{model_def.name}/{model_def.version}"
                }]
            }

            # Update or add model
            model_exists = False
            for i, model in enumerate(custom_models["models"]):
                if model.get("name") == model_def.name:
                    custom_models["models"][i] = model_entry
                    model_exists = True
                    logger.info(f"Updated existing model entry for {model_def.name}")
                    break

            if not model_exists:
                custom_models["models"].append(model_entry)
                logger.info(f"Added new model entry for {model_def.name}")

            # Update ConfigMap
            cm.data["custom-models.yaml"] = yaml.dump(custom_models, default_flow_style=False, sort_keys=False)

            try:
                self.k8s_core.replace_namespaced_config_map(cm_name, self.target_namespace, cm)
            except:
                self.k8s_core.create_namespaced_config_map(self.target_namespace, cm)

            logger.info(f"Updated catalog ConfigMap")
            return True
        except Exception as e:
            logger.error(f"Failed to update catalog: {e}")
            import traceback
            traceback.print_exc()
            return False

    def reconcile_model(self, yaml_content: str) -> bool:
        """Reconcile a single model definition"""
        model_def = self.parse_model_definition(yaml_content)
        if not model_def:
            return False

        logger.info("=" * 80)
        logger.info(f"RECONCILING MODEL: {model_def.name}")
        logger.info(f"  Model Name: {model_def.model_name}")
        logger.info(f"  Version: {model_def.version}")
        logger.info(f"  Storage Type: {model_def.storage.get('type', 'unknown')}")
        logger.info("=" * 80)

        # Check if already processed
        model_key = f"{model_def.name}:{model_def.version}"
        if model_key in self.processed_models:
            logger.info(f"Model {model_key} already processed, skipping")
            return True

        # Download from source
        if model_def.storage.get("type") == "huggingface":
            local_dir = self.download_from_huggingface(model_def)
            if not local_dir:
                return False

            # Upload to S3
            s3_uri = self.upload_to_s3(local_dir, model_def)
            if not s3_uri:
                return False

            # Cleanup local files
            if self.cleanup_after_upload:
                try:
                    logger.info(f"Cleaning up local directory: {local_dir}")
                    shutil.rmtree(local_dir)
                except Exception as e:
                    logger.warning(f"Failed to cleanup {local_dir}: {e}")
        else:
            # Use existing S3 URI
            s3_uri = model_def.storage.get("uri", "")

        # Register with Model Registry
        if not self.register_model(model_def, s3_uri):
            return False

        # Update catalog
        if not self.update_catalog(model_def, s3_uri):
            logger.warning("Failed to update catalog, but model is registered")

        # Mark as processed
        self.processed_models.add(model_key)
        logger.info(f"Successfully reconciled model: {model_def.name}")
        return True

    def watch_configmaps(self):
        """Watch for ConfigMap changes"""
        logger.info(f"Watching ConfigMaps in namespace {self.namespace}")

        w = watch.Watch()
        for event in w.stream(
            self.k8s_core.list_namespaced_config_map,
            namespace=self.namespace,
            label_selector="app=model-registry-gitops"
        ):
            event_type = event['type']
            cm = event['object']
            cm_name = cm.metadata.name

            logger.info(f"ConfigMap event: {event_type} - {cm_name}")

            if event_type in ['ADDED', 'MODIFIED']:
                # Process each model definition in the ConfigMap sequentially
                for key, value in cm.data.items():
                    if key.endswith('.yaml'):
                        logger.info(f"Processing {key} from {cm_name}")
                        self.reconcile_model(value)
                        # Add delay between models to prevent memory issues
                        if self.sequential_delay > 0:
                            logger.info(f"Waiting {self.sequential_delay}s before next model...")
                            time.sleep(self.sequential_delay)

    def run(self):
        """Run the reconciler"""
        logger.info("Starting Model Registry GitOps Reconciler")
        logger.info(f"Namespace: {self.namespace}")
        logger.info(f"Target Namespace: {self.target_namespace}")
        logger.info(f"Reconcile Interval: {self.reconcile_interval}s")

        try:
            self.watch_configmaps()
        except KeyboardInterrupt:
            logger.info("Shutting down reconciler")
        except Exception as e:
            logger.error(f"Reconciler error: {e}")
            import traceback
            traceback.print_exc()
            sys.exit(1)


if __name__ == "__main__":
    reconciler = ModelRegistryReconciler()
    reconciler.run()

