#!/usr/bin/env bash
# 01-patch-aiq.sh — v2 (multi-store + OpenShift OAuth)
# ──────────────────────────────────────────────────────────────────────────────
# Patches the NVIDIA AI-Q repository for IBM Fusion CAS integration.
# Source of truth: IBM Community blog "Connecting IBM Fusion CAS to NVIDIA AI-Q
#                  on OpenShift - v2"
#
# What it does:
#   1. Pins the aiq repo to AIQ_COMMIT (reproducible builds).
#   2. Copies backend src files from this repo's src/    (Part 1, Steps 2-3).
#   3. Copies openshift-oidc.ts frontend provider        (Part 1, Step 4).
#   4. Patches pyproject.toml using Python/tomllib        (Part 2).
#   5. Patches register.py — 4 additions incl. v2 _active_data_sources path  (Part 2).
#   6. Patches providers/index.ts — swap disabled → OpenShift provider        (Part 2).
#   7. Patches config.ts — two JWT callback fixes                             (Part 2).
#   8. Copies configs/config_web_frag.yml template as-is (no substitution)   (Part 3).
#   9. Patches deploy/helm/deployment-k8s/values.yaml                        (Part 2).
#  10. Copies fusion-config-override.yaml into the aiq repo                   (Part 5).
#  11. Runs `uv lock`.
#
# Usage:
#   source aiq-fusion.env
#   ./scripts/01-patch-aiq.sh
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[01-patch]${NC} $*"; }
success() { echo -e "${GREEN}[01-patch]${NC} ✓ $*"; }
warn()    { echo -e "${YELLOW}[01-patch]${NC} ⚠ $*"; }
die()     { echo -e "${RED}[01-patch]${NC} ✗ $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"   # fusion-cas-aiq/

# ── Python dependency bootstrap ──────────────────────────────────────────────
# Use a private venv so pip install works on Homebrew/PEP-668 Pythons
# (macOS externally-managed environments block system-wide pip installs).
VENV_DIR="${REPO_ROOT}/.patch-venv"
if [[ ! -x "${VENV_DIR}/bin/python" ]]; then
    info "Creating patch venv at ${VENV_DIR}"
    python3 -m venv "${VENV_DIR}"
fi
PYTHON="${VENV_DIR}/bin/python"

info "Checking Python patching dependencies"
PKGS=(tomli_w "ruamel.yaml")
# tomllib is stdlib ≥3.11; only need tomli on older Pythons
if "${PYTHON}" -c "import sys; sys.exit(0 if sys.version_info >= (3,11) else 1)"; then
    :
else
    PKGS+=(tomli)
fi
"${VENV_DIR}/bin/pip" install --quiet --disable-pip-version-check "${PKGS[@]}"
success "Python patching dependencies ready"

# ── Required env vars ────────────────────────────────────────────────────────
: "${AIQ_REPO_DIR:?AIQ_REPO_DIR must be set}"
: "${AIQ_COMMIT:?AIQ_COMMIT must be set}"

AIQ_REPO_DIR="$(realpath "${AIQ_REPO_DIR}")"

# src/ lives alongside this script: fusion-cas-aiq/src/
# No STORAGE_FUSION_REPO_DIR needed — we are already running from this repo.
SRC_DIR="${REPO_ROOT}/src"

[[ -d "${AIQ_REPO_DIR}/.git" ]]         || die "AIQ_REPO_DIR is not a git repo: ${AIQ_REPO_DIR}"
[[ -f "${SRC_DIR}/adapter.py" ]]        || die "adapter.py not found in ${SRC_DIR}"
[[ -f "${SRC_DIR}/__init__.py" ]]       || die "__init__.py not found in ${SRC_DIR}"
[[ -f "${SRC_DIR}/openshift-oidc.ts" ]] || die "openshift-oidc.ts not found in ${SRC_DIR}"

# ── Step 0: pin commit ────────────────────────────────────────────────────────
info "Pinning aiq repo to commit: ${AIQ_COMMIT}"
cd "${AIQ_REPO_DIR}"

PINNED_SHA=$(git rev-parse "${AIQ_COMMIT}")
CURRENT_SHA=$(git rev-parse HEAD)
if [[ "${CURRENT_SHA}" == "${PINNED_SHA}" ]]; then
    success "Already at ${PINNED_SHA:0:12}"
else
    git checkout "${PINNED_SHA}"
    success "Checked out ${PINNED_SHA:0:12}"
fi

# Sanity-check key source files exist at this commit
for f in \
    "sources/knowledge_layer/pyproject.toml" \
    "sources/knowledge_layer/src/register.py" \
    "configs/config_web_frag.yml" \
    "deploy/helm/deployment-k8s/values.yaml" \
    "frontends/ui/src/adapters/auth/providers/index.ts" \
    "frontends/ui/src/adapters/auth/config.ts"; do
    [[ -f "${f}" ]] || die "${f} not found — wrong AIQ_COMMIT?"
done

# ── Part 1 Step 2-3: copy backend source files ────────────────────────────────
info "Copying fusion_cas backend package files (Part 1 Steps 2-3)"
mkdir -p sources/knowledge_layer/src/fusion_cas
cp "${SRC_DIR}/__init__.py"   sources/knowledge_layer/src/fusion_cas/__init__.py
cp "${SRC_DIR}/adapter.py"    sources/knowledge_layer/src/fusion_cas/adapter.py
success "Copied __init__.py and adapter.py → adapter.py"

# ── Part 1 Step 4: copy frontend OpenShift OIDC provider ─────────────────────
info "Copying openshift-oidc.ts (Part 1 Step 4)"
mkdir -p frontends/ui/src/adapters/auth/providers
cp "${SRC_DIR}/openshift-oidc.ts" \
   frontends/ui/src/adapters/auth/providers/openshift-oidc.ts
success "Copied openshift-oidc.ts"

# ── Part 2: patch pyproject.toml ─────────────────────────────────────────────
info "Patching pyproject.toml (Part 2)"
"${PYTHON}" - <<'PYEOF'
import sys, pathlib

try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        sys.exit("ERROR: tomllib (Python 3.11+) or tomli required. pip install tomli")

try:
    import tomli_w
except ImportError:
    sys.exit("ERROR: tomli_w required. pip install tomli_w")

path = pathlib.Path("sources/knowledge_layer/pyproject.toml")
data = tomllib.loads(path.read_text())

# 1. Add package
pkgs = data.setdefault("tool", {}).setdefault("setuptools", {}).setdefault("packages", [])
entry = "knowledge_layer.fusion_cas"
if entry not in pkgs:
    pkgs.append(entry)
    print(f"  + Added '{entry}' to [tool.setuptools] packages")
else:
    print(f"  ~ '{entry}' already present")

# 2. Add optional-dep group
opt_deps = data.setdefault("project", {}).setdefault("optional-dependencies", {})
if "fusion_cas" not in opt_deps:
    opt_deps["fusion_cas"] = ["requests>=2.28.0", "urllib3>=2.7.0,<3"]
    print("  + Added fusion_cas optional-dep group")
else:
    print("  ~ fusion_cas optional-dep group already present")

# 3. Update 'all' group
all_group = opt_deps.get("all", [])
new_all = "knowledge-layer[llamaindex,foundational_rag,opensearch,azure_ai_search,fusion_cas]"
old_all = "knowledge-layer[llamaindex,foundational_rag,opensearch,azure_ai_search]"
if new_all not in str(all_group):
    updated = [new_all if entry == old_all else entry for entry in all_group]
    if updated == all_group:
        updated.append(new_all)
    opt_deps["all"] = updated
    print("  + Updated 'all' group")
else:
    print("  ~ 'all' group already updated")

path.write_bytes(tomli_w.dumps(data).encode())
print("  ✓ pyproject.toml written")
PYEOF
success "pyproject.toml patched"

# ── Part 2: patch register.py (4 additions) ──────────────────────────────────
info "Patching register.py (Part 2, 4 additions)"
"${PYTHON}" - <<'PYEOF'
import pathlib, sys

path = pathlib.Path("sources/knowledge_layer/src/register.py")
src  = path.read_text()
orig = src

# ─ Addition 1: eager import + _active_data_sources ContextVar ───────────────
# Both must be injected together — search_nat (Addition 4) calls
# _active_data_sources.get() at runtime.  If only the import guard lands but
# not the ContextVar declaration, the deployed image raises:
#   NameError: name '_active_data_sources' is not defined
LOGGER_LINE = "logger = logging.getLogger(__name__)"
EAGER_IMPORT = (
    "from contextvars import ContextVar\n\n"
    "try:\n"
    "    import knowledge_layer.fusion_cas  # noqa: F401\n"
    "except ImportError:\n"
    "    pass\n\n"
    "# ContextVar set by the agent layer just before the graph is invoked.\n"
    "# Holds the list of data-source IDs the user enabled in the AI-Q UI\n"
    "# (e.g. [\"fusion_cas_1\", \"fusion_cas_2\"]).  search_nat reads this to\n"
    "# tell FusionCASRetriever which stores to query in parallel.\n"
    "# Value is None when not set — all configured stores are searched.\n"
    "_active_data_sources: ContextVar[list[str] | None] = ContextVar(\n"
    "    \"knowledge_retrieval_data_sources\", default=None\n"
    ")\n\n"
)
# Guard on the ContextVar *declaration* specifically — not just any use of the
# name.  The .get() call from Addition 4 also contains "_active_data_sources",
# so a broader check would falsely skip this block when Addition 4 already landed
# but the declaration was never injected (the exact NameError scenario).
if "ContextVar(" not in src or "_active_data_sources: ContextVar" not in src:
    if LOGGER_LINE not in src:
        sys.exit(f"ERROR: '{LOGGER_LINE}' not found in register.py — check AIQ_COMMIT")
    src = src.replace(LOGGER_LINE, EAGER_IMPORT + LOGGER_LINE, 1)
    print("  + Addition 1: eager import + _active_data_sources ContextVar inserted")
else:
    print("  ~ Addition 1: already present")

# ─ Addition 2: extend BackendType ────────────────────────────────────────────
OLD_BT = 'BackendType = Literal["llamaindex", "foundational_rag", "opensearch", "azure_ai_search"]'
NEW_BT = (
    'BackendType = Literal[\n'
    '    "llamaindex",\n'
    '    "foundational_rag",\n'
    '    "opensearch",\n'
    '    "azure_ai_search",\n'
    '    "nat_retriever",\n'
    ']'
)
if '"nat_retriever"' not in src:
    if OLD_BT not in src:
        sys.exit("ERROR: BackendType literal not found — check AIQ_COMMIT")
    src = src.replace(OLD_BT, NEW_BT, 1)
    print("  + Addition 2: nat_retriever added to BackendType")
else:
    print("  ~ Addition 2: already present")

# ─ Addition 3a: field in KnowledgeRetrievalConfig ────────────────────────────
FIELD_CODE = (
    "    fusion_cas_retriever: str | None = Field(\n"
    "        default=None,\n"
    '        description="Name of the retriever entry in the retrievers: section.",\n'
    "    )\n"
)
if "fusion_cas_retriever" not in src:
    marker = "    @model_validator"
    if marker not in src:
        sys.exit("ERROR: @model_validator not found — check AIQ_COMMIT")
    src = src.replace(marker, FIELD_CODE + marker, 1)
    print("  + Addition 3a: fusion_cas_retriever field added")
else:
    print("  ~ Addition 3a: already present")

# ─ Addition 3b: validator ─────────────────────────────────────────────────────
VALIDATOR_CODE = (
    '        elif backend == "nat_retriever":\n'
    "            if not self.fusion_cas_retriever:\n"
    "                raise ValueError(\n"
    '                    "backend=\'nat_retriever\' requires fusion_cas_retriever to be set. "\n'
    '                    "Add \'fusion_cas_retriever: <retriever-name>\' to the config."\n'
    "                )\n"
)
if 'backend == "nat_retriever"' not in src:
    marker = "        return self"
    if marker not in src:
        sys.exit("ERROR: 'return self' not found in validate_backend_config — check AIQ_COMMIT")
    src = src.replace(marker, VALIDATOR_CODE + marker, 1)
    print("  + Addition 3b: nat_retriever validator added")
else:
    print("  ~ Addition 3b: already present")

# ─ Addition 4: nat_retriever execution path (v2 — _active_data_sources) ──────
NAT_PATH = '''\
    if config.backend == "nat_retriever":
        nat_retriever = await _builder.get_retriever(config.fusion_cas_retriever)
        logger.info(
            "Knowledge retrieval initialized: backend=nat_retriever, retriever=%s, top_k=%d",
            config.fusion_cas_retriever,
            top_k,
        )

        async def search_nat(query: str) -> str:
            """Search for documents relevant to the query.

            Args:
                query (str): Natural language query.

            Returns:
                str: Formatted excerpts with citations.
            """
            logger.info("Knowledge search (nat_retriever): query=\'%s...\'", query[:100])
            try:
                from nat.retriever.models import RetrieverOutput
                from aiq_agent.knowledge.schema import Chunk, ContentType, RetrievalResult

                # v2: pass UI-selected source IDs so the retriever fans out
                # only to the stores the user enabled in the Data Sources panel.
                active_sources = _active_data_sources.get()
                search_kwargs: dict = {"query": query, "top_k": top_k}
                if active_sources is not None:
                    search_kwargs["enabled_source_ids"] = active_sources

                raw: RetrieverOutput = await nat_retriever.search(**search_kwargs)
                chunks = []
                for i, doc in enumerate(raw.results):
                    meta = doc.metadata or {}
                    filename = meta.get("filename", "unknown")
                    page_number = meta.get("page_number")
                    citation = f"{filename}, p.{page_number}" if page_number else filename
                    chunks.append(
                        Chunk(
                            chunk_id=str(meta.get("file_id") or f"nat-{i}"),
                            content=doc.page_content or "",
                            file_name=filename,
                            page_number=page_number,
                            score=float(meta.get("score", 0.0)),
                            content_type=ContentType.TEXT,
                            display_citation=citation,
                        )
                    )
                result = RetrievalResult(
                    success=True, chunks=chunks, query=query, backend="nat_retriever"
                )
                formatted = _format_results(result, query)
                logger.info("Knowledge search (nat_retriever) returned %d chunks", len(chunks))
                return formatted
            except Exception as e:
                logger.error("Knowledge search (nat_retriever) failed: %s", e)
                return f"Error searching knowledge base: {e}"

        yield FunctionInfo.from_fn(
            search_nat,
            description=(
                "Search the knowledge base for relevant documents. "
                "Use this to find information from ingested PDFs, documents, and other files. "
                f"Returns up to {top_k} relevant excerpts with citations."
            ),
        )
        return   # skip all other backend code below

'''
if "search_nat" not in src:
    # Strategy:
    #   1. Remove the upstream configure_summary_db block (it runs before nat_retriever
    #      and crashes when the summary DB path doesn't exist in the pod).
    #   2. Insert: top_k + nat_retriever early-return block BEFORE _get_retriever().
    #   3. Re-insert configure_summary_db AFTER the nat_retriever early-return so it
    #      is only reached by non-nat_retriever backends that actually need it.

    # Step 1: strip the upstream configure_summary_db call + its import
    SUMMARY_BLOCK = (
        "    # Initialize summary DB with configured URL\n"
        "    from aiq_agent.knowledge.factory import configure_summary_db\n"
        "\n"
        "    configure_summary_db(config.summary_db)\n"
        "\n"
    )
    SUMMARY_BLOCK_ALT = (
        "    from aiq_agent.knowledge.factory import configure_summary_db\n"
        "\n"
        "    configure_summary_db(config.summary_db)\n"
        "\n"
    )
    if SUMMARY_BLOCK in src:
        src = src.replace(SUMMARY_BLOCK, "", 1)
        print("  + Removed upstream configure_summary_db block (with comment)")
    elif SUMMARY_BLOCK_ALT in src:
        src = src.replace(SUMMARY_BLOCK_ALT, "", 1)
        print("  + Removed upstream configure_summary_db block (no comment)")
    else:
        sys.exit("ERROR: configure_summary_db block not found — check AIQ_COMMIT")

    # Step 2: insert top_k + nat_retriever path before _get_retriever()
    marker = "    retriever = _get_retriever(config)"
    if marker not in src:
        sys.exit("ERROR: '_get_retriever(config)' not found — check AIQ_COMMIT")
    # nat_retriever block ends with early return, so configure_summary_db (step 3)
    # goes right before the existing _get_retriever line.
    SUMMARY_AFTER = (
        "\n    # Initialize summary DB with configured URL\n"
        "    from aiq_agent.knowledge.factory import configure_summary_db\n"
        "\n"
        "    configure_summary_db(config.summary_db)\n\n"
    )
    insert = "    top_k = config.top_k\n\n" + NAT_PATH + SUMMARY_AFTER
    src = src.replace(marker, insert + marker, 1)
    # Remove the now-duplicate top_k = config.top_k that sits after _get_retriever()
    DUPE = (
        "    retriever = _get_retriever(config)\n\n"
        "    _initialize_ingestor(config, summary_llm_obj)\n\n"
        "    collection = config.collection_name\n"
        "    top_k = config.top_k\n"
    )
    DUPE_CLEAN = (
        "    retriever = _get_retriever(config)\n\n"
        "    _initialize_ingestor(config, summary_llm_obj)\n\n"
        "    collection = config.collection_name\n"
    )
    if DUPE in src:
        src = src.replace(DUPE, DUPE_CLEAN, 1)
        print("  + Removed duplicate top_k = config.top_k after _get_retriever")
    print("  + Addition 4: nat_retriever execution path added (v2)")
else:
    print("  ~ Addition 4: already present")

if src != orig:
    path.write_text(src)
    print("  ✓ register.py written")
else:
    print("  ~ register.py unchanged")

# ── Post-patch verification (fail loudly if any addition is missing) ──────────
checks = {
    "Addition 1 (eager import)":             "import knowledge_layer.fusion_cas",
    "Addition 1 (_active_data_sources var)": "_active_data_sources",
    "Addition 2 (BackendType)":              '"nat_retriever"',
    "Addition 3a (fusion_cas_retriever field)": "fusion_cas_retriever",
    "Addition 3b (nat_retriever validator)":    'backend == "nat_retriever"',
    "Addition 4 (search_nat execution path)":   "search_nat",
}
final = pathlib.Path("sources/knowledge_layer/src/register.py").read_text()
failed = [name for name, needle in checks.items() if needle not in final]
if failed:
    print("ERROR: The following patches were NOT applied to register.py:")
    for name in failed:
        print(f"  ✗ {name}")
    print("Check AIQ_COMMIT — the upstream source lines may have changed.")
    sys.exit(1)

# Verify ordering: configure_summary_db must come AFTER search_nat's return,
# not before it — the old ordering caused SQLite crashes at pod startup.
pos_search_nat = final.index("search_nat")
pos_summary_db = final.index("configure_summary_db(config.summary_db)")
if pos_summary_db < pos_search_nat:
    print("ERROR: configure_summary_db appears BEFORE search_nat — ordering is wrong.")
    print("  nat_retriever early-return will never fire before the summary DB is touched.")
    sys.exit(1)
print("  ✓ All 4 register.py additions verified in final file")
print("  ✓ configure_summary_db correctly placed after nat_retriever early-return")
PYEOF
success "register.py patched and verified"

# ── Part 2: patch providers/index.ts ─────────────────────────────────────────
info "Patching frontends/ui/src/adapters/auth/providers/index.ts (Part 2)"
"${PYTHON}" - <<'PYEOF'
import pathlib, sys

path = pathlib.Path("frontends/ui/src/adapters/auth/providers/index.ts")
src  = path.read_text()
orig = src

if "openshift-oidc" not in src:
    # Replace the entire disabled-auth export with the OpenShift one
    old = (
        "import type { AuthProviderConfig } from './types'\n"
        "\n"
        "export const getAuthProviderConfig = (): AuthProviderConfig => ({\n"
        "  provider: null,\n"
        "  providerId: 'disabled-auth',\n"
        "  refreshToken: async () => {\n"
        "    throw new Error('No auth provider configured')\n"
        "  },\n"
        "})"
    )
    new = (
        "import type { AuthProviderConfig } from './types'\n"
        "import { getOpenShiftProviderConfig } from './openshift-oidc'\n"
        "\n"
        "export const getAuthProviderConfig = (): AuthProviderConfig =>\n"
        "  getOpenShiftProviderConfig()"
    )
    if old in src:
        src = src.replace(old, new, 1)
        print("  + Swapped disabled-auth → OpenShift provider")
    else:
        print("  ⚠ Could not find exact disabled-auth block — patching by append")
        src = new
else:
    print("  ~ openshift-oidc import already present")

if src != orig:
    path.write_text(src)
    print("  ✓ providers/index.ts written")
else:
    print("  ~ providers/index.ts unchanged")
PYEOF
success "providers/index.ts patched"

# ── Part 2: patch config.ts (two JWT callback fixes) ─────────────────────────
info "Patching frontends/ui/src/adapters/auth/config.ts (Part 2)"
"${PYTHON}" - <<'PYEOF'
import pathlib, sys

path = pathlib.Path("frontends/ui/src/adapters/auth/config.ts")
src  = path.read_text()
orig = src

# Fix 1: id_token fallback
if "account.id_token ?? account.access_token" not in src:
    if "idToken: account.id_token," in src:
        src = src.replace(
            "idToken: account.id_token,",
            "idToken: account.id_token ?? account.access_token,",
            1,
        )
        print("  + Fix 1: id_token ?? access_token fallback applied")
    else:
        print("  ⚠ Fix 1: 'idToken: account.id_token,' not found — skipping")
else:
    print("  ~ Fix 1: already applied")

# Fix 2: expires_at fallback
if "account.expires_at ??" not in src:
    if "expiresAt: account.expires_at," in src:
        src = src.replace(
            "expiresAt: account.expires_at,",
            "expiresAt:\n"
            "          account.expires_at ??\n"
            "          Math.floor(Date.now() / 1000) + SESSION_MAX_AGE_SECONDS,",
            1,
        )
        print("  + Fix 2: expires_at ?? SESSION_MAX_AGE_SECONDS fallback applied")
    else:
        print("  ⚠ Fix 2: 'expiresAt: account.expires_at,' not found — skipping")
else:
    print("  ~ Fix 2: already applied")

if src != orig:
    path.write_text(src)
    print("  ✓ config.ts written")
else:
    print("  ~ config.ts unchanged")
PYEOF
success "config.ts patched"

# ── Part 3: copy config_web_frag.yml template as-is ─────────────────────────
# No substitution at copy time — all ${...} references are resolved at pod
# startup from Kubernetes Secrets/env injected by Helm secretEnv/env blocks.
# The file is gitignored in the aiq repo and deployed as a ConfigMap by
# 03-setup-secrets-and-token.sh, which mounts it into the backend pod.
info "Copying configs/config_web_frag.yml (no substitution — all values stay as env refs)"

TEMPLATE="${REPO_ROOT}/templates/config_web_frag.yml.template"
[[ -f "${TEMPLATE}" ]] || die "Template not found: ${TEMPLATE}"

cp "${TEMPLATE}" configs/config_web_frag.yml
success "configs/config_web_frag.yml copied (all values remain as \${ENV_VAR} references)"

# ── Part 2: patch values.yaml ─────────────────────────────────────────────────
info "Patching deploy/helm/deployment-k8s/values.yaml"
"${PYTHON}" - <<'PYEOF'
import pathlib, sys

try:
    from ruamel.yaml import YAML
except ImportError:
    sys.exit("ERROR: ruamel.yaml required. pip install ruamel.yaml")

yaml = YAML()
yaml.preserve_quotes = True
path = pathlib.Path("deploy/helm/deployment-k8s/values.yaml")
data = yaml.load(path)

backend = data.get("aiq", {}).get("apps", {}).get("backend", {})
env = backend.setdefault("env", {})

if env.get("CONFIG_FILE") != "configs/config_web_frag.yml":
    env["CONFIG_FILE"] = "configs/config_web_frag.yml"
    print("  + Set CONFIG_FILE")
else:
    print("  ~ CONFIG_FILE already set")

# secretEnv keys tell the Helm chart which keys to pull from the aiq-credentials
# Kubernetes Secret and expose as pod env vars. Only key names go here — no values.
secret_env = backend.setdefault("secretEnv", {})
for secret_key in (
    "FUSION_CAS_TOKEN", "NVIDIA_API_KEY", "TAVILY_API_KEY",
    # DB credentials — the upstream values.yaml builds full Postgres URLs from
    # $(DB_USER_NAME):$(DB_USER_PASSWORD) env interpolation; both must be present
    # as secret-backed env vars so the interpolation resolves at pod startup.
    "DB_USER_NAME", "DB_USER_PASSWORD",
):
    if secret_key not in secret_env:
        secret_env[secret_key] = secret_key
        print(f"  + Added secretEnv.{secret_key}")
    else:
        print(f"  ~ secretEnv.{secret_key} already present")

# Non-secret env vars (FUSION_CAS_URL, FUSION_VECTOR_STORE_*, FUSION_VERIFY_SSL,
# CLUSTER_DOMAIN-derived values) are NOT patched into values.yaml.
# They are passed at deploy time via fusion-config-override.yaml secretEnv so no
# cluster-specific data is ever written into a committed file.
print("  ~ Non-secret env vars sourced from fusion-config-override.yaml secretEnv")

with open(path, "w") as f:
    yaml.dump(data, f)
print("  ✓ values.yaml written")
PYEOF
success "values.yaml patched"

# ── Part 2b: patch chat_researcher/register.py — _active_data_sources.set() ─────
# This is the "KNOWN GAP" from patch 0001: the agent layer must set the ContextVar
# before ainvoke() so the FusionCAS retriever knows which stores the user enabled.
info "Patching src/aiq_agent/agents/chat_researcher/register.py (Part 2b - ContextVar set)"
"${PYTHON}" - <<'PYEOF'
import pathlib, sys

path = pathlib.Path("src/aiq_agent/agents/chat_researcher/register.py")
src  = path.read_text()
orig = src

# The block to insert before state creation (12-space indent level)
IMPORT_BLOCK = (
    "        # Propagate the UI-selected data-source IDs to the knowledge_retrieval\n"
    "        # function via a ContextVar.  This lets the FusionCAS retriever fan out\n"
    "        # only to the enabled stores in parallel in a single tool call, rather\n"
    "        # than forcing the LLM to call each per-store tool one by one.\n"
    "        try:\n"
    "            from knowledge_layer.register import _active_data_sources as _kr_data_sources  # noqa: PLC0415\n"
    "\n"
    "            _kr_token = _kr_data_sources.set(data_sources)\n"
    "            _kr_set = True\n"
    "        except ImportError:\n"
    "            _kr_token = None\n"
    "            _kr_set = False\n"
    "\n"
)

# Find where state is created (after available_documents logic)
STATE_MARKER = "            state = ChatResearcherState("
if STATE_MARKER in src and "_active_data_sources" not in src:
    # Insert the ContextVar set block right before state creation
    src = src.replace(STATE_MARKER, IMPORT_BLOCK + STATE_MARKER, 1)
    print("  + Added _active_data_sources.set() before state creation")
else:
    print("  ~ _active_data_sources.set() already present or marker not found")

# Find the try/finally block around agent.run and add the reset
TRY_MARKER = "            result = await agent.run(state, thread_id=nat_context_conversation_id)"
FINALLY_MARKER = "        finally:"
if TRY_MARKER in src and FINALLY_MARKER in src and "_kr_data_sources.reset" not in src:
    # Find the finally block and add the reset before reset_session_registry
    FINALLY_BLOCK = "        finally:\n            reset_session_registry(token)"
    NEW_FINALLY = (
        "        finally:\n"
        "            reset_session_registry(token)\n"
        "            if _kr_set and _kr_token is not None:\n"
        "                _kr_data_sources.reset(_kr_token)"
    )
    if FINALLY_BLOCK in src:
        src = src.replace(FINALLY_BLOCK, NEW_FINALLY, 1)
        print("  + Added _active_data_sources.reset() in finally block")
    else:
        print("  ⚠ Could not find exact finally block pattern")
else:
    print("  ~ _active_data_sources.reset() already present or markers not found")

if src != orig:
    path.write_text(src)
    print("  ✓ chat_researcher/register.py written")
else:
    print("  ~ chat_researcher/register.py unchanged")

# Verify the patch was applied correctly
final = pathlib.Path("src/aiq_agent/agents/chat_researcher/register.py").read_text()
checks = {
    "_active_data_sources.set": "_kr_data_sources.set(data_sources)",
    "_active_data_sources.reset": "_kr_data_sources.reset(_kr_token)",
    "import _active_data_sources": "from knowledge_layer.register import _active_data_sources",
}
failed = [name for name, needle in checks.items() if needle not in final]
if failed:
    print("ERROR: The following patches were NOT applied to chat_researcher/register.py:")
    for name in failed:
        print(f"  ✗ {name}")
    sys.exit(1)
print("  ✓ All chat_researcher/register.py patches verified")
PYEOF
success "chat_researcher/register.py patched"

# ── Part 5: copy fusion-config-override.yaml as-is ───────────────────────────
# No substitution — CLUSTER_DOMAIN is passed via --set flags in 04-deploy-helm.sh.
# The <cluster-domain> placeholder stays in the file; it is NOT used at runtime
# because 04-deploy-helm.sh overrides all host/URL values with --set.
info "Copying fusion-config-override.yaml (no substitution — CLUSTER_DOMAIN passed via helm --set)"
OVERRIDE_SRC="${REPO_ROOT}/templates/fusion-config-override.yaml"
[[ -f "${OVERRIDE_SRC}" ]] || die "fusion-config-override.yaml not found: ${OVERRIDE_SRC}"
cp "${OVERRIDE_SRC}" deploy/helm/deployment-k8s/fusion-config-override.yaml
success "fusion-config-override.yaml copied"

# ── Run uv lock ───────────────────────────────────────────────────────────────
# uv lock must run from the knowledge_layer package root where pyproject.toml
# and uv.lock live — NOT from the repo root.
info "Running uv lock (in sources/knowledge_layer/)"
if command -v uv &>/dev/null; then
    (cd "${AIQ_REPO_DIR}/sources/knowledge_layer" && uv lock)
    success "uv.lock updated"
else
    warn "uv not found — run 'cd \${AIQ_REPO_DIR}/sources/knowledge_layer && uv lock' manually before building the image"
fi

# ── Patches applied — user must review, commit, and push manually ────────────
AIQ_GIT_REF="${AIQ_GIT_REF:-fusion-cas}"

# configs/config_web_frag.yml is gitignored in the aiq repo — it contains
# ${ENV_VAR} references that must not be committed even though no values are
# baked in, to avoid confusion. It is deployed as a Kubernetes ConfigMap.
# fusion-config-override.yaml is now safe to commit (no hardcoded values).
GITIGNORE="${AIQ_REPO_DIR}/.gitignore"
if ! grep -qxF "configs/config_web_frag.yml" "${GITIGNORE}" 2>/dev/null; then
    echo "configs/config_web_frag.yml" >> "${GITIGNORE}"
    info "Added 'configs/config_web_frag.yml' to aiq repo .gitignore"
fi

echo ""
success "All patches applied to ${AIQ_REPO_DIR}"

# ── Deploy secrets reminder ───────────────────────────────────────────────────
# configs/config_web_frag.yml is gitignored — deployed as Kubernetes ConfigMap
# by 03-setup-secrets-and-token.sh. All ${...} refs in it are resolved at pod
# startup from the Kubernetes Secret (aiq-credentials) and Helm env --set values.
# fusion-config-override.yaml has no hardcoded values and is safe to commit.
echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW} Secrets and config are NOT in the git commit above.${NC}"
echo -e "${YELLOW} Run 03-setup-secrets-and-token.sh to deploy them to OpenShift.${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${CYAN} The following file is rendered locally and is gitignored:${NC}"
echo "   ${AIQ_REPO_DIR}/configs/config_web_frag.yml"
echo -e "${CYAN} (fusion-config-override.yaml has no secrets and is safe to commit)${NC}"
echo ""
echo -e "${CYAN} 03-setup-secrets-and-token.sh will:${NC}"
echo "   • Create Kubernetes Secret  aiq-credentials  (FUSION_CAS_TOKEN, NGC_API_KEY, ...)"
echo "   • Create Kubernetes ConfigMap  aiq-config-frag  (config_web_frag.yml)"
echo "   • Create OpenShift OAuthClient and OAuth CA ConfigMap"
echo ""
echo -e "${YELLOW}See fusion-cas-aiq/README.md for full deploy instructions.${NC}"
echo ""
echo -e "${CYAN}Next steps:${NC}"
echo "  1. Review patches: cd ${AIQ_REPO_DIR} && git diff"
echo "  2. Create branch:  git checkout -b ${AIQ_GIT_REF}"
echo "  3. Commit:         git add -p && git commit"
echo "  4. Push:           git push origin ${AIQ_GIT_REF}"
echo "  5. Build image:    ./scripts/02-build-push-image.sh"
echo "  6. Deploy secrets: ./scripts/03-setup-secrets-and-token.sh"
echo "  7. Deploy Helm:    ./scripts/04-deploy-helm.sh"
