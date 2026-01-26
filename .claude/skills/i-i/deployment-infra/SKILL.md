---
name: deployment-infra
description: Setup deployment infrastructure with Docker, Caddy reverse proxy, deployment/rollback scripts, and GitHub Actions for building images.
author: Interactor Workspace Practices
source_docs:
  - docs/i-i/interactor-workspace-docs/docs/development-practices.md#deployment-infrastructure
---

# Deployment Infrastructure

**Documentation:** `docs/i-i/interactor-workspace-docs/docs/development-practices.md`

## When to Use

- Setting up production deployment for a new project
- Need Docker-based deployment with easy rollback
- Want HTTPS with automatic certificate management
- Setting up CI/CD for Docker image builds

## Folder Structure

```
deploy/
├── README.md                      # Deployment guide
├── .env.example                   # Server environment template
├── .env.local.example             # Local SSH connection config
├── docker-compose.prod.yml        # Production Docker Compose
├── caddy/
│   └── Caddyfile                  # HTTPS reverse proxy
├── scripts/
│   ├── local/                     # Run on developer machine
│   │   ├── generate-secrets.sh    # Generate passwords/keys
│   │   ├── logs.sh                # Fetch production logs
│   │   ├── ssh.sh                 # SSH helper
│   │   ├── setup-remote.sh        # Initial server setup
│   │   └── wait-and-deploy.sh     # Wait for image, deploy
│   └── server/                    # Run on production server
│       ├── setup-server.sh        # Server provisioning
│       ├── deploy.sh              # Pull and deploy
│       ├── rollback.sh            # Rollback to previous
│       └── backup-db.sh           # Database backup
└── github-actions/
    └── docker-build.yml           # Multi-arch Docker build
```

**Key Principle:** Scripts in `local/` run on your machine and SSH into the server. Scripts in `server/` run directly on the production server.

## Components

### 1. Docker Compose Production

- App binds to `127.0.0.1` only - Caddy handles external traffic
- PostgreSQL not exposed externally
- Health checks enable zero-downtime deploys
- Log rotation prevents disk fill

### 2. Caddy Reverse Proxy

- Automatic HTTPS via Let's Encrypt
- HTTP/2 and HTTP/3 built-in
- Upstream health checking
- Security headers by default

### 3. Deploy Script

- Saves current version for rollback
- Pulls new Docker image
- Runs database migrations
- Performs health check after deploy

### 4. Rollback Script

- Rolls back to previous version
- Or specific version by tag
- Uses same deploy process for consistency

### 5. GitHub Actions Docker Build

- Multi-architecture builds (amd64, arm64)
- Automatic tagging from git tags
- Build caching for speed

## Deployment Workflow

### Initial Setup (one-time)

```bash
# 1. Configure local SSH settings
cd my-service/deploy
cp .env.local.example .env.local

# 2. Generate secrets
./scripts/local/generate-secrets.sh

# 3. SSH to server and configure
./scripts/local/ssh.sh
cd /opt/my-service
cp .env.example .env
nano .env  # Paste secrets
sudo cp caddy/Caddyfile /etc/caddy/Caddyfile
sudo systemctl reload caddy

# 4. Deploy
./scripts/server/deploy.sh
```

### Regular Deployment

```bash
# After pushing to main (triggers Docker build)
./scripts/local/wait-and-deploy.sh

# Or manually on server
./scripts/server/deploy.sh v1.2.0
```

### Rollback

```bash
./scripts/server/rollback.sh           # Previous version
./scripts/server/rollback.sh v1.1.0    # Specific version
```

## Instructions

1. Read the full implementation from source documentation
2. Create the `deploy/` folder structure
3. Copy and customize `docker-compose.prod.yml`
4. Set up Caddyfile with your domain
5. Create deployment scripts
6. Add GitHub Actions workflow
7. Run initial server setup
8. Deploy!

## Gitignore Additions

```
deploy/.env
deploy/.env.local
deploy/.previous_version
deploy/scripts/local/*.pem
deploy/backups/
```

## Related Skills

- `ci-setup` - GitHub Actions for testing
- `hot-reload` - Debug production without full deploys
