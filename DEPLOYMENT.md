# Deployment Guide for Advisor Agent

This guide covers deploying the Advisor Agent application to Fly.io and setting up a remote model server.

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Deploy to Fly.io](#deploy-to-flyio)
3. [Remote Model Server Options](#remote-model-server-options)
4. [OAuth Configuration](#oauth-configuration)
5. [Environment Variables](#environment-variables)
6. [Monitoring and Maintenance](#monitoring-and-maintenance)

## Prerequisites

- [flyctl](https://fly.io/docs/hands-on/install-flyctl/) installed and authenticated
- Fly.io account
- Google OAuth credentials (for production redirect URIs)
- HubSpot OAuth credentials (for production redirect URIs)

## Deploy to Fly.io

### 1. Initialize Fly.io App

```bash
# Login to Fly.io
fly auth login

# Launch the app (this will create fly.toml if not exists)
fly launch --no-deploy

# When prompted:
# - Choose app name (or keep suggested name)
# - Choose region (closest to your users)
# - Don't deploy yet (we need to set secrets first)
```

### 2. Create PostgreSQL Database

```bash
# Create a Postgres cluster
fly postgres create

# When prompted:
# - Name: advisor-agent-db (or your preferred name)
# - Region: same as your app
# - Configuration: Development (512MB RAM is sufficient to start)

# Attach the database to your app
fly postgres attach advisor-agent-db --app advisor-agent
```

### 3. Enable pgvector Extension

```bash
# Connect to your database
fly postgres connect -a advisor-agent-db

# In the PostgreSQL prompt:
CREATE EXTENSION IF NOT EXISTS vector;

# Verify
\dx

# Exit
\q
```

### 4. Set Environment Secrets

```bash
# Generate a secret key base
mix phx.gen.secret

# Set all required secrets
fly secrets set \
  SECRET_KEY_BASE="<generated-secret-from-above>" \
  GOOGLE_CLIENT_ID="<your-google-client-id>" \
  GOOGLE_CLIENT_SECRET="<your-google-client-secret>" \
  HUBSPOT_CLIENT_ID="<your-hubspot-client-id>" \
  HUBSPOT_CLIENT_SECRET="<your-hubspot-client-secret>" \
  OPENAI_API_KEY="<your-openai-api-key>" \
  NOMIC_API_KEY="<your-nomic-api-key>" \
  SELF_HOSTED_MODEL_URL="<your-model-server-url>"

# Example for self-hosted model URL:
# If using RunPod: https://your-pod-id.runpod.io
# If using local dev: http://localhost:8080 (development only)
```

### 5. Deploy

```bash
# Deploy the application
fly deploy

# Monitor the deployment
fly logs

# Check status
fly status

# Open in browser
fly open
```

### 6. Verify Deployment

```bash
# Check health endpoint
curl https://advisor-agent.fly.dev/health

# Should return: {"status":"ok"}
```

## Remote Model Server Options

### Option 1: RunPod (Recommended for Production)

**Cost:** ~$0.30-0.50/hour for RTX 4090

1. **Create RunPod Account**: Sign up at [runpod.io](https://www.runpod.io/)

2. **Deploy GPU Pod**:
   ```bash
   # Use RunPod's web interface or CLI
   # Choose a GPU (RTX 4090 recommended for balance of cost/performance)
   # Select a template or use custom Docker image
   ```

3. **Deploy llama-server**:
   Create a Dockerfile:
   ```dockerfile
   FROM nvidia/cuda:12.1.0-runtime-ubuntu22.04

   RUN apt-get update && apt-get install -y wget build-essential

   # Install llama.cpp with CUDA support
   WORKDIR /app
   RUN wget https://github.com/ggerganov/llama.cpp/releases/latest/download/llama-server-linux-cuda
   RUN chmod +x llama-server-linux-cuda

   # Download your model (example)
   RUN wget -O model.gguf https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf

   EXPOSE 8080

   CMD ["./llama-server-linux-cuda", "-m", "model.gguf", "--port", "8080", "--host", "0.0.0.0", "-c", "8192", "-ngl", "99", "--jinja"]
   ```

4. **Configure Networking**:
   - Enable public HTTP access in RunPod
   - Copy the public URL
   - Add API authentication (nginx reverse proxy or middleware)

5. **Update Fly.io Secret**:
   ```bash
   fly secrets set SELF_HOSTED_MODEL_URL="https://your-pod-id.runpod.io"
   ```

### Option 2: Modal Labs (Serverless - Best for Low Usage)

**Cost:** $0.00010/second GPU time (scales to zero)

1. **Install Modal**:
   ```bash
   pip install modal
   modal setup
   ```

2. **Create `modal_llama.py`**:
   ```python
   import modal

   app = modal.App("llama-server")
   image = modal.Image.from_registry(
       "nvidia/cuda:12.1.0-runtime-ubuntu22.04"
   ).run_commands([
       "apt-get update && apt-get install -y wget",
       "wget https://github.com/ggerganov/llama.cpp/releases/latest/download/llama-server-linux-cuda",
       "chmod +x llama-server-linux-cuda"
   ])

   @app.function(
       gpu="A10G",
       image=image,
       timeout=600,
   )
   @modal.web_endpoint(method="POST")
   def chat_completion(request: dict):
       # Proxy to llama-server
       import subprocess
       # Implementation here
       pass
   ```

3. **Deploy**:
   ```bash
   modal deploy modal_llama.py
   ```

### Option 3: Cloud GPU (AWS/GCP)

1. **Provision GPU Instance**:
   - AWS: g4dn.xlarge ($0.526/hour) or p3.2xlarge ($3.06/hour)
   - GCP: n1-standard-4 + Tesla T4 ($0.35/hour GPU + $0.19/hour VM)

2. **Setup Script** (run on instance):
   ```bash
   # Install CUDA
   wget https://developer.download.nvidia.com/compute/cuda/12.1.0/local_installers/cuda_12.1.0_530.30.02_linux.run
   sudo sh cuda_12.1.0_530.30.02_linux.run

   # Install llama.cpp
   git clone https://github.com/ggerganov/llama.cpp
   cd llama.cpp
   make LLAMA_CUDA=1

   # Download model
   wget -O model.gguf <model-url>

   # Run server
   ./llama-server -m model.gguf --port 8080 --host 0.0.0.0 -c 8192 -ngl 99 --jinja
   ```

3. **Setup nginx with SSL**:
   ```bash
   sudo apt install nginx certbot python3-certbot-nginx

   # Configure nginx reverse proxy
   sudo nano /etc/nginx/sites-available/llama

   # Add:
   # server {
   #   listen 80;
   #   server_name your-domain.com;
   #   location / {
   #     proxy_pass http://localhost:8080;
   #   }
   # }

   sudo ln -s /etc/nginx/sites-available/llama /etc/nginx/sites-enabled/
   sudo certbot --nginx -d your-domain.com
   ```

### Option 4: Personal Machine (Development/Testing Only)

1. **Ensure llama-server is Running**:
   ```bash
   llama-server -m /path/to/model.gguf --port 8080 --host 0.0.0.0 -c 8192 -ngl 99 --jinja
   ```

2. **Expose via Tailscale Funnel or ngrok**:
   ```bash
   # Using ngrok:
   ngrok http 8080

   # Using Tailscale Funnel:
   tailscale funnel 8080
   ```

3. **Use the public URL** in SELF_HOSTED_MODEL_URL

## OAuth Configuration

### Update Google OAuth

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Navigate to APIs & Services > Credentials
3. Edit your OAuth 2.0 Client ID
4. Add to **Authorized redirect URIs**:
   - `https://advisor-agent.fly.dev/auth/google/callback`
   - (Keep localhost for development)

### Update HubSpot OAuth

1. Go to [HubSpot Developer Portal](https://developers.hubspot.com/)
2. Navigate to your app
3. Update **Redirect URL**:
   - `https://advisor-agent.fly.dev/auth/hubspot/callback`

## Environment Variables

| Variable | Description | Required | Example |
|----------|-------------|----------|---------|
| `SECRET_KEY_BASE` | Phoenix secret key | Yes | Generate with `mix phx.gen.secret` |
| `DATABASE_URL` | Postgres connection | Yes | Auto-set by `fly postgres attach` |
| `PHX_HOST` | App hostname | Yes | `advisor-agent.fly.dev` (set in fly.toml) |
| `PORT` | HTTP port | Yes | `8080` (set in fly.toml) |
| `GOOGLE_CLIENT_ID` | Google OAuth ID | Yes | From Google Cloud Console |
| `GOOGLE_CLIENT_SECRET` | Google OAuth secret | Yes | From Google Cloud Console |
| `HUBSPOT_CLIENT_ID` | HubSpot OAuth ID | Yes | From HubSpot Developer Portal |
| `HUBSPOT_CLIENT_SECRET` | HubSpot OAuth secret | Yes | From HubSpot Developer Portal |
| `OPENAI_API_KEY` | OpenAI API key | Yes | From OpenAI platform |
| `NOMIC_API_KEY` | Nomic API key | Yes | From Nomic platform |
| `SELF_HOSTED_MODEL_URL` | Model server URL | Optional | `https://your-pod.runpod.io` |

## Monitoring and Maintenance

### View Logs

```bash
# Stream logs
fly logs

# Recent logs
fly logs --recent
```

### Scale the App

```bash
# Scale VM size
fly scale vm shared-cpu-2x --memory 512

# Scale number of machines
fly scale count 2
```

### Database Backups

```bash
# List snapshots
fly postgres snapshots list -a advisor-agent-db

# Create snapshot
fly postgres snapshot create -a advisor-agent-db
```

### Update the App

```bash
# Pull latest code
git pull

# Deploy
fly deploy
```

### SSH into the App

```bash
# SSH into running instance
fly ssh console

# Run Elixir console
fly ssh console -C "/app/bin/advisor_agent remote"
```

### Common Issues

**Problem: Database connection errors**
```bash
# Check database status
fly status -a advisor-agent-db

# Restart database if needed
fly postgres restart -a advisor-agent-db
```

**Problem: Migrations didn't run**
```bash
# Manually run migrations
fly ssh console -C "/app/bin/migrate"
```

**Problem: Model server unreachable**
```bash
# Test model server from your app
fly ssh console
# Then: curl $SELF_HOSTED_MODEL_URL/health
```

## Cost Estimates

### Fly.io App
- **Shared CPU 1x (256MB)**: ~$2/month
- **PostgreSQL (Development)**: ~$2/month
- **Total Fly.io**: ~$4-10/month

### Model Server
- **RunPod (24/7)**: ~$220/month (RTX 4090)
- **RunPod (4hrs/day)**: ~$35/month
- **Modal Labs (pay-per-use)**: ~$5-25/month depending on usage
- **Cloud GPU (AWS g4dn)**: ~$380/month (24/7)
- **Personal machine**: Free (electricity only)

### Total Estimated Costs
- **Low usage (Modal)**: ~$10-30/month
- **Medium usage (RunPod 4hrs/day)**: ~$40-50/month
- **High usage (RunPod 24/7)**: ~$225-250/month

## Next Steps

1. Monitor the application logs for any issues
2. Test OAuth flows with Google and HubSpot
3. Test self-hosted model integration
4. Set up monitoring (Fly.io includes basic metrics)
5. Consider setting up a custom domain
6. Set up automated backups

## Support

For Fly.io issues: https://fly.io/docs/
For llama.cpp issues: https://github.com/ggerganov/llama.cpp/issues
