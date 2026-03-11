#!/usr/bin/env bash
# =============================================================================
# Legal Analyst Squad — Deploy Assistant
# =============================================================================
# Usage:
#   ./deploy.sh local      — Docker Compose (local)
#   ./deploy.sh railway    — Deploy to Railway
#   ./deploy.sh fly        — Deploy to Fly.io
#   ./deploy.sh render     — Deploy to Render
#   ./deploy.sh vercel     — Deploy frontend to Vercel
#   ./deploy.sh stop       — Stop local containers
#   ./deploy.sh status     — Check local status
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
GOLD='\033[0;33m'
NC='\033[0m'

banner() {
  echo ""
  echo -e "${GOLD}╔══════════════════════════════════════════════════════╗${NC}"
  echo -e "${GOLD}║   Legal Analyst Squad — Deploy Assistant             ║${NC}"
  echo -e "${GOLD}║   Sistema de Inteligencia Juridica                   ║${NC}"
  echo -e "${GOLD}╚══════════════════════════════════════════════════════╝${NC}"
  echo ""
}

check_env() {
  if [ ! -f .env ]; then
    echo -e "${YELLOW}[!] .env nao encontrado. Criando a partir do template...${NC}"
    cp .env.example .env
    echo -e "${YELLOW}[!] Edite o arquivo .env com sua ANTHROPIC_API_KEY antes de continuar.${NC}"
    echo -e "${YELLOW}    vim .env${NC}"
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# LOCAL — Docker Compose
# ---------------------------------------------------------------------------
deploy_local() {
  echo -e "${BLUE}[*] Deploy local via Docker Compose...${NC}"

  if ! command -v docker &>/dev/null; then
    echo -e "${RED}[x] Docker nao encontrado. Instale em: https://docs.docker.com/get-docker/${NC}"
    exit 1
  fi

  check_env || exit 1

  echo -e "${GREEN}[+] Construindo imagens...${NC}"
  docker compose build

  echo -e "${GREEN}[+] Iniciando servicos...${NC}"
  docker compose up -d

  echo ""
  echo -e "${GREEN}[OK] Legal Analyst Squad esta rodando!${NC}"
  echo -e "     Frontend: ${BLUE}http://localhost:${UI_PORT:-3000}${NC}"
  echo -e "     Backend:  ${BLUE}http://localhost:${API_PORT:-8000}/api/health${NC}"
  echo -e "     Swagger:  ${BLUE}http://localhost:${API_PORT:-8000}/docs${NC}"
  echo ""
  echo -e "${YELLOW}     Para parar: ./deploy.sh stop${NC}"
}

# ---------------------------------------------------------------------------
# RAILWAY
# ---------------------------------------------------------------------------
deploy_railway() {
  echo -e "${BLUE}[*] Deploy para Railway...${NC}"

  if ! command -v railway &>/dev/null; then
    echo -e "${YELLOW}[!] Railway CLI nao encontrado. Instalando...${NC}"
    echo -e "    npm install -g @railway/cli"
    echo -e "    railway login"
    exit 1
  fi

  echo -e "${GREEN}[+] Criando projeto Railway...${NC}"
  echo ""
  echo "O Railway detecta automaticamente o docker-compose.yml."
  echo "Siga os passos:"
  echo ""
  echo -e "  ${GOLD}1.${NC} railway login"
  echo -e "  ${GOLD}2.${NC} railway init"
  echo -e "  ${GOLD}3.${NC} railway variables set ANTHROPIC_API_KEY=sk-ant-..."
  echo -e "  ${GOLD}4.${NC} railway up"
  echo ""
  echo -e "  Ou via dashboard: ${BLUE}https://railway.app/new${NC}"
  echo "  -> New Project -> Deploy from GitHub Repo"
  echo "  -> Selecione o repo e configure as env vars"
  echo ""

  read -p "Deseja executar 'railway up' agora? (y/n) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    railway up
  fi
}

# ---------------------------------------------------------------------------
# FLY.IO
# ---------------------------------------------------------------------------
deploy_fly() {
  echo -e "${BLUE}[*] Deploy para Fly.io...${NC}"

  if ! command -v fly &>/dev/null; then
    echo -e "${YELLOW}[!] Fly CLI nao encontrado. Instalando...${NC}"
    echo -e "    curl -L https://fly.io/install.sh | sh"
    echo -e "    fly auth login"
    exit 1
  fi

  # Generate fly.toml for backend
  cat > fly.toml <<'FLYTOML'
app = "legal-analyst-api"
primary_region = "gru"

[build]
  dockerfile = "backend/Dockerfile"

[env]
  ANTHROPIC_MODEL = "claude-sonnet-4-20250514"

[http_service]
  internal_port = 8000
  force_https = true
  auto_stop_machines = true
  auto_start_machines = true
  min_machines_running = 0

[[vm]]
  cpu_kind = "shared"
  cpus = 1
  memory_mb = 512
FLYTOML

  echo -e "${GREEN}[+] fly.toml gerado.${NC}"
  echo ""
  echo "Passos para deploy:"
  echo ""
  echo -e "  ${GOLD}1.${NC} fly auth login"
  echo -e "  ${GOLD}2.${NC} fly launch  (aceite as configuracoes)"
  echo -e "  ${GOLD}3.${NC} fly secrets set ANTHROPIC_API_KEY=sk-ant-..."
  echo -e "  ${GOLD}4.${NC} fly deploy"
  echo ""
  echo "Para o frontend, use Vercel ou Cloudflare Pages:"
  echo -e "  ${GOLD}5.${NC} ./deploy.sh vercel"
  echo ""

  read -p "Deseja executar 'fly launch' agora? (y/n) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    fly launch
  fi
}

# ---------------------------------------------------------------------------
# RENDER
# ---------------------------------------------------------------------------
deploy_render() {
  echo -e "${BLUE}[*] Deploy para Render...${NC}"

  # Generate render.yaml
  cat > render.yaml <<'RENDERYAML'
services:
  - type: web
    name: legal-analyst-api
    runtime: docker
    dockerfilePath: ./backend/Dockerfile
    dockerContext: ./backend
    region: oregon
    plan: free
    healthCheckPath: /api/health
    envVars:
      - key: ANTHROPIC_API_KEY
        sync: false
      - key: ANTHROPIC_MODEL
        value: claude-sonnet-4-20250514
    disk:
      name: uploads
      mountPath: /app/uploads
      sizeGB: 1

  - type: web
    name: legal-analyst-ui
    runtime: static
    buildCommand: cd frontend && npm install && npm run build
    staticPublishPath: frontend/dist
    headers:
      - path: /*
        name: Cache-Control
        value: public, max-age=86400
    routes:
      - type: rewrite
        source: /api/*
        destination: https://legal-analyst-api.onrender.com/api/*
      - type: rewrite
        source: /*
        destination: /index.html
RENDERYAML

  echo -e "${GREEN}[+] render.yaml gerado.${NC}"
  echo ""
  echo "Passos para deploy no Render:"
  echo ""
  echo -e "  ${GOLD}1.${NC} Acesse ${BLUE}https://dashboard.render.com/select-repo?type=blueprint${NC}"
  echo -e "  ${GOLD}2.${NC} Conecte seu repositorio GitHub"
  echo -e "  ${GOLD}3.${NC} O Render detecta automaticamente o render.yaml"
  echo -e "  ${GOLD}4.${NC} Configure ANTHROPIC_API_KEY nas variaveis de ambiente"
  echo -e "  ${GOLD}5.${NC} Clique em 'Apply'"
  echo ""
}

# ---------------------------------------------------------------------------
# VERCEL (frontend only)
# ---------------------------------------------------------------------------
deploy_vercel() {
  echo -e "${BLUE}[*] Deploy do frontend para Vercel...${NC}"

  if ! command -v vercel &>/dev/null; then
    echo -e "${YELLOW}[!] Vercel CLI nao encontrado.${NC}"
    echo -e "    npm install -g vercel"
    echo -e "    vercel login"
    exit 1
  fi

  # Generate vercel.json
  cat > frontend/vercel.json <<'VERCELJSON'
{
  "buildCommand": "npm run build",
  "outputDirectory": "dist",
  "framework": "vite",
  "rewrites": [
    {
      "source": "/api/(.*)",
      "destination": "${BACKEND_URL}/api/$1"
    },
    {
      "source": "/(.*)",
      "destination": "/index.html"
    }
  ]
}
VERCELJSON

  echo -e "${GREEN}[+] vercel.json gerado.${NC}"
  echo ""
  echo "Passos:"
  echo ""
  echo -e "  ${GOLD}1.${NC} cd frontend"
  echo -e "  ${GOLD}2.${NC} vercel"
  echo -e "  ${GOLD}3.${NC} Configure BACKEND_URL nas env vars do Vercel"
  echo -e "     (URL do backend: Railway, Fly.io ou Render)"
  echo ""

  read -p "Deseja executar 'vercel' agora? (y/n) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    cd frontend && vercel
  fi
}

# ---------------------------------------------------------------------------
# STOP / STATUS
# ---------------------------------------------------------------------------
stop_local() {
  echo -e "${YELLOW}[*] Parando servicos...${NC}"
  docker compose down
  echo -e "${GREEN}[OK] Servicos encerrados.${NC}"
}

show_status() {
  echo -e "${BLUE}[*] Status dos servicos:${NC}"
  echo ""
  docker compose ps 2>/dev/null || echo "Nenhum servico rodando."
  echo ""
  echo -e "${BLUE}[*] Health check:${NC}"
  curl -s http://localhost:${API_PORT:-8000}/api/health 2>/dev/null \
    && echo "" \
    || echo -e "${RED}Backend nao acessivel${NC}"
}

# ---------------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------------
banner

case "${1:-help}" in
  local)    deploy_local ;;
  railway)  deploy_railway ;;
  fly)      deploy_fly ;;
  render)   deploy_render ;;
  vercel)   deploy_vercel ;;
  stop)     stop_local ;;
  status)   show_status ;;
  *)
    echo "Uso: ./deploy.sh <comando>"
    echo ""
    echo "Comandos disponiveis:"
    echo ""
    echo -e "  ${GREEN}local${NC}      Docker Compose (desenvolvimento local)"
    echo -e "  ${GREEN}railway${NC}    Deploy para Railway (recomendado)"
    echo -e "  ${GREEN}fly${NC}        Deploy para Fly.io"
    echo -e "  ${GREEN}render${NC}     Deploy para Render"
    echo -e "  ${GREEN}vercel${NC}     Deploy frontend para Vercel"
    echo -e "  ${YELLOW}stop${NC}       Parar servicos locais"
    echo -e "  ${YELLOW}status${NC}     Ver status dos servicos"
    echo ""
    echo "Exemplo rapido (local):"
    echo -e "  ${GOLD}cp .env.example .env${NC}"
    echo -e "  ${GOLD}vim .env  # configure ANTHROPIC_API_KEY${NC}"
    echo -e "  ${GOLD}./deploy.sh local${NC}"
    echo ""
    ;;
esac
