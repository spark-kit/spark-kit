# Spark Kit

**La plomberie numerique pour PME industrielles.**

Spark transforme un Mac Mini en plateforme d'orchestration locale : connectez vos logiciels existants, automatisez vos flux, donnez a vos equipes des outils qu'elles utilisent vraiment — sans toucher a ce qui marche deja.

```
  Logiciels metier du client (CRM, ERP, WMS, facturation, support...)
                       |  source de verite business — INTOUCHABLE
                       |  API / webhook / export CSV
                       v
  ┌──────────────────────────────────────┐
  │  Spark  (Mac Mini chez le client)    │
  │                                      │
  │  n8n       pont controle entre les   │
  │            logiciels existants       │
  │     ↕                                │
  │  NocoDB    tables de travail,        │
  │            ecrans metier,            │
  │            donnees qui n'existaient  │
  │            nulle part avant          │
  │     ↕                                │
  │  Equipes   utilisent NocoDB          │
  │            comme outil quotidien     │
  └──────────────────────────────────────┘
```

Spark ne remplace rien. Le CRM reste. L'ERP reste. Le fichier Excel qui marche depuis 2012 reste. Spark les fait parler entre eux.

---

## Stack

| Composant | Role | Pourquoi celui-la |
|-----------|------|-------------------|
| **n8n** | Orchestration, workflows, connexion entre logiciels | Open source, 400+ connecteurs, code quand il faut |
| **NocoDB** | Base de donnees visuelle (comme Airtable, en local) | Les non-devs peuvent creer des vues et des formulaires |
| **PostgreSQL 16** | Base relationnelle partagee (n8n + NocoDB) | Un seul backup couvre tout |
| **Caddy** | Reverse proxy, HTTPS automatique sur le LAN | `tls internal` = zero config certificats |
| **Uptime Kuma** | Monitoring, alertes si un service tombe | Dashboard visuel, alertes webhook via n8n |

Tout tourne dans Docker via **Colima** (MIT, headless, leger en RAM).

---

## Pre-requis

### Materiel

| | Minimum | Recommande |
|---|---------|------------|
| **Machine** | Mac Mini Apple Silicon | Mac Mini M2/M4 |
| **RAM** | 8 GB (pas de LLM local) | 16 GB |
| **Stockage** | 50 GB libres | 100 GB+ |
| **Reseau** | Ethernet LAN | Ethernet LAN + IP fixe/DHCP reserve |

### Logiciel

- macOS 14 (Sonoma) ou superieur
- Compte administrateur sur la machine
- (Optionnel) Compte Cloudflare + domaine — pour l'acces distant

### Verifications rapides

```bash
uname -m          # doit afficher "arm64"
sw_vers           # macOS 14+
```

---

## Installation

Trois etapes : preparer le Mac, configurer le site, lancer la stack.

### Etape 1 — Preparer le Mac

```bash
# Auto-reboot apres coupure electrique (critique en usine)
sudo pmset -a autorestart 1

# Pas de mise en veille
sudo pmset -a sleep 0
sudo pmset -a disksleep 0
sudo pmset -a displaysleep 0

# Firewall en mode stealth
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on
```

```bash
# Homebrew (si pas deja installe)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Paquets essentiels
brew install colima docker docker-compose git jq curl htop rsync rclone
```

```bash
# Demarrer Colima avec le bon dimensionnement
#   16 GB+ de RAM sur le Mac → 6 GB pour Colima
#    8 GB de RAM sur le Mac  → 4 GB pour Colima (pas de LLM local possible)
colima start --cpu 4 --memory 6 --disk 100 --network-address --vm-type vz --vz-rosetta

# Verifier que Docker repond
docker info
```

### Etape 2 — Configurer le site

```bash
mkdir -p ~/spark/{config,data,logs,backups}
cd ~/spark
```

Generer les secrets (alphabet URL-safe uniquement — ne jamais utiliser `base64` qui produit des `+/=` incompatibles avec certaines configs) :

```bash
gen_secret() { LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$1"; }

cat > .env <<EOF
POSTGRES_PASSWORD=$(gen_secret 32)
N8N_USER=admin
N8N_PASSWORD=$(gen_secret 24)
N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)
NOCODB_JWT_SECRET=$(openssl rand -hex 32)
SPARK_PREFIX=acme
SPARK_DOMAIN=spark.local
EOF

chmod 600 .env
```

> Remplacer `acme` par le slug du client et `spark.local` par le domaine reel.

Creer le fichier d'init PostgreSQL :

```bash
cat > config/init-db.sql <<'SQL'
CREATE DATABASE n8n;
CREATE DATABASE nocodb;
SQL
```

Creer le Caddyfile :

```bash
cat > config/Caddyfile <<'CADDY'
n8n.spark.local {
    tls internal
    reverse_proxy n8n:5678
}
db.spark.local {
    tls internal
    reverse_proxy nocodb:8080
}
status.spark.local {
    tls internal
    reverse_proxy uptime-kuma:3001
}
CADDY
```

