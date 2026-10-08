import os
import logging
import google.cloud.logging
from google.cloud.logging_v2.handlers import CloudLoggingHandler
from dotenv import load_dotenv
from google.adk.agents import Agent
from google.adk.apps.app import App
from google.adk.tools import google_search

# Initialize the Google Cloud Logging client
client = google.cloud.logging.Client()
# Create a Cloud Logging handler
handler = CloudLoggingHandler(client)
# Configure the root Python logger
logging.getLogger().setLevel(logging.INFO)
logging.getLogger().addHandler(handler)
logging.info("Cloud Logging initialized for ADK agent script")
handler.close()
load_dotenv()

# Define the agent with Google Search tool
# IMPORTANT: If sharing a GCP project, append your LDAP to the name to make it unique.
root_agent = Agent(
    name="basic_search_agent_YOUR_LDAP",
    model=os.getenv("GEMINI_MODEL", "gemini-2.5-flash"),
    description="Agent to answer questions using Google Search.",
    instruction="I can answer your questions by searching the internet. Just ask me anything!",
    tools=[google_search],
)
app = App(root_agent=root_agent, name="app")
