# Spark Kit — Archive des incidents

> Chaque fail rencontré sur un déploiement Spark (`kyklos` aujourd'hui, autres demain) est archivé ici.
> But : éviter qu'un nouveau site rencontre deux fois le même piège, et nourrir la check-list du bootstrap.
>
> Format par incident : symptôme → diagnostic (avec commandes utiles) → cause racine → fix immédiat → fix structurel → leçons exploitables (cases à cocher dans le code).

---

## INC-2026-05-05 — NocoDB crashloop, 502 sur `kyklos-db.usine.io`

**Site** : kyklos / usine.io
**Sévérité** : medium (1 service public KO, autres services OK)
**Statut** : ✅ résolu — mitigé structurellement (`NC_DB_JSON` + alphabet secret URL-safe à enforcer)

### Symptôme
- `https://kyklos-db.usine.io/` répond `HTTP 502` (Caddy ne joint pas l'upstream)
- `docker-compose ps` : `kyklos-nocodb-1   Restarting (1) X seconds ago`, en boucle ~60 s
- Trois autres services (n8n, postgres, kuma) : OK

### Diagnostic
```bash
docker logs kyklos-nocodb-1 --tail 80
# → "error: password authentication failed for user \"nocodb\"" (PG code 28P01)
```

Le rôle existe pourtant côté Postgres :
```bash
docker exec kyklos-postgres-1 psql -U postgres -tAc \
  "SELECT rolname FROM pg_roles WHERE rolname IN ('nocodb','n8n');"
# → n8n / nocodb (les deux existent)
```

Test direct de l'auth `nocodb` avec le password du `.env` (depuis l'intérieur du container postgres pour ne pas exposer le secret) :
```bash
docker exec kyklos-postgres-1 bash -c \
  'PGPASSWORD="$NOCODB_DB_PASSWORD" psql -h 127.0.0.1 -U nocodb -d nocodb -tAc "SELECT 1;"'
# → 1   (auth OK avec le password brut !)
```

Donc le password du `.env` est correct côté Postgres, mais NocoDB envoie autre chose. Test du contenu :
```bash
docker exec kyklos-postgres-1 bash -c 'echo -n "$NOCODB_DB_PASSWORD" | tr -dc "&=+%/?# " | wc -c'
# → 4   (4 caractères URL-spéciaux dans le password)
```

### Cause racine
**Combinaison de deux problèmes** :

1. La conf NocoDB utilisait le format URL `NC_DB="pg://postgres:5432?u=nocodb&p=${NOCODB_DB_PASSWORD}&d=nocodb"` — qui **URL-décode** le password avant de l'envoyer à Postgres.
2. `openssl rand -base64 24` (utilisé pour générer `NOCODB_DB_PASSWORD`) peut produire des caractères URL-spéciaux (`&`, `=`, `+`, `/`, `%`...). Cette fois-ci, 4 d'entre eux étaient présents.

Résultat : Postgres reçoit un password tronqué/déformé après URL-decode → `password authentication failed`. n8n n'était pas affecté parce qu'il prend le password en env var directe (`DB_POSTGRESDB_PASSWORD`), pas via URL.

**Facteur aggravant** : `init-db.sh` ne s'exécute **qu'au tout premier démarrage du volume `postgres_data`** (vide). Si le `.env` est régénéré après coup, le rôle `nocodb` côté Postgres garde son ancien password — drift silencieux.

### Fix immédiat
1. Resynchroniser le password du rôle Postgres avec celui du `.env`, **sans exposer le secret côté host** (utiliser l'env var déjà présente dans le container postgres) :
   ```bash
   docker exec kyklos-postgres-1 bash -c '
     printf "ALTER USER nocodb WITH ENCRYPTED PASSWORD '\''%s'\'';\n" "$NOCODB_DB_PASSWORD" \
     | psql -U postgres -v ON_ERROR_STOP=1
   '
   ```
2. ⚠️ À ce stade, NocoDB crashait encore — le password aligné côté PG ne suffisait pas, parce que NocoDB continuait à URL-décoder.

### Fix structurel
Remplacement de `NC_DB` (URL) par `NC_DB_JSON` (objet JSON, pas de URL-decode) dans `docker-compose.yml` :
```yaml
NC_DB_JSON: '{"client":"pg","connection":{"host":"postgres","port":5432,"user":"nocodb","password":"${NOCODB_DB_PASSWORD}","database":"nocodb"}}'
```
→ `docker-compose up -d nocodb` → `App started successfully` → `https://kyklos-db.usine.io` répond 200.

### Leçons exploitables (à porter dans Spark)

- [ ] **Bootstrap** (Phase 3) : générer les secrets avec un alphabet **URL-safe ET JSON-safe** : `tr -dc 'A-Za-z0-9-_' </dev/urandom | head -c 32`. Bannir `openssl rand -base64` pour tout secret destiné à transiter dans un endroit qui pourrait l'interpréter (URL, JSON inline, query string).
- [ ] **Compose template** : pour toute conf passant par une URL (`NC_DB`, `DATABASE_URL`, `REDIS_URL`...), préférer le format objet quand l'app le supporte. Si pas le choix, URL-encoder explicitement le password.
- [ ] **Bootstrap health-check** (Phase 3) : ne pas se contenter de `docker-compose up -d --wait`. Tester l'auth applicative **réelle** de chaque service vers sa base après le up, pas juste l'existence du rôle.
- [ ] **Doc opérateur** : si on régénère un password dans `.env` après le 1er boot, il faut **explicitement** un `ALTER USER` côté Postgres — `init-db.sh` ne se rejouera jamais. À documenter dans une procédure "rotation de secrets".
- [ ] **Diag rapide à préserver** : la commande `printf '%s' "$X" | tr -dc "&=+%/?# " | wc -c` est utile pour traquer ce genre de bug sans exposer la valeur. Garder ce pattern dans les runbooks.

### Temps réel
- Détection → diagnostic complet : ~5 min (logs explicites)
- Diagnostic → fix immédiat : ~2 min (mais insuffisant)
- Fix immédiat → fix structurel : ~5 min (`NC_DB_JSON`)
- **Total** : ~15 min — court parce que les logs Postgres étaient lisibles. Sans ça (ex: si Caddy avait masqué le 502 derrière un retry), aurait pu durer beaucoup plus.

---

## INC-(antérieur, capturé dans le wiki) — Containers Spark exit code 0 / restart loop ~60s

**Source** : `spark-vault/wiki/topics/architecture-technique.md` §1.3 ("Symptômes d'un Colima sous-dimensionné")
**Statut** : ✅ leçon déjà intégrée au sizing Colima du bootstrap (à coder en Phase 3)

### Symptôme (synthèse du wiki)
- Containers exit avec **code 0** (pas 137/OOM) et restartent en boucle ~60 s, sans stack trace
- n8n logs : `Last session crashed` répété, `Task runner connection attempt failed with status code 403`
- Postgres logs : `Database connection timed out` puis `recovered` cycliques, `Connection reset by peer`
- `OOMKilled=false` partout — masque la vraie cause

### Cause racine
Colima VM sous-dimensionnée : sur un host 8 GB unified avec LLM local concurrent (Ollama 7B ≈ 5 GB working set) + macOS + apps, il restait < 2 GiB pour la VM Colima. Le kernel-OOM-killer cible les sous-processus enfants (le runner n8n, le client Postgres...) plutôt que le container parent → exit 0 silencieux.

### Diag rapide
```bash
docker run --rm alpine free -h
# Si "available" < 200 MB côté VM Colima → c'est la mémoire.
```

### Fix
```bash
colima stop
colima start --cpu N --memory G --disk 100
# unless-stopped relance les containers tout seul
```

### Leçons exploitables (à porter dans Spark)
- [ ] **Bootstrap** (Phase 3) : sizing adaptatif au host. 16+ GB → 6 GB Colima. 8 GB → 4 GB max. (Déjà spécifié §3.2 archi.)
- [ ] **Doc opérateur** : Spark productif **incompatible** avec un host < 16 GB qui fait tourner un LLM local concurrent. À mettre dans le pré-requis du `spark-new-site.sh`.
- [ ] **Diag** : `docker run --rm alpine free -h` doit être le **premier réflexe** face à un crashloop sans stack trace. À mettre en commentaire dans `spark-bootstrap.sh` et runbook.

---

## Template d'incident (à copier pour les prochains)

```markdown
## INC-YYYY-MM-DD — <titre court>

**Site** : <site> / <domain>
**Sévérité** : low / medium / high / critical
**Statut** : 🔴 ouvert / 🟡 mitigé / ✅ résolu

### Symptôme
<ce qu'on voyait depuis l'extérieur>

### Diagnostic
<commandes utilisées, dans l'ordre, avec leur output significatif>

### Cause racine
<la vraie cause — pas le symptôme déguisé en cause>

### Fix immédiat
<ce qui a remis le service en route>

### Fix structurel
<ce qui empêche la récurrence>

### Leçons exploitables (à porter dans Spark)
- [ ] action concrète sur le code/bootstrap/doc
- [ ] ...

### Temps réel
<détection → résolution>
```