Creer le `docker-compose.yml` :

```bash
cat > docker-compose.yml <<'COMPOSE'
services:
  caddy:
    image: caddy:2-alpine
    restart: unless-stopped
    ports:
      - "${SPARK_HOST_HTTP_PORT:-80}:80"
      - "443:443"
    volumes:
      - ./config/Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
    networks: [spark]

  n8n:
    image: n8nio/n8n:1.70.3
    restart: unless-stopped
    environment:
      - N8N_HOST=${SPARK_PREFIX}-n8n.${SPARK_DOMAIN}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - WEBHOOK_URL=https://${SPARK_PREFIX}-n8n.${SPARK_DOMAIN}/
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=${N8N_USER}
      - N8N_BASIC_AUTH_PASSWORD=${N8N_PASSWORD}
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=postgres
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - N8N_PROXY_HOPS=2
      - GENERIC_TIMEZONE=Europe/Paris
    volumes:
      - n8n_data:/home/node/.n8n
    depends_on:
      postgres: { condition: service_healthy }
    networks: [spark]

  nocodb:
    image: nocodb/nocodb:0.260.0
    restart: unless-stopped
    environment:
      - NC_DB_JSON={"client":"pg","connection":{"host":"postgres","port":5432,"user":"postgres","password":"${POSTGRES_PASSWORD}","database":"nocodb"}}
      - NC_AUTH_JWT_SECRET=${NOCODB_JWT_SECRET}
      - NC_PUBLIC_URL=https://${SPARK_PREFIX}-db.${SPARK_DOMAIN}
    volumes:
      - nocodb_data:/usr/app/data
    depends_on:
      postgres: { condition: service_healthy }
    networks: [spark]

  postgres:
    image: postgres:16-alpine
    restart: unless-stopped
    environment:
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./config/init-db.sql:/docker-entrypoint-initdb.d/init.sql:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks: [spark]

  uptime-kuma:
    image: louislam/uptime-kuma:1
    restart: unless-stopped
    volumes:
      - uptime_data:/app/data
    networks: [spark]

volumes:
  caddy_data:
  caddy_config:
  n8n_data:
  nocodb_data:
  postgres_data:
  uptime_data:

networks:
  spark:
    driver: bridge
COMPOSE
```

### Etape 3 — Lancer et verifier

```bash
docker compose up -d --wait
```

Attendre 15 secondes que les services demarrent, puis verifier :

```bash
for svc in n8n:5678 nocodb:8080 uptime-kuma:3001; do
  name="${svc%%:*}" port="${svc##*:}"
  code=$(curl -sk -o /dev/null -w "%{http_code}" "http://localhost:$port" 2>/dev/null || echo "000")
  printf "  %-15s %s\n" "$name" "$([[ $code =~ ^(200|301|302)$ ]] && echo 'OK' || echo "FAIL ($code)")"
done
```

### Configurer le DNS local

Sur chaque poste qui doit acceder a Spark, ajouter dans `/etc/hosts` :

```
<IP_DU_MAC>  n8n.spark.local db.spark.local status.spark.local
```

Recuperer l'IP du Mac :

```bash
ipconfig getifaddr en0
```

### Premier acces

| Service | URL | Identifiants |
|---------|-----|-------------|
| **n8n** | `https://n8n.spark.local` | voir `.env` (`N8N_USER` / `N8N_PASSWORD`) |
| **NocoDB** | `https://db.spark.local` | creer au premier acces |
| **Uptime Kuma** | `https://status.spark.local` | creer au premier acces |

> Le navigateur affichera un avertissement de certificat (self-signed). C'est normal — accepter et continuer.

---

## Architecture interne

```
┌───────────────────────────────────────────────┐
│                Mac Mini (Spark)                │
│                                               │
│  ┌─────────┐   ┌─────────┐   ┌────────────┐  │
│  │  Caddy   │   │  n8n    │   │  NocoDB    │  │
│  │ :80/:443 │──▸│ :5678   │   │  :8080     │  │
│  └─────────┘   └────┬────┘   └─────┬──────┘  │
│       │              │             │          │
│       │         ┌────▼─────────────▼────┐     │
│       │         │     PostgreSQL 16     │     │
│       │         │     :5432             │     │
│       │         │   bases: n8n, nocodb  │     │
│       │         └───────────────────────┘     │
│       │                                       │
│       │         ┌───────────────────────┐     │
│       └────────▸│    Uptime Kuma        │     │
│                 │    :3001              │     │
│                 └───────────────────────┘     │
│                                               │
│  Volumes Docker : n8n_data, nocodb_data,      │
│  postgres_data, uptime_data, caddy_*          │
└───────────────────────────────────────────────┘
```

**Choix structurants** :
- Une seule instance PostgreSQL pour n8n + NocoDB → un `pg_dumpall` sauvegarde tout
- Caddy `tls internal` → HTTPS sur le LAN sans cert externe
- `restart: unless-stopped` + `pmset autorestart 1` → la stack survit aux coupures electriques
- Images Docker epinglees (jamais `latest`) → pas de surprise a la mise a jour
- Colima (MIT, headless) → pas de licence commerciale, pas de GUI

