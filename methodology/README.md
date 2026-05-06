# Spark Methodology — Pipeline ingest → PRD → POC

> **Chantier B** de spark-kit : flux méthodologique pour transformer la découverte d'un client en POC déployable.
>
> Ce dossier contient les **gabarits et procédures réutilisables**. Les **instances** (fiches-logiciel d'un client donné, PRD POC d'un projet précis) vivent dans le repo du site client (ex: `kyklos-container/discovery/`), pas ici.

---

## Vue d'ensemble du pipeline

```
[wiki Spark]                           [par-site, repo client]                [spark-kit]

questionnaire-onboarding   ────►   discovery/fiches/<soft>.md   ◄────  ingest-legacy-docs.md
(découverte client,                  (1 fiche par logiciel                  (gabarit + checklist)
 déjà existant)                       legacy touché)
                                            │
                                            ▼
                                   discovery/prds/prd-<NNN>-<slug>.md   ◄──  prd-template.md
                                   (1 PRD par POC envisagé)                  (gabarit PRD)
                                            │
                                            ▼
                                   POC implémenté (n8n flows,    ◄────  poc-from-prd.md
                                   tables NocoDB, écrans...)              (à venir — chantier A
                                            │                              en dépendance)
                                            ▼
                                   Déployé chez le client
                                   → boucle d'itération
```

---

## Fichiers de ce dossier

| Fichier | Rôle |
|---|---|
| [`ingest-legacy-docs.md`](ingest-legacy-docs.md) | Procédure pour ingérer la doc d'un logiciel legacy → produire une fiche-logiciel structurée |
| [`prd-template.md`](prd-template.md) | Template du PRD pour un POC Spark client (inspiré de `wiki/topics/veille-prd.md`) |
| `poc-from-prd.md` *(à venir)* | Du PRD → assemblage de playbooks → implémentation. Dépend du chantier A (`spark-kit/playbooks/` qui n'existe pas encore). |

---

## Articulation avec le reste de l'écosystème Spark

| Brique | Vit où | Statut |
|---|---|---|
| Manifeste (vision, niveaux 1-7, thèse IA) | `wiki/topics/manifeste-spark.md` | ✅ |
| Architecture technique kit | `wiki/topics/architecture-technique.md` | ✅ |
| Questionnaire onboarding (3 phases) | `wiki/topics/questionnaire-onboarding.md` | ✅ |
| PRD veille (modèle de PRD bien structuré) | `wiki/topics/veille-prd.md` | ✅ (inspirateur de `prd-template.md`) |
| Patterns d'intégration réutilisables | `spark-kit/playbooks/` (chantier A) | 🚫 vide |
| **Pipeline méthodologique** | **`spark-kit/methodology/` (ce dossier — chantier B)** | 🟡 en construction |
| Outillage Claude (MCP n8n, skill NocoDB) | `spark-kit/skills/`, `spark-kit/mcp/` (chantier C) | 🚫 vide |
| Fiches-logiciel et PRD POC d'un client | `<repo-site>/discovery/` | par-site (à instancier) |

**Règle** : ne pas dupliquer le contenu des docs wiki ici. Référencer.

---

## Convention de structure par-site (à instancier)

À la racine du repo de chaque site (ex: `kyklos-container/`), prévoir un dossier `discovery/` :

```
discovery/
├── onboarding/
│   └── visite-YYYY-MM-DD.md         # rapport de visite, sortie du questionnaire
├── fiches/                          # une fiche par logiciel legacy étudié
│   ├── phone-check.md
│   ├── google-sheets-erp.md
│   └── pennylane.md
└── prds/                            # une PRD par POC envisagé
    ├── prd-001-phone-check-to-noco.md
    └── prd-002-stock-traceability.md
```

> Cette convention n'est **pas** appliquée tout de suite sur `kyklos-container`. À matérialiser lorsqu'on attaque un POC concret pour kyklos.

---

## Comment utiliser ce dossier

1. **Premier contact client** → utiliser `wiki/topics/questionnaire-onboarding.md` (déjà existant côté wiki Spark). Sortie : un rapport de visite client.
2. **Identification d'un logiciel à brancher** → ouvrir une fiche en suivant `ingest-legacy-docs.md`. Sortie : `<repo-site>/discovery/fiches/<soft>.md`.
3. **Cadrage d'un POC** → rédiger un PRD en suivant `prd-template.md`. Sortie : `<repo-site>/discovery/prds/prd-NNN-<slug>.md`.
4. **Implémentation** → assembler des briques playbook (chantier A, à construire). Sortie : workflows n8n + tables NocoDB + écrans + déploiement.

---

*Procédure v1.0 (2026-05-06). À itérer après le 1er POC client réel.*
