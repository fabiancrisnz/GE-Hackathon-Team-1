#!/usr/bin/env bash
set -e
PROJECT_ID=$(gcloud config get-value project)
export GOOGLE_CLOUD_PROJECT="$PROJECT_ID"
echo "🚀 Iniciando Setup Completo no Projeto: $PROJECT_ID"

gcloud services enable aiplatform.googleapis.com bigquery.googleapis.com discoveryengine.googleapis.com cloudresourcemanager.googleapis.com --project="$PROJECT_ID"

mkdir -p ~/hackathon && cd ~/hackathon
if [ ! -d ~/hackathon/agent02_google_trends_bigquery_analyst ] && [ -f ~/resources-hackathon_starter.zip ]; then
  unzip -qo ~/resources-hackathon_starter.zip -d ~/hackathon
fi

echo "⏳ [1/4] Agente 1 (basic-search-agent-idr)..."
cd ~/hackathon && rm -rf ~/hackathon/basic-search-agent-idr
printf "1\n1\n1\nus-east1\nY\n" | uvx agent-starter-pack create basic-search-agent-idr
cd ~/hackathon/basic-search-agent-idr && rm -f deployment_metadata.json
cat << 'EOF' > app/agent.py
import os
from google.adk.agents import Agent
from google.adk.apps.app import App
from google.adk.tools import google_search

root_agent = Agent(
    name="basic_search_agent_icaroribeiro",
    model=os.getenv("GEMINI_MODEL", "gemini-2.5-flash"),
    description="Basic Search Agent using Google Search.",
    instruction="You are a helpful search assistant. Use Google Search to answer user queries accurately.",
    tools=[google_search],
)
app = App(root_agent=root_agent, name="app")
EOF
make backend < /dev/null

echo "⏳ [2/4] Agente 2 (bq-trends-agent-idr)..."
rm -rf ~/hackathon/bq-trends-agent-idr
cp -r ~/hackathon/basic-search-agent-idr ~/hackathon/bq-trends-agent-idr
cd ~/hackathon/bq-trends-agent-idr && rm -f deployment_metadata.json
find . -maxdepth 3 -type f -not -path '*/.*' -exec sed -i 's/basic-search-agent-idr/bq-trends-agent-idr/g' {} +
if [ -d ~/hackathon/agent02_google_trends_bigquery_analyst ]; then
  cp -r ~/hackathon/agent02_google_trends_bigquery_analyst/utils.py ~/hackathon/agent02_google_trends_bigquery_analyst/prompts app/ || true
fi
cat << 'EOF' > app/agent.py
import os, google.auth
from dotenv import load_dotenv
from google.adk.agents import Agent
from google.adk.apps.app import App
from google.adk.tools.bigquery import BigQueryCredentialsConfig, BigQueryToolset
from google.cloud import bigquery
load_dotenv()
credentials, project_id = google.auth.default()
bigquery_toolset = BigQueryToolset(credentials_config=BigQueryCredentialsConfig(credentials=credentials))
try:
    from app import utils
    refresh_date = utils.get_latest_refresh_date()
    system_instruction = utils.load_nl2sql_with_few_shot_prompt(refresh_date)
except Exception:
    bq_client = bigquery.Client(project=os.getenv("GOOGLE_CLOUD_PROJECT", project_id), credentials=credentials)
    refresh_date = list(bq_client.query("SELECT CAST(MAX(refresh_date) AS STRING) AS d FROM `bigquery-public-data.google_trends.international_top_terms`").result())[0].d
    system_instruction = f"""You are a BigQuery SQL expert for Google Trends (`bigquery-public-data.google_trends.international_top_terms` and `international_top_rising_terms`).
Always filter by `refresh_date = '{refresh_date}'` and for the most recent week filter `week = (SELECT MAX(week) FROM \`bigquery-public-data.google_trends.international_top_terms\` WHERE refresh_date = '{refresh_date}' AND country_name = '<country>')`. Group by `term`, sum `score` as `total_score`, order by `total_score DESC`."""

root_agent = Agent(
    name="bq_trend_analyst_icaroribeiro",
    model=os.getenv("GEMINI_MODEL", "gemini-2.5-flash"),
    description="Agent expert in translating natural language to BigQuery SQL to analyze Google Trends.",
    instruction=system_instruction,
    tools=[bigquery_toolset],
)
app = App(root_agent=root_agent, name="app")
EOF
uv add google-cloud-bigquery jinja2 python-dotenv < /dev/null
make backend < /dev/null