---

## Acces distant (optionnel)

Pour exposer Spark sur internet (support a distance, acces hors LAN), Spark utilise **Cloudflare Tunnel** en mode local-managed (pattern A).

```
Internet → Cloudflare Edge (TLS) → cloudflared (sur le Mac) → Caddy → services
```

Le tunnel est gere par un fichier YAML local (pas par le dashboard CF). Les scripts `tunnel-up.sh` / `tunnel-down.sh` gerent l'ajout et le retrait de routes.

Pre-requis supplementaires :
- Domaine pointe vers Cloudflare (nameservers CF)
- `brew install cloudflared`
- `cloudflared login` (une fois, interactif)
- Token API CF avec scope `Zone:DNS:Edit` sur la zone du domaine

Le hostname suit le pattern **single-level** : `<prefix>-<service>.<domain>` (ex: `acme-n8n.example.com`). Le Universal SSL gratuit de CF couvre ce format.

> Details complets dans la documentation d'architecture.

---

## Depannage

### NocoDB ne demarre pas (502 / crashloop)

**Symptome** : NocoDB redemarre en boucle, Caddy renvoie 502.

**Cause probable** : le mot de passe PostgreSQL contient des caracteres speciaux (`+`, `/`, `=`, `&`, `%`) qui cassent le parsing URL.

**Solution** : utiliser `NC_DB_JSON` (format objet) au lieu de `NC_DB` (format URL). C'est deja fait dans le `docker-compose.yml` ci-dessus. Si vous avez un ancien `.env`, regenerer le mot de passe avec des caracteres URL-safe uniquement.

### Containers en restart loop silencieux

**Symptome** : containers qui sortent avec code 0, redemarrent toutes les ~60s. Pas de stack trace dans les logs. n8n affiche `Task runner connection attempt failed with status code 403`.

**Cause probable** : Colima manque de memoire.

**Diagnostic** :
```bash
docker run --rm alpine free -h
```
Si `available` < 200 MB → redimensionner :
```bash
colima stop
colima start --cpu 4 --memory 6 --disk 100
```

### Erreur cookie / auth derriere reverse proxy

**Symptome** : n8n affiche *"Your n8n server is configured to use a secure cookie, however you are either visiting this via an insecure URL"*.

**Cause** : la chaine de proxy (Cloudflare → cloudflared → Caddy → n8n) perd le header `X-Forwarded-Proto`.

**Solution** : deux choses a verifier :
1. Caddy force le header : `header_up X-Forwarded-Proto https` dans le bloc `reverse_proxy`
2. n8n est configure avec `N8N_PROXY_HOPS=2` (cloudflared + Caddy)

---

## Vocabulaire

| Terme | Sens |
|-------|------|
| **Spark** | Le kit / template — ce projet |
| **Site** | Un deploiement Spark concret : 1 Mac Mini, 1 client, 1 domaine |
| **`SPARK_PREFIX`** | Slug par-site qui forme les hostnames (`<prefix>-<service>.<domain>`) |
| **Pattern A** | Tunnel Cloudflare local-managed (config YAML sur le Mac, pas sur le dashboard CF) |
| **Playbook** | Brique d'integration assemblable (workflow n8n + tables NocoDB + config) |

---

## Organisation du projet

```
spark-kit/
├── spark-kit        ← ce repo (meta, documentation, incidents)
├── templates/       ← methodologie : ingest legacy → PRD → POC
└── <client>/        ← un repo par deploiement client (prive)
       ├── infra/           docker-compose, scripts, config
       ├── discovery/       questionnaire, fiches logiciel, PRD
       └── LESSONS-LEARNED.md
```

---

## Philosophie

Spark est ne d'une conviction : **les petites entreprises meritent l'industrie 4.0**.

Siemens et Dassault Systemes ont construit l'usine connectee pour les grands groupes. Les PME de 10 a 100 personnes n'ont ni le budget ni les equipes pour ca. Spark est leur porte d'entree.

**Principes** :
- **Pas a pas, pas big bang** — on resout un probleme concret en une semaine, puis un autre
- **Side-stack** — on ne touche pas au systeme qui tourne, on pose un deuxieme cerveau a cote
- **La donnee reste chez le client** — Mac Mini sur le LAN, pas de cloud obligatoire
- **La plomberie avant l'IA** — connecter les logiciels existants est le prerequis, l'IA viendra apres

> Version complete : [Manifeste Spark](https://github.com/spark-kit/spark-kit/wiki/manifeste)

---

## Roadmap & decisions

Le suivi detaille de la templatification, les decisions d'architecture et les questions ouvertes sont dans [`ROADMAP.md`](ROADMAP.md).

Les incidents de production et leurs lecons sont archives dans [`INCIDENTS.md`](INCIDENTS.md).

---

*Spark Kit est un projet [Atelier B](https://github.com/spark-kit). Licence a definir.*
