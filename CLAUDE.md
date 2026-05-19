# CLAUDE.md — Guide agent pour un deploiement Spark

> Toi (Claude) qui debarques sur un repo Spark : voici l'essentiel avant d'ecrire ou modifier quoi que ce soit.

---

## Ce qu'est Spark

Spark est un **side-stack** : un Mac Mini pose a cote des systemes existants de l'entreprise. Il ne remplace rien. Le CRM reste. L'ERP reste. Le fichier Excel qui marche depuis 2012 reste. Spark les fait parler entre eux.

**La source de verite business est toujours le systeme metier de l'entreprise** (Phone Check, Pennylane, Google Sheets, ERP, WMS...). NocoDB n'est jamais la source de verite business — c'est un bac a sable, un staging, une surface pour des donnees qui n'existaient nulle part avant. n8n est un pont controle qui ouvre des portes choisies vers les sources metier.

---

## Vocabulaire critique

| Terme | Sens |
|-------|------|
| **Spark** | La kit / methode (org GitHub `spark-kit`). Pas un site specifique. |
| **Site** | Un deploiement Spark concret : 1 Mac Mini, 1 entreprise, 1 domaine, 1 repo. |
| **`SPARK_PREFIX`** | Slug par-site qui forme les hostnames (`<prefix>-<service>.<domain>`). Ce n'est PAS le nom de la kit. |
| **Playbook** | Brique d'integration assemblable (workflow n8n + tables NocoDB + config). |

---

## Stack technique

| Service | Role | Port interne |
|---------|------|-------------|
| n8n | Orchestration, workflows | 5678 |
| NocoDB | Base visuelle, ecrans metier | 8080 |
| PostgreSQL 16 | Base relationnelle partagee (users separes : `n8n`, `nocodb`) | 5432 |
| Caddy | Reverse proxy, route le trafic | 80 (127.0.0.1 uniquement) |
| cloudflared | Tunnel Cloudflare (TLS, acces distant) | host, pas Docker |

Caddy a `auto_https off` — c'est Cloudflare qui gere le TLS. Caddy injecte `X-Forwarded-Proto https` pour que les apps croient etre en HTTPS.

---

## Outillage agent : skills + MCP

La stack embarque deux couches complementaires. **Utiliser les MCP pour interagir avec les instances live, les skills pour la reference API et les patterns.**

### n8n

**Skills** (7 skills `n8n-*`) :
- `n8n-node-configuration` — configuration des nodes par type et operation
- `n8n-workflow-patterns` — patterns architecturaux prouves (webhook, CRUD, scheduling, AI agents)
- `n8n-expression-syntax` — syntaxe `{{ }}`, `$json`, `$node`, troubleshooting expressions
- `n8n-code-javascript` — Code nodes JS, `$input`, `$helpers`, `DateTime`
- `n8n-code-python` — Code nodes Python, `_input`, `_json`, limitations
- `n8n-validation-expert` — interpretation des erreurs de validation
- `n8n-mcp-tools-expert` — guide d'utilisation des outils MCP n8n

**MCP** (`n8n-mcp`) :
- Lecture/ecriture de workflows, activation, executions
- Se connecte a `http://n8n:5678` en interne Docker
- Script wrapper : `infra/scripts/mcp-n8n.sh`

### NocoDB

**Skill** (`nocodb`) :
- Reference API v3 complete : data CRUD, meta management, links, filters, sorts, attachments
- Inclut le CLI `nocodb.sh` — c'est l'outil d'**action** pour NocoDB
- Syntaxe des filtres `where` : `(field,op,value)~and(field2,op2,value2)`

**Acces live : API v3 via CLI `nocodb.sh`** (pas de MCP). L'ecosysteme MCP NocoDB n'est pas stable contre les versions recentes (`2026.04.5+`) — le package historique `@andrewlwn77/nocodb-mcp@0.2.2` cible v1/v2 que NocoDB rejette pour les PAT. Cf. INC-2026-05-19 dans `INCIDENTS.md`. La stack n'integre pas de MCP NocoDB ; on s'en tient au CLI tant qu'un package compatible v3 n'a pas ete valide.

Utilisation type :
```bash
set -a; source infra/.env; set +a
export NOCODB_TOKEN="$NOCODB_API_TOKEN"
export NOCODB_URL="https://<prefix>-db.<domain>"
bash ~/.claude/skills/nocodb/scripts/nocodb.sh table:list <base>
unset NOCODB_TOKEN NOCODB_API_TOKEN
```

### Regles

1. **n8n : ne jamais `curl` quand le MCP n8n peut le faire.** Le MCP gere auth, pagination, format.
2. **NocoDB : toujours passer par `nocodb.sh`.** Pas de curl ad-hoc, pas de docker exec psql, pas de lecture brute de `.env`.
3. **Skills = reference, MCP/CLI = action.** Consulter la skill pour comprendre la syntaxe, utiliser le MCP n8n ou le CLI NocoDB pour executer.
4. **Charger la skill avant de configurer un node.** `n8n-node-configuration` donne les champs requis par operation — evite les allers-retours.
5. **Valider avec `n8n-validation-expert`** apres avoir modifie un workflow.

