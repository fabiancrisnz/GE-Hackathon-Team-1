# GE Hackathon Project - Team 1
## Overview
This repository contains our team's completed agents and Gemini Enterprise configuration for the GE Hackathon.
## Repository Contents
- `ge-config/`: Gemini Enterprise App configuration manifest and Model Armor policy metadata.
- `basic-search-agent/`: Basic search ADK agent integrated with Google Search and deployed to Agent Engine.
- `bq-trend-agent/`: BigQuery SQL analyst agent using `BigQueryToolset` to query Google Trends data in real-time.
- `github-mcp-agent/`: ADK agent leveraging Model Context Protocol (MCP) to query GitHub repositories and issues.
## Setup Instructions
1. Clone this repository.
2. For each agent directory, copy `.env.example` to `.env` and fill in required GCP project IDs and credentials.
3. Install dependencies: `uv sync`
4. Test locally: `uv run adk web`
5. Deploy to backend: `make backend
