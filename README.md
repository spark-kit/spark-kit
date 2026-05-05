# Spark Kit — Roadmap de templatification

> Suivi de la transformation progressive de `kyklos-container` en **template Spark** réutilisable pour de nouveaux sites.
> Le reste du repo reste opérationnel pour le déploiement `kyklos` en cours.
>
> **Voir aussi** : [`INCIDENTS.md`](INCIDENTS.md) — archive des fails rencontrés sur les déploiements Spark, avec leçons exploitables à porter dans la kit.

---

## 1. Vocabulaire

Distinction critique à garder à l'œil — on a confondu les deux pendant le bug NocoDB du 2026-05-05.

| Terme | Sens |
|---|---|
| **Spark** | nom de la **kit / template** (ce qu'on construit ici). Cf. wiki `spark-vault/wiki/topics/architecture-technique.md`. |
| **Site** | un **déploiement** Spark concret (1 Mac Mini, 1 domaine, 1 client). Le site courant s'appelle `kyklos` et utilise `usine.io`. |
| **`SPARK_PREFIX`** (futur) | la valeur par-déploiement qui forme les hostnames `<prefix>-<service>.<domain>`. Vaut `kyklos` aujourd'hui. |
| **Pattern A** | tunnel Cloudflare *local-managed* (YAML sur l'hôte). Cf. archi §3.3. Choix Spark par défaut. |
| **kyklos-container** | nom historique du repo. À renommer en Phase 1. |

---

## 2. Vision

À terme, déployer un nouveau site Spark = 3 étapes :

```bash
git clone <spark-template>      spark-acme
cd spark-acme
./scripts/spark-bootstrap.sh    # host : pmset, brew, Colima, .env auto-généré
./scripts/spark-new-site.sh acme acme.fr   # tunnel CF + DNS + up
```

Reste manuel (1× par compte CF) : `cloudflared login`.

---

## 3. État actuel (au 2026-05-06)

### ✅ Déjà template-friendly
- Stack `docker-compose.yml` paramétrée par variables (host/domain/prefix/port)
- Reverse-proxy Caddy lit ses vhosts depuis `${KYKLOS_PREFIX}` / `${KYKLOS_DOMAIN}`
- `.env.example` couvre les 10 variables nécessaires
- Scripts `tunnel-up.sh` / `tunnel-down.sh` idempotents, édition par bloc marqué
- Pattern A (local-managed) verrouillé et documenté
- Postgres + n8n + NocoDB + Caddy + Uptime-Kuma fonctionnels

### ⚠️ Encore hardcodé / à template-iser
- `name: kyklos` dans compose → préfixe les **volumes** et les **containers** (`kyklos_postgres_data`, `kyklos-postgres-1`)
- Préfixe `KYKLOS_*` sur **toutes** les vars d'env (compose, Caddyfile, scripts, `.env.example`)
- Markers `# >>> kyklos-begin` / `# <<< kyklos-end` dans le YAML cloudflared (édité par tunnel-up.sh)
- Commentaires `.env.example` parlent de "Kyklos / Cloudflare Tunnel"
- Nom du dossier projet `kyklos-container/`

### 🚫 Manquant
- `scripts/spark-bootstrap.sh` (host setup automatisé) — la spec existe au §3.2 du doc archi mais n'est pas encore dans le repo
- `scripts/spark-new-site.sh` (helper création nouveau site)
- Stratégie backup (3-2-1 décrite §2.3 archi, aucun script)
- Tests / linting `.env` / health-check post-up
- Doc d'onboarding pour un nouveau site

---

## 4. Roadmap par phase

Phases ordonnées par dépendance. **On peut continuer à bosser sur le site `kyklos` pendant la majorité des phases** ; les seules à risque pour la prod sont 1+2 (rename + volumes), à faire ensemble.

### Phase 0 — Capture des décisions (ce document) ← **on est ici**

### Phase 1 — Rename in-place `kyklos` → `spark`
**Bloqué par Phase 2** (sinon perte des volumes Docker du déploiement live).

À faire dans le repo :
- [ ] `name: kyklos` → `name: spark` dans `docker-compose.yml`
- [ ] `KYKLOS_*` → `SPARK_*` dans `docker-compose.yml`, `config/Caddyfile`, `scripts/tunnel-*.sh`, `.env.example`, `.env`
- [ ] Markers `kyklos-begin/end` → `spark-begin/end` dans `scripts/tunnel-*.sh` (avec lecture tolérante des anciens markers le temps de la migration)
- [ ] Réécriture des commentaires `.env.example` et messages d'erreur des scripts en termes "Spark"
- [ ] (Optionnel) renommer le dossier `kyklos-container/` → `spark-container/` — impacte raccourcis shell + mémoires Claude (chemins absolus dans `~/.claude/projects/.../memory/`)

### Phase 2 — Volumes externes (déliaison données ↔ nom projet)
**Pourquoi** : `docker-compose` v2 préfixe les volumes nommés par `name:` du projet. Renommer `name: kyklos` → `name: spark` crée des volumes vides `spark_postgres_data` et orphelinise les données existantes.

Deux options, à trancher :
- **(a) `external: true` + nom littéral préservé** : on garde les volumes `kyklos_postgres_data` etc. en les déclarant externes. Zéro downtime, zéro migration de données. Le préfixe `kyklos_` traîne sur disque mais c'est cosmétique.
- **(b) Migration one-shot** via container alpine (`cp -a` de `/from` vers `/to`). Plus propre mais downtime + risque pendant la copie.

**Recommandation** : (a) maintenant pour débloquer Phase 1 sans risque. Faire (b) plus tard si on a besoin de propreté disque.

### Phase 3 — `scripts/spark-bootstrap.sh` (host setup)
Implémenter le script du §3.2 doc archi, **avec ces ajouts post-incident** :

- [ ] **Génération de secrets URL-safe** : alphabet `A-Za-z0-9-_` (32 chars) au lieu de `openssl rand -base64`. Raison : éviter les chars `&`/`=`/`+`/`/`/`%` qui cassent les configs URL-based (cf. mémoire `feedback-nocodb-nc-db-json.md` — incident 2026-05-05).
- [ ] **Sizing Colima adaptatif** : déjà décrit §3.2 archi (16+ GB → 6 GB Colima ; sinon 4 GB). Cf. mémoire `dev-mac-memory-constraints.md`.
- [ ] **Idempotence** : relançable, ne casse pas un `.env` existant.
- [ ] **Health-check final** : vérifie que les 4 services HTTP répondent.

### Phase 4 — `scripts/spark-new-site.sh`
`./scripts/spark-new-site.sh <site> <domain> [<tunnel-config-path>]`
- Création tunnel : `cloudflared tunnel create spark-<site>`
- Génération `.env` : `SPARK_PREFIX=<site>`, `SPARK_DOMAIN=<domain>`, `SPARK_TUNNEL_ID=<uuid>` + secrets via fonction Phase 3
- Lance `tunnel-up.sh` → routes + CNAMEs créées
- Lance `docker-compose up -d`

Pré-requis manuel à conserver : `cloudflared login` interactif (1× par compte CF, génère le `cert.pem`).

### Phase 5 — Distribution
À trancher :
- **GitHub template repo** (`gh repo create --template spark-template`) — simple, git-natif.
- **Branch `template` du repo actuel** — un seul lieu, mais mélange code de site et code de template.
- **Cookiecutter / copier** — vraie templatification avec substitution de variables. Surdimensionné si `<prefix>-<service>` couvre déjà 95 % des cas.

**Préférence faible** : GitHub template repo séparé, alimenté par un `git subtree push` depuis le repo de site, avec scripts de promotion.

---

## 5. Décisions déjà figées (à ne pas re-débattre)

| Décision | Source / Raison |
|---|---|
| **NocoDB via `NC_DB_JSON`, pas `NC_DB`** | mémoire `feedback-nocodb-nc-db-json.md`. URL-decode sur password = crashloop si chars spéciaux. Incident 2026-05-05. |
| **Cloudflare Tunnel pattern A** (local-managed YAML) | doc archi §3.3. Évite saturation dashboard CF sur N sites. |
| **Single-level subdomain** `<prefix>-<service>.<domain>` | doc archi §3.3. Universal SSL gratuit ne couvre pas wildcard 2-niveaux. |
| **Postgres unique** partagée n8n + NocoDB | doc archi §2.3. Une `pg_dumpall` couvre tout. |
| **Caddy `tls internal`** (LAN) + CF (public) | doc archi §4.2. Pas d'exposition directe internet. |
| **`X-Forwarded-Proto https` forcé** côté Caddy + `N8N_PROXY_HOPS=2` | doc archi §3.3 (trust de proxy chain). Sinon n8n refuse les cookies sécurisés. |
| **Secrets : alphabet URL-safe `A-Za-z0-9-_`** | leçon incident NocoDB. À enforcer dans bootstrap. |
| **Colima sizing adaptatif au host** | doc archi §1.3. 8GB → 4 GiB ; 16GB+ → 6+ GiB. |
| **Volumes Docker nommés** (pas de bind-mounts pour data) | implicite docker-compose actuel. Backup unifiée. |
| **`SPARK_PREFIX` ≠ "Spark"** | la kit s'appelle Spark, le préfixe par-site est libre (kyklos pour ce site). On ne renommera **pas** la valeur runtime en Phase 1. |

---

## 6. Questions ouvertes

- [ ] **Multi-tenant local** : un Mac peut-il héberger plusieurs sites Spark (n sites = n stacks) ? Si oui : `SPARK_HOST_HTTP_PORT` doit varier, et `name:` compose doit inclure le site (`name: spark-<site>`). Mon avis : *non* par défaut (1 Mac = 1 site, c'est l'esprit usine), mais à confirmer.
- [ ] **Périmètre backup dans la template** : on inclut les scripts `pg_dumpall` + `rclone` du §2.3 archi, ou on laisse au site ?
- [ ] **Versioning n8n workflows** : §5.3 archi flagué "provisoire" (Git local + push GitHub privé). À figer avant Phase 4 ?
- [ ] **`KYKLOS_PREFIX=kyklos` reste-t-il la valeur de ce site ?** Si on veut migrer les URLs vers `spark-*.usine.io` un jour, c'est un chantier séparé (DNS CF + bookmarks + WEBHOOK_URL). Hors scope template.
- [ ] **Repo `spark-template` séparé vs branche** : voir Phase 5.

---

## 7. Journal des modifications

| Date | Phase | Action |
|---|---|---|
| 2026-05-06 | 0 | Création de ce document |
| 2026-05-06 | 0 | Création de `INCIDENTS.md` + archive INC-2026-05-05 (NocoDB / `NC_DB_JSON`) et incident wiki Colima sizing |