---

## Configuration Claude Code

Le repo entreprise contient un `.mcp.json` (gitignored) a la racine qui pointe vers le wrapper n8n :

```json
{
  "mcpServers": {
    "n8n-mcp": {
      "command": "bash",
      "args": ["infra/scripts/mcp-n8n.sh"]
    }
  }
}
```

Le script source `infra/.env` et lance `docker run --network spark_spark` en mode stdio (`name: spark` dans le compose → reseau `spark_spark`). Au demarrage d'une session, le MCP n8n apparait automatiquement comme tool provider. NocoDB s'utilise via le CLI `nocodb.sh` de la skill (cf. plus haut).

### Installation des skills

Les skills sont globales (une seule fois par poste, dans `~/.claude/skills/`) :

```bash
npx @anthropic-ai/claude-code skills add nocodb/agent-skills
npx @anthropic-ai/claude-code skills add n8n/agent-skills
```

### Obtention des cles API

Apres le premier acces aux apps :
1. **n8n** : Settings > API > Create API Key → `N8N_API_KEY` dans `.env`
2. **NocoDB** : Team & Settings > Tokens > Add New Token → `NOCODB_API_TOKEN` dans `.env`
3. Relancer `docker compose up -d` pour que les MCP prennent les cles.

---

## Principes de travail

### Donnees

- NocoDB = bac a sable. Le systeme metier = source de verite.
- Quand une donnee existe deja dans un legacy, NocoDB en est le **cache/staging**.
- Quand une donnee n'existait nulle part (ex: WMS d'un atelier papier), NocoDB devient la **source pour cette donnee precise**.

### Secrets

- Pas de credential en clair dans le repo — jamais.
- `.env` est gitignored. Verifier avec `git status` avant tout commit.
- Les secrets metier (API keys, tokens des logiciels de l'entreprise) vont dans **n8n > Settings > Credentials**, chiffres par `N8N_ENCRYPTION_KEY`.
- Le `.env` ne contient que les secrets d'infrastructure de la stack.

### Workflows n8n

- Un workflow = une responsabilite claire.
- Nommer les workflows avec un prefixe explicite : `[SYNC] CRM → NocoDB`, `[ALERT] Stock bas`, `[WEBHOOK] Commande recue`.
- Tester les workflows en mode manuel avant de les activer.
- Les credentials sont references par nom, pas par ID — facilite la portabilite.

### Modifications infra

- Travailler dans `infra/`.
- Tester localement (`docker compose up -d`) avant de committer.
- Commit avec prefixe : `infra: ...`, `workflow: ...`, `discovery: ...`.

---

## Structure d'un repo entreprise

```
<entreprise>/
├── infra/
│   ├── .env                  secrets (gitignored)
│   ├── .env.example          template sans secrets
│   ├── docker-compose.yml
│   ├── config/
│   │   ├── Caddyfile
│   │   └── postgres/init-db.sh
│   ├── apps/                    apps metier statiques (servies par Caddy sur -app)
│   └── scripts/
│       ├── tunnel-up.sh      creation routes + CNAMEs CF
│       ├── tunnel-down.sh    suppression routes + CNAMEs
│       └── mcp-n8n.sh        wrapper MCP n8n
├── discovery/
│   ├── onboarding/           questionnaires entreprise
│   ├── fiches/               fiches-logiciel legacy
│   └── prds/                 PRDs des POCs
├── LESSONS-LEARNED.md        notes operationnelles
├── CLAUDE.md                 ce fichier, adapte a l'entreprise
└── .mcp.json                 config MCP (gitignored)
```

---

## Pieges connus

### NocoDB — toujours `NC_DB_JSON`, jamais `NC_DB`

La conf URL `NC_DB="pg://...&p=XXX&d=..."` URL-decode le password. Si le password contient `&`, `=`, `+`, `%` → auth fail en boucle. Utiliser `NC_DB_JSON` (objet JSON, pas de parsing URL).

### Sizing Colima

4 GiB par defaut. Si la stack devient lourde ou si des LLMs locaux tournent en parallele → 6+ GiB, mais seulement sur Mac 16 GB+. Diagnostic memoire : `docker run --rm alpine free -h`.

### Tunnel Cloudflare — pattern A

Le YAML cloudflared vit cote hote (`~/.cloudflared/config-*.yml`), edite par `scripts/tunnel-up.sh` via blocs marques `# >>> spark-begin` / `# <<< spark-end`. Ne pas editer manuellement les blocs marques.

---

## Liens

- Meta Spark : https://github.com/spark-kit/spark-kit
- Templates (gabarits methodologie) : https://github.com/spark-kit/templates
- Wiki Spark (manifeste, archi, concurrence) : `~/Documents/spark-vault/wiki/`