echo "⏳ [3/4] Tabela BigQuery tam_stockout_analytics.vms_created_last30days..."
bq --project_id="$PROJECT_ID" mk --dataset --location=US "$PROJECT_ID:tam_stockout_analytics" || true
bq --project_id="$PROJECT_ID" query --use_legacy_sql=false "
CREATE OR REPLACE TABLE \`$PROJECT_ID.tam_stockout_analytics.vms_created_last30days\` PARTITION BY event_date AS
WITH h AS (SELECT ts AS timestamp_hour FROM UNNEST(GENERATE_TIMESTAMP_ARRAY(TIMESTAMP_TRUNC(TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY), HOUR), TIMESTAMP_TRUNC(CURRENT_TIMESTAMP(), HOUR), INTERVAL 1 HOUR)) AS ts),
p AS (
  SELECT 586798498348 AS project_number, 'media-live-streaming-prd' AS project_id, 'southamerica-east1' AS region, 'southamerica-east1-a' AS zone, 'N2' AS machine_family, 'n2-standard-64' AS exact_vm_type, 64 AS vcpus, 256 AS ram_gb, 0.28 AS r UNION ALL
  SELECT 586798498348, 'media-live-streaming-prd', 'southamerica-east1', 'southamerica-east1-b', 'N4', 'n4-standard-64', 64, 256, 0.01 UNION ALL
  SELECT 719283746510, 'gke-tsuru-platform-prd', 'southamerica-east1', 'southamerica-east1-c', 'E2', 'e2-standard-32', 32, 128, 0.19 UNION ALL
  SELECT 839102938471, 'dataflow-realtime-analytics-prd', 'us-east1', 'us-east1-b', 'C3', 'c3-highcpu-88', 88, 176, 0.15 UNION ALL
  SELECT 839102938471, 'dataflow-realtime-analytics-prd', 'us-east1', 'us-east1-c', 'C4', 'c4-highcpu-96', 96, 192, 0.005 UNION ALL
  SELECT 918273645019, 'ai-video-highlights-prd', 'us-east1', 'us-east1-d', 'G2', 'g2-standard-16', 16, 64, 0.34 UNION ALL
  SELECT 445566778899, 'adtech-bidding-engine-prd', 'southamerica-east1', 'southamerica-east1-a', 'N2D', 'n2d-standard-48', 48, 192, 0.12
),
e AS (SELECT h.timestamp_hour, DATE(h.timestamp_hour) AS event_date, EXTRACT(HOUR FROM h.timestamp_hour AT TIME ZONE 'America/Sao_Paulo') AS hour_brt, p.*, i FROM h CROSS JOIN p CROSS JOIN UNNEST(GENERATE_ARRAY(1, 5)) AS i),
s AS (SELECT *, (r * IF(hour_brt BETWEEN 19 AND 22, 2.4, 0.6) * IF(timestamp_hour >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 2 DAY), 1.5, 1.0)) > (MOD(ABS(FARM_FINGERPRINT(CONCAT(project_id, zone, CAST(timestamp_hour AS STRING), CAST(i AS STRING)))), 1000) / 1000.0) AS so FROM e)
SELECT timestamp_hour, event_date, hour_brt, project_number, project_id, region, zone, machine_family, exact_vm_type, vcpus, ram_gb, CONCAT('inst-', CAST(project_number AS STRING), '-', FORMAT_TIMESTAMP('%Y%m%d%H', timestamp_hour), '-', CAST(i AS STRING)) AS machine_id, IF(so, 'STOCKOUT_TYPE_ZONE_RESOURCE_POOL_EXHAUSTED', 'STOCKOUT_TYPE_NOT_STOCKOUT') AS stockout_type, so AS is_stockout, NOT so AS is_success FROM s;
" < /dev/null

echo "⏳ [4/4] Agente 3 (tam-stockout-agent-idr)..."
rm -rf ~/hackathon/tam-stockout-agent-idr
cp -r ~/hackathon/basic-search-agent-idr ~/hackathon/tam-stockout-agent-idr
cd ~/hackathon/tam-stockout-agent-idr && rm -f deployment_metadata.json
find . -maxdepth 3 -type f -not -path '*/.*' -exec sed -i 's/basic-search-agent-idr/tam-stockout-agent-idr/g' {} +
cat << 'EOF' > app/agent.py
import os, google.auth
from dotenv import load_dotenv
from google.adk.agents import Agent
from google.adk.apps.app import App
from google.adk.tools.bigquery import BigQueryCredentialsConfig, BigQueryToolset
load_dotenv()
credentials, default_project = google.auth.default()
project_id = os.getenv("GOOGLE_CLOUD_PROJECT", default_project)
bigquery_toolset = BigQueryToolset(credentials_config=BigQueryCredentialsConfig(credentials=credentials))
SYSTEM_INSTRUCTION = f"""You are a Google Cloud TAM GCE Stockout & Obtainability (DfO) SQL Analyst.
Query `{project_id}.tam_stockout_analytics.vms_created_last30days` (columns: timestamp_hour, event_date, hour_brt, project_number, project_id, region, zone, machine_family, exact_vm_type, vcpus, ram_gb, machine_id, stockout_type, is_stockout, is_success).
1. Execute SQL in project `{project_id}` and report total attempts, stockouts, stockout rate %, peak hours (`hour_brt`), and impacted zones/shapes.
2. Provide TAM DfO recommendations (migrating Gen 2/3 `n2-standard-64`/`c3-highcpu-88` to Gen 4 `n4-standard-64`/`c4-highcpu-96` with <1% stockouts, multi-zone balancing, multi-family node pools)."""
root_agent = Agent(
    name="tam_stockout_advisor_icaroribeiro",
    model=os.getenv("GEMINI_MODEL", "gemini-2.5-flash"),
    description="TAM GCE Stockout & Obtainability (DfO) Analyst powered by BigQuery.",
    instruction=SYSTEM_INSTRUCTION,
    tools=[bigquery_toolset],
)
app = App(root_agent=root_agent, name="app")
EOF
uv add google-cloud-bigquery python-dotenv < /dev/null
make backend < /dev/null
echo "✅ TUDO PRONTO NO PROJETO $PROJECT_ID!"
