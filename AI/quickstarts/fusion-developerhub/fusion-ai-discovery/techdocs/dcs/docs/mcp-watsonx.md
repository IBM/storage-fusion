# DCS + watsonx Orchestrate Integration

Connect IBM Fusion DCS to IBM watsonx Orchestrate using the MCP Server for natural language
data catalog exploration and AI agent workflows.

## Configure watsonx Orchestrate

Get the MCP HTTP endpoint from the Developer Hub catalog entry for your cluster (Links tab),
then add to your watsonx Orchestrate MCP server configuration:

```yaml
mcp_servers:
  - name: fusion-dcs-<cluster-id>
    connection_type: http
    url: https://dcs-mcp-route-ibm-data-cataloging.apps.<domain>/mcp/http
    headers:
      Content-Type: "application/json"
```

Replace `<cluster-id>` with the catalog entity name and `<domain>` with the cluster's OCP apps domain.

## Example Agent Prompts

After connecting, try these natural language queries:

- `"Show me all files modified in the last 7 days on Storage Scale"`
- `"Find all PDF files tagged as financial data"`
- `"List all data source connections"`
- `"Show classification policies active on this cluster"`

## IBM Documentation

- [Create Your AI Agents on watsonx Orchestrate for Data Catalog](https://community.ibm.com/community/user/blogs/paul-llamas-virgen/2026/03/06/create-your-ai-agents-on-wx-orch-for-data-catalog)
- [Exploring Your Fusion Data Catalog with NLP](https://community.ibm.com/community/user/blogs/paul-llamas-virgen/2026/03/06/exploring-your-fusion-data-catalog-with-nlp)
