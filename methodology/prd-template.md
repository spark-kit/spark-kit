# Template PRD — POC Spark client

> Gabarit fillable pour rédiger un PRD de POC Spark à déployer chez un client.
> **Usage** : copier ce fichier vers `<repo-site>/discovery/prds/prd-NNN-<slug>.md`, puis remplir les `{{placeholders}}`.
> Les sections marquées *(facultatif)* peuvent être omises sur un POC trivial — mais expliquer pourquoi en haut du document.
> Inspiré du PRD bien structuré `wiki/topics/veille-prd.md`. Lire avant rédaction : `wiki/topics/manifeste-spark.md` (vision, niveaux 1-7) et la ou les fiches-logiciel des systèmes touchés (`discovery/fiches/*.md`).

---

```markdown
---
title: "PRD POC — {{Nom court du POC}}"
client: "{{Nom du client}}"
site: "{{site/prefix Spark, ex: kyklos}}"
tags: [prd, poc, niveau-{{N}}, {{domaine: wms|erp|cs|integration|tracabilite|...}}]
date: {{YYYY-MM-DD}}
status: draft  # draft | review | approved | implementing | live | retired
version: 0.1
owner: "{{Atelier B - prénom}}"
champion: "{{prénom du champion interne client}}"
---

# PRD POC — {{Nom du POC}}

> Spec courte (3-10 pages) d'un POC Spark à construire pour {{client}}.

---

## 1. Contexte et objectif

### 1.1 Le client en 3 lignes
- **Activité** : {{ex: reconditionnement smartphones, 25 personnes, 3000 unités/mois}}
- **Pain ciblé** : {{ex: copier-coller IMEI entre Phone Check et Google Sheets, ~2h/jour perdues}}
- **Niveau Spark visé** : niveau {{N}} ({{nom du niveau, cf. manifeste-spark §"niveaux d'intervention"}})

### 1.2 Objectif du POC en 1 phrase
{{Une seule phrase. Si elle dépasse 25 mots, le POC est trop large — découper en plusieurs PRD.}}

### 1.3 Pourquoi maintenant
{{Trigger métier : montée en charge, nouveau client, perte mesurée, compliance, échéance externe...}}

---

## 2. Périmètre

### Dans le périmètre (v1)
- {{...}}
- {{...}}

### Hors périmètre (v1)
- {{...}}
- {{...}}

> Discipline anti-scope-creep : tout ce qui n'est pas listé "in" est traité comme "out", même si "ce serait bien". On ouvre une v2 si le besoin se confirme après 2-4 semaines de run.

---

## 3. Sources de vérité et flux de données

> ⚠️ Rappel archi (cf. spark-kit/README §2.2) : les sources de vérité business sont **les systèmes métier du client**. NocoDB est staging / nouvelle source pour des données qui n'existaient nulle part. n8n est le bridge contrôlé.

### 3.1 Systèmes métier touchés (sources de vérité business)

| Système | Rôle métier | Surface d'intégration | Direction du flux | Fiche |
|---|---|---|---|---|
| {{ex: Phone Check}} | {{diagnostic phones}} | {{webhook sortant JSON}} | legacy → Spark | `discovery/fiches/phone-check.md` |
| {{ex: Google Sheets ERP}} | {{ERP de fortune}} | {{Sheets API v4}} | bidirectionnel | `discovery/fiches/google-sheets-erp.md` |

### 3.2 Surface NocoDB (staging / écrans côté Spark)

**Tables nouvelles ou modifiées** :

| Table | Type | Rôle |
|---|---|---|
| {{ex: phones_diag}} | nouvelle | {{cache des résultats Phone Check, append-only}} |
| {{ex: phones_state}} | nouvelle | {{état courant + historique par IMEI}} |

**Vues / écrans** :
- {{ex: Vue "À traiter aujourd'hui" — filtre statut=pending, ordre=date}}
- {{ex: Écran tablette poste réception — formulaire de scan IMEI + résumé}}

### 3.3 Workflows n8n (high-level)

| Workflow | Trigger | Action | Brique playbook |
|---|---|---|---|
| {{ex: phone-check-ingest}} | {{webhook Phone Check}} | {{INSERT NocoDB phones_diag + UPDATE phones_state}} | `n8n-webhook-in` + `n8n-nocodb-bridge` *(chantier A — à créer)* |

> Détailler en pseudo-code uniquement à l'échelle qui sert la décision archi. L'implémentation détaillée ne va pas dans le PRD — elle vit dans le repo de site (workflows n8n exportés JSON, scripts).

---

## 4. Utilisateurs et rôles

| Rôle | Personnes | Action attendue | Surface |
|---|---|---|---|
| {{ex: Opérateur réception}} | {{3 techniciens}} | {{scanner les IMEI à l'arrivée}} | {{tablette → écran NocoDB form}} |
| {{ex: Chef d'atelier}} | {{Cédric}} | {{voir le pipeline de la journée}} | {{vue "Aujourd'hui"}} |
| {{ex: Direction}} | {{dirigeant}} | {{stats hebdo}} | {{vue analytics}} |

---

## 5. Critères de succès

### 5.1 KPIs mesurables
*(s'inspirer de Q3.5 du questionnaire onboarding)*

- {{ex: temps gagné par jour : objectif 1h30, mesuré par chrono champion semaine 1 et semaine 4}}
- {{ex: élimination du copier-coller : 0 saisie manuelle sur ≥ 95 % des cas mesurés}}
- {{ex: latence event → NocoDB visible : < 30 s sur 99e percentile}}

### 5.2 Critères qualitatifs
- {{ex: champion interne dit "je gagne du temps" sans qu'on le sollicite}}
- {{ex: zéro escalade IT en 4 semaines de run}}

---

## 6. Contraintes non-fonctionnelles

| Contrainte | Cible | Mesure |
|---|---|---|
| Volume {{event/jour}} | {{ex: ≤ 200}} | {{logs n8n}} |
| Latence | {{ex: < 30s p99}} | {{Uptime Kuma + n8n exec time}} |
| Fenêtre de maintenance | {{ex: nuit + WE}} | {{accord avec champion}} |
| Disponibilité | {{ex: heures ouvrées 7h-18h, lundi-vendredi}} | {{monitoring}} |

---

## 7. Sécurité et confidentialité

- **Données sensibles touchées** : {{ex: IMEI = identifiants techniques, pas perso. RGPD : N/A pour ce POC}}
- **Stockage** : LAN-only, NocoDB sur Spark Mac Mini, pas de cloud externe
- **Auth/secrets côté Spark** : credentials chiffrés via `N8N_ENCRYPTION_KEY` (cf. archi-technique §4.1)
- **Auth côté legacy** : {{ex: token API Phone Check, scope minimal lecture, rotation manuelle tous les 6 mois}}
- **Backup** : couvert par la stratégie 3-2-1 du site (cf. archi-technique §2.3)

---

## 8. Risques et hypothèses

| # | Risque / Hypothèse | Probabilité | Impact | Mitigation |
|---|---|---|---|---|
| R1 | {{ex: Phone Check change son format webhook sans préavis}} | basse | haut | {{tests automatiques sur structure de payload, alerte Kuma}} |
| R2 | {{ex: réseau Wi-Fi sature pendant les pics de réception}} | moyenne | moyen | {{cf. archi §1.5, switch + IP fixe + Ethernet pour le poste atelier}} |
| H1 | {{Hypothèse : champion dispo 2h/sem pour valider}} | — | — | {{si fausse → POC mort, escalade direction}} |

---

## 9. Plan d'implémentation

### 9.1 Briques playbooks utilisées

- {{`n8n-webhook-in`}} *(chantier A — à créer)*
- {{`n8n-nocodb-bridge`}} *(chantier A — à créer)*
- {{...}}

### 9.2 Étapes

| # | Étape | Durée | Livrable | Owner |
|---|---|---|---|---|
| 1 | {{Setup credentials Phone Check côté n8n}} | {{30 min}} | {{credential vault entry}} | {{Atelier B}} |
| 2 | {{Création tables NocoDB}} | {{1h}} | {{schéma + données fictives}} | {{Atelier B}} |
| 3 | {{Workflow n8n ingest}} | {{2h}} | {{flow JSON exporté + commité}} | {{Atelier B}} |
| 4 | {{Test bout-en-bout avec champion}} | {{1h}} | {{validation sur 5 cas réels}} | {{champion + Atelier B}} |
| 5 | {{Mise en service + monitoring 1 semaine}} | {{1 sem}} | {{rapport hebdo + ajustements}} | {{champion}} |

### 9.3 Durée totale estimée
{{ex: ~1 jour de dev + 1 semaine de monitoring}}

---

## 10. Décisions ouvertes

| # | Décision | Options | Échéance |
|---|---|---|---|
| 1 | {{ex: format de phones_diag : 1 ligne par diag ou 1 ligne par phone avec dernière diag ?}} | a / b | {{avant étape 2}} |

---

## 11. Annexes

### Sources documentaires
- Rapport d'onboarding : {{lien interne, ex: `discovery/onboarding/visite-2026-MM-DD.md`}}
- Fiches-logiciel : `discovery/fiches/{{...}}.md`
- Manifeste & archi : `wiki/topics/manifeste-spark.md`, `wiki/topics/architecture-technique.md`

### Glossaire client *(facultatif)*
- {{IMEI}} : {{International Mobile Equipment Identity, identifiant unique téléphone}}

---

*PRD v0.1 rédigé le {{YYYY-MM-DD}}. À réviser après chaque jalon (`approved`, `implementing`, `live`).*
```

---

## Notes pour le rédacteur

- **Numéro PRD** : 3 chiffres incrémental par-site (`prd-001`, `prd-002`...). Le numéro reste figé même si le statut évolue.
- **Si le POC est trivial** (<2h dev, 1 brique, 1 utilisateur) : un PRD ultra-court à 4 sections (1, 2, 5, 9) suffit. Plutôt qu'éliminer la spec, on la compresse.
- **Si le POC mute en gros chantier** : ne pas étendre le PRD, en ouvrir un nouveau (`prd-NNN+1-<sous-slug>`) qui référence le précédent. Le PRD original est figé.
- **Statuts** : `draft` (rédaction) → `review` (relu champion + Atelier B) → `approved` (go pour implémenter) → `implementing` (en cours) → `live` (en prod, monitoring) → `retired` (POC arrêté ou remplacé).
