#!/bin/bash
#
# gen-model-config.sh — build the Bob model-config for a MaaS model.
#
# Reads   ../model-as-a-service/models/config/helm/<model>.yaml
# Writes  a model-config file for `bobctl update-model-config --model-config <file>`.
#
# Topologies (both produce the same file layout; only base_url / api_key differ):
#   direct   Bob -> llm-d workload Service in-cluster (no Kuadrant, no Route)   [default]
#   gateway  Bob -> MaaS gateway (needs your gateway URL and token)
#
# Usage:
#   ./gen-model-config.sh <model-name | model-values-file> [options]
#     --topology direct|gateway     default: direct
#     --gateway-url <url>           gateway only, e.g. https://maas.apps.<domain>
#     --api-key <token>             gateway only. Default: dummy-key (direct) or a placeholder
#     --guardrail <model>           use a separate model for "security" (e.g. gpt-oss-20b).
#                                   Default: "security" is an alias of the main model.
#     --guardrail-url <url>         same, with an explicit base URL instead
#     --out <file>                  default: stdout
#     --resolve                     print shell variables for verify.sh instead of YAML
#
# Example:
#   ./gen-model-config.sh nemotron-3-ultra-550b-nvfp4 --out /tmp/model-config.yaml
#   cd ibm-bob-install-<ver> && ./bobctl update-model-config --model-config /tmp/model-config.yaml

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

command -v python3 >/dev/null || { echo "ERROR: python3 is required" >&2; exit 1; }
python3 -c 'import yaml' 2>/dev/null || { echo "ERROR: PyYAML is required (pip install pyyaml)" >&2; exit 1; }

exec python3 - "$HERE" "$@" <<'PY'
import argparse
import os
import sys

import yaml

here = sys.argv[1]
root = os.path.dirname(here)

ap = argparse.ArgumentParser(prog="gen-model-config.sh")
ap.add_argument("model")
ap.add_argument("--topology", choices=["direct", "gateway"], default="direct")
ap.add_argument("--gateway-url")
ap.add_argument("--api-key")
ap.add_argument("--guardrail")
ap.add_argument("--guardrail-url")
ap.add_argument("--out")
ap.add_argument("--resolve", action="store_true")
a = ap.parse_args(sys.argv[2:])


def load(path):
    if not os.path.isfile(path):
        sys.exit(f"ERROR: not found: {path}")
    with open(path) as f:
        return yaml.safe_load(f) or {}


# Locate the model values file
model_arg = a.model
if os.path.isfile(model_arg):
    gen_file = model_arg
else:
    model_name_clean = model_arg[:-5] if model_arg.endswith(".yaml") else model_arg
    candidates = [
        os.path.join(root, "model-as-a-service", "models", "config", "helm", f"{model_name_clean}.yaml"),
        os.path.join(root, "model-as-a-service", "models", f"{model_name_clean}.yaml"),
        os.path.join(here, "models", "config", "helm", f"{model_name_clean}.yaml"),
        os.path.join(here, "models", f"{model_name_clean}.yaml"),
    ]
    gen_file = next((c for c in candidates if os.path.isfile(c)), None)
    if not gen_file:
        sys.exit(f"ERROR: Could not find model configuration for '{model_arg}' in {candidates[0]}")

gen = load(gen_file)

name = gen.get("model", {}).get("name", "model")
ns = gen.get("model", {}).get("namespace", "deploy-models-rhoai")
inf = gen.get("inference") or {}
vllm = gen.get("vllm") or {}
args = (inf.get("args") or []) + (inf.get("extraArgs") or []) + (vllm.get("additionalArgs") or [])


def flag(prefix):
    for i, x in enumerate(args):
        if x.startswith(prefix + "="):
            return x.split("=", 1)[1]
        if x == prefix and i + 1 < len(args):
            return args[i + 1]
    return None


served = flag("--served-model-name") or name
svc, port = f"{name}-kserve-workload-svc", flag("--port") or "8000"

