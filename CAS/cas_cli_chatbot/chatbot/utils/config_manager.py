"""
Configuration Manager for interactive OC login setup
Handles config file creation and credential prompts
"""

import os
import yaml
from pathlib import Path
from typing import Dict, Any, Optional
from rich.console import Console
from rich.prompt import Prompt, Confirm
from getpass import getpass

console = Console()


class ConfigManager:
    """Manages configuration file creation and credential setup"""

    def __init__(self, config_path: Path):
        self.config_path = Path(config_path)
        self.sample_path = self.config_path.parent / "config.yaml.sample"

    def config_exists(self) -> bool:
        """Check if config file exists"""
        return self.config_path.exists()

    def has_oc_credentials(self, config: Dict[str, Any]) -> bool:
        """Check if config has OC credentials configured"""
        username = config.get('oc_username', '')
        password = config.get('oc_password', '')
        console_url = config.get('console_url', '')

        # Check if credentials are placeholders or empty
        placeholders = [
            '<your-ocp-username>', '<your-ocp-password>', '<your-cluster>',
            'changeme', ''
        ]

        has_valid_username = username and username not in placeholders
        has_valid_password = password and password not in placeholders
        has_valid_url = console_url and '<your-cluster>' not in console_url

        return has_valid_username and has_valid_password and has_valid_url

    def prompt_for_credentials(self) -> Dict[str, str]:
        """Interactively prompt user for OC credentials and CAS configuration"""
        console.print("\n[bold cyan]OpenShift Configuration Setup[/]")
        console.print("Please provide your OpenShift cluster credentials:\n")

        console_url = Prompt.ask(
            "[yellow]Console URL[/] [cyan](Ex: https://console-openshift-console.apps.<your-cluster>.openshiftapps.com)[/]"
        )

        username = Prompt.ask("[yellow]OC Username[/]")

        # Use getpass for secure password input
        console.print("[yellow]OC Password:[/] ", end="")
        password = getpass("")

        # Get CAS API URL
        console.print("\n[bold cyan]CAS API Configuration[/]")

        # Initialize namespace with default value
        namespace = "ibm-cas"

        # Try to auto-generate CAS URL
        cas_url = None
        try:
            cluster = self._extract_cluster_from_console_url(console_url)
            cas_url = f"https://console-ibm-spectrum-fusion-ns.apps.{cluster}.openshiftapps.com/cas/api/v1"
            console.print(
                f"\n[green]✓ Auto-generated CAS URL:[/] [cyan]{cas_url}[/]")

            use_generated = Confirm.ask("[yellow]Use this CAS URL?[/]",
                                        default=True)

            if not use_generated:
                cas_url = Prompt.ask("[yellow]Enter CAS URL manually[/]")
                namespace: str = Prompt.ask("[yellow]Enter CAS Namespace[/]")
        except ValueError as e:
            console.print(f"[yellow]⚠ Could not auto-generate CAS URL: {e}[/]")
            cas_url = Prompt.ask("[yellow]CAS URL[/]")

        return {
            'console_url': console_url,
            'oc_username': username,
            'oc_password': password,
            'cas_url': cas_url,
            'cas_namespace': namespace
        }

    def create_config_from_sample(
            self, credentials: Dict[str, str]) -> Dict[str, Any]:
        """Create config from sample file with provided credentials"""
        if not self.sample_path.exists():
            raise FileNotFoundError(
                f"Sample config not found: {self.sample_path}")

        # Load sample config
        with open(self.sample_path, 'r') as f:
            config = yaml.safe_load(f)

        # Update with credentials
        config['console_url'] = credentials['console_url']
        config['oc_username'] = credentials['oc_username']
        config['oc_password'] = credentials['oc_password']
        config['cas_url'] = credentials['cas_url']
        config['cas_namespace'] = credentials['cas_namespace']

        return config

    def save_config(self, config: Dict[str, Any], backup: bool = True):
        """Save configuration to file"""
        if backup and self.config_path.exists():
            backup_path = self.config_path.with_suffix('.yaml.bak')
            import shutil
            shutil.copy2(self.config_path, backup_path)
            console.print(f"[dim]Created backup: {backup_path}[/]")

        with open(self.config_path, 'w') as f:
            yaml.safe_dump(config, f, default_flow_style=False, sort_keys=False)

        console.print(
            f"[bold green]✓ Configuration saved to {self.config_path}[/]")

    def setup_interactive(self) -> Dict[str, Any]:
        """
        Interactive setup flow:
        1. Check if config exists
        2. If exists, check if credentials are configured
        3. Prompt user accordingly
        4. Create/update config file
        """
        if self.config_exists():
            # Config exists, load it
            with open(self.config_path, 'r') as f:
                config = yaml.safe_load(f)

            if self.has_oc_credentials(config):
                # Credentials already configured
                console.print(
                    "\n[bold green]✓ Configuration file found with credentials[/]"
                )
                console.print(f"  Console URL: {config.get('console_url')}")
                console.print(f"  Username: {config.get('oc_username')}")

                use_existing = Confirm.ask(
                    "\n[yellow]Use existing configuration?[/]", default=True)

                if use_existing:
                    return config
                else:
                    console.print("\n[cyan]Setting up new credentials...[/]")
                    credentials = self.prompt_for_credentials()
                    config['console_url'] = credentials['console_url']
                    config['oc_username'] = credentials['oc_username']
                    config['oc_password'] = credentials['oc_password']
                    config['cas_url'] = credentials['cas_url']
                    config['cas_namespace'] = credentials['cas_namespace']

                    self.save_config(config)
                    return config
            else:
                # Config exists but no valid credentials
                console.print(
                    "\n[yellow]⚠ Configuration file found but credentials not configured[/]"
                )
                credentials = self.prompt_for_credentials()
                config['console_url'] = credentials['console_url']
                config['oc_username'] = credentials['oc_username']
                config['oc_password'] = credentials['oc_password']
                config['cas_url'] = credentials['cas_url']
                config['cas_namespace'] = credentials['cas_namespace']

                self.save_config(config)
                return config
        else:
            # No config file exists
            console.print("\n[yellow]⚠ No configuration file found[/]")
            console.print("Creating new configuration...\n")

            credentials = self.prompt_for_credentials()
            config = self.create_config_from_sample(credentials)
            self.save_config(config, backup=False)
            return config

    def update_credentials(self,
                           config: Dict[str, Any],
                           username: Optional[str] = None,
                           password: Optional[str] = None,
                           console_url: Optional[str] = None) -> Dict[str, Any]:
        """Update specific credentials in config"""
        if username:
            config['oc_username'] = username
        if password:
            config['oc_password'] = password
        if console_url:
            config['console_url'] = console_url

        return config

    def update_default_vector_store(self, vector_store_name: str):
        """
        Update the default_vector_store in the config file
        
        Args:
            vector_store_name: Name of the vector store to set as default
        """
        if not self.config_path.exists():
            console.print("[yellow]⚠ Config file not found. Cannot update default vector store.[/]")
            return
        
        # Load current config
        with open(self.config_path, 'r') as f:
            config = yaml.safe_load(f)
        
        # Update default_vector_store
        config['default_vector_store'] = vector_store_name
        
        # Save config without backup (minor update)
        with open(self.config_path, 'w') as f:
            yaml.safe_dump(config, f, default_flow_style=False, sort_keys=False)

    def has_llm_configured(self, config: Dict[str, Any]) -> bool:
        """
        Check if config has at least one LLM provider configured
        
        Args:
            config: Configuration dictionary
            
        Returns:
            True if at least one LLM provider is properly configured
        """
        provider_sequence = config.get('llm_provider_sequence', [])
        
        if not provider_sequence:
            return False
        
        # Check each provider in sequence
        for provider in provider_sequence:
            if provider == 'openai':
                api_key = config.get('openai_api_key', '')
                # Check if it's not empty and not a placeholder
                if api_key and not api_key.startswith('${') and not api_key.startswith('sk-YOUR'):
                    return True
                    
            elif provider == 'ollama':
                host = config.get('ollama_host', '')
                # Check if it's not empty and not a placeholder
                if host and '<' not in host and host != 'http://localhost:11434':
                    return True
                    
            elif provider == 'nvidia':
                url = config.get('nvidia_llm_url', '')
                # Check if it's not empty and not a placeholder
                if url and '<' not in url:
                    return True
        
        return False

    def prompt_for_llm_setup(self) -> Dict[str, Any]:
        """
        Interactively prompt user for LLM provider configuration
        
        Returns:
            Dictionary with LLM configuration settings
        """
        console.print("\n[bold cyan]LLM Provider Setup[/]")
        console.print("Some commands use an LLM to enhance responses (e.g., 'query ask').\n")
        
        console.print("[bold]Available LLM Providers:[/]")
        console.print("  [cyan]1.[/] OpenAI (requires API key)")
        console.print("  [cyan]2.[/] Ollama (local, requires running instance)")
        console.print("  [cyan]3.[/] NVIDIA NIM (requires endpoint URL)")
        console.print("  [cyan]4.[/] Skip for now\n")
        
        choice = Prompt.ask(
            "[yellow]Select provider[/]",
            choices=["1", "2", "3", "4"],
            default="4"
        )
        
        llm_config = {}
        
        if choice == "1":
            # OpenAI setup
            console.print("\n[bold cyan]OpenAI Configuration[/]")
            api_key = Prompt.ask("[yellow]OpenAI API Key[/]")
            model = Prompt.ask(
                "[yellow]Model[/]",
                default="gpt-3.5-turbo"
            )
            
            llm_config = {
                'llm_provider_sequence': ['openai'],
                'openai_api_key': api_key,
                'openai_model': model
            }
            console.print("[green]✓ OpenAI configured[/]")
            
        elif choice == "2":
            # Ollama setup
            console.print("\n[bold cyan]Ollama Configuration[/]")
            host = Prompt.ask(
                "[yellow]Ollama Host URL[/]",
                default="http://localhost:11434"
            )
            model = Prompt.ask(
                "[yellow]Model[/]",
                default="llama3"
            )
            
            llm_config = {
                'llm_provider_sequence': ['ollama'],
                'ollama_host': host,
                'ollama_model': model
            }
            console.print("[green]✓ Ollama configured[/]")
            
        elif choice == "3":
            # NVIDIA setup
            console.print("\n[bold cyan]NVIDIA NIM Configuration[/]")
            url = Prompt.ask("[yellow]NVIDIA Endpoint URL[/]")
            model = Prompt.ask(
                "[yellow]Model[/]",
                default="meta/llama-3.2-1b-instruct"
            )
            
            llm_config = {
                'llm_provider_sequence': ['nvidia'],
                'nvidia_llm_url': url,
                'nvidia_model': model
            }
            console.print("[green]✓ NVIDIA configured[/]")
            
        else:
            console.print("[dim]Skipping LLM setup. You can configure it later using the config file.[/]")
        
        return llm_config

    def update_llm_config(self, llm_config: Dict[str, Any]):
        """
        Update LLM configuration in the config file
        
        Args:
            llm_config: Dictionary with LLM settings to update
        """
        if not llm_config:
            return
            
        if not self.config_path.exists():
            console.print("[yellow]⚠ Config file not found. Cannot update LLM configuration.[/]")
            return
        
        # Load current config
        with open(self.config_path, 'r') as f:
            config = yaml.safe_load(f)
        
        # Update LLM settings
        config.update(llm_config)
        
        # Save config
        with open(self.config_path, 'w') as f:
            yaml.safe_dump(config, f, default_flow_style=False, sort_keys=False)
        
        console.print("[bold green]✓ LLM configuration saved[/]")

    def _extract_cluster_from_console_url(self, console_url: str) -> str:
        """
        Extract cluster name from OpenShift console URL
        
        Args:
            console_url: Console URL like 'https://console-openshift-console.apps.cluster-name.openshiftapps.com'
        
        Returns:
            Cluster name (e.g., 'cluster-name')
        
        Raises:
            ValueError: If URL format is invalid
        """
        try:
            # Expected format: https://console-openshift-console.apps.<cluster>.openshiftapps.com
            if "console-openshift-console.apps." not in console_url:
                raise ValueError(
                    "Unsupported console URL format. Expected: console-openshift-console.apps.<cluster>..."
                )

            # Extract the part after "console-openshift-console.apps."
            parts = console_url.split("console-openshift-console.apps.")
            if len(parts) < 2:
                raise ValueError("Could not find cluster name in URL")

            remainder = parts[1]

            # Extract cluster name (everything before .openshiftapps.com or .com)
            if ".openshiftapps.com" in remainder:
                cluster = remainder.split(".openshiftapps.com")[0]
            elif ".com" in remainder:
                cluster = remainder.split(".com")[0]
            else:
                cluster = remainder.split(".")[0]

            if not cluster:
                raise ValueError("Cluster name is empty")

            return cluster

        except Exception as e:
            raise ValueError(f"Failed to extract cluster from console URL: {e}")
