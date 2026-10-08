import os, google.auth
from dotenv import load_dotenv
from google.adk.agents import Agent
from google.adk.apps.app import App
from google.adk.tools.bigquery import BigQueryCredentialsConfig, BigQueryToolset
from google.cloud import bigquery


load_dotenv()
creds, proj = google.auth.default()
bq_tools = BigQueryToolset(credentials_config=BigQueryCredentialsConfig(credentials=creds))
try:
    from app import utils
    refresh_date = utils.get_latest_refresh_date()
    prompt = utils.load_nl2sql_with_few_shot_prompt(refresh_date)
except Exception:
    client = bigquery.Client(project=os.getenv("GOOGLE_CLOUD_PROJECT", proj), credentials=creds)
    refresh_date = list(client.query("SELECT CAST(MAX(refresh_date) AS STRING) AS d FROM bigquery-public-data.google_trends.international_top_terms").result())[0].d
    prompt = f"You are a BigQuery SQL expert for Google Trends (bigquery-public-data.google_trends.international_top_terms). Always filter by refresh_date = '{refresh_date}' and week = (SELECT MAX(week) FROM bigquery-public-data.google_trends.international_top_terms WHERE refresh_date = '{refresh_date}' AND country_name = '<country>'). Group by term, SUM(score) AS total_score, ORDER BY total_score DESC."


root_agent = Agent(
    name="bq_trend_analyst_icaroribeiro",
    model=os.getenv("GEMINI_MODEL", "gemini-2.5-flash"),
    description="BigQuery SQL expert for Google Trends.",
    instruction=prompt,
    tools=[bq_tools],
)
app = App(root_agent=root_agent, name="app")
EOF
uv add google-cloud-bigquery jinja2 python-dotenv < /dev/null
make backend < /dev/null