direct_url = f"http://{svc}.{ns}.svc.cluster.local:{port}"
if a.topology == "direct":
    base_url, api_key = direct_url, a.api_key or "dummy-key"
else:
    if not a.gateway_url:
        sys.exit("ERROR: --topology gateway needs --gateway-url")
    base_url = f"{a.gateway_url.rstrip('/')}/{ns}/{name}"
    api_key = a.api_key or "REPLACE_WITH_MAAS_TOKEN"

default_alias = "premium-ide"
aliases = ["premium-ide", "fast", "explorer", "default", "background"]

if a.resolve:
    print(f"SERVED_NAME='{served}'")
    print(f"MODEL_NAME='{name}'")
    print(f"MODEL_NAMESPACE='{ns}'")
    print(f"MODEL_SVC='{svc}'")
    print(f"MODEL_PORT='{port}'")
    print(f"MODEL_URL='{direct_url}'")
    print(f"DEFAULT_ALIAS='{default_alias}'")
    sys.exit(0)

# Determine context length from vLLM args
max_len = int(flag("--max-model-len") or vllm.get("maxModelLen") or 131072)
has_tools = bool(flag("--tool-call-parser") or "--enable-auto-tool-choice" in args)
has_reasoning = bool(flag("--reasoning-parser"))


def entry(model_name, full):
    info = {
        "exposed": True,
        "mode": "chat",
        "max_input_tokens": max_len,
        "max_output_tokens": 20000 if max_len >= 131072 else 8192,
    }
    if full:
        info["supports_function_calling"] = has_tools
        info["supports_tool_choice"] = has_tools
        info["supports_reasoning"] = has_reasoning
        info["input_cost_per_token"] = 0.0
        info["output_cost_per_token"] = 0.0
    return {
        "model_name": model_name,
        "openai_compatible": {"model": served, "base_url": base_url, "api_key": api_key},
        "model_info": info,
    }


models = [entry(served, True)] + [entry(x, False) for x in aliases]

guardrail_url = a.guardrail_url
if a.guardrail:
    gr_clean = a.guardrail[:-5] if a.guardrail.endswith(".yaml") else a.guardrail
    candidates = [
        os.path.join(root, "model-as-a-service", "models", "config", "helm", f"{gr_clean}.yaml"),
        os.path.join(root, "model-as-a-service", "models", f"{gr_clean}.yaml"),
        os.path.join(here, "models", "config", "helm", f"{gr_clean}.yaml"),
    ]
    gr_file = next((c for c in candidates if os.path.isfile(c)), None)
    if gr_file:
        gg = load(gr_file)
        ginf = gg.get("inference") or {}
        gargs = (ginf.get("args") or []) + (ginf.get("extraArgs") or [])
        gport = next((x.split("=", 1)[1] for x in gargs if x.startswith("--port=")), "8000")
        guardrail_url = (
            f"http://{gg['model']['name']}-kserve-workload-svc."
            f"{gg['model']['namespace']}.svc.cluster.local:{gport}"
        )

if not guardrail_url:
    models.append(entry("security", False))
else:
    models.append({
        "model_name": "security",
        "openai_compatible": {"model": "openai/gpt-oss-20b", "base_url": guardrail_url, "api_key": "dummy-key"},
        "model_info": {
            "exposed": False,
            "mode": "chat",
            "max_input_tokens": 4096,
            "max_output_tokens": 512,
            "provider": "openai",
            "family": "gpt-oss",
            "version": "20b",
        },
    })

doc = {
    "models": models,
    "routers": [{
        "name": "router",
        "strategy": "static",
        "static": {"default_model": default_alias},
    }],
}
header = (
    f"# Generated by gen-model-config.sh — do not edit.\n"
    f"# model={a.model} topology={a.topology}\n"
    f"# Apply: ./bobctl update-model-config --model-config <this file>\n"
)
text = header + yaml.safe_dump(doc, sort_keys=False)
if a.out:
    with open(a.out, "w") as f:
        f.write(text)
    print(f"wrote {a.out}", file=sys.stderr)
else:
    sys.stdout.write(text)
PY
