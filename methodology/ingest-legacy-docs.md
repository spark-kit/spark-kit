# Ingest legacy docs — produire une fiche-logiciel

> Procédure pour ingérer la documentation d'un logiciel legacy d'un client et produire une **fiche-logiciel** structurée, prête à alimenter un PRD POC.
>
> **Une fiche par logiciel.** Vit dans `<repo-site>/discovery/fiches/<soft-slug>.md`, **pas** dans spark-kit (parce que volumes, owners, contraintes contractuelles dépendent du client).

---

## 1. Quand ouvrir une fiche-logiciel

Dès que la **Phase 0 ou 1 du questionnaire d'onboarding** (cf. `wiki/topics/questionnaire-onboarding.md`) identifie un logiciel candidat à être branché par n8n.

Ne pas ingérer **tous** les logiciels du client — seulement ceux qui ont :
- une intégration prévisible dans un POC Phase 1 ou 2 (court terme)
- ou un risque de blocage (ex: ERP fermé sans API qu'on devra contourner)

Garder l'inventaire brut (sans fiches détaillées) dans le rapport d'onboarding pour les autres.

---

## 2. Sources possibles, par niveau d'effort

À collecter dans cet ordre, **en s'arrêtant dès qu'on a "assez"** pour rédiger un PRD. Mieux vaut une fiche à 70 % qui débloque un PRD que 100 % qui retarde tout.

### Niveau 1 — gratuit, rapide *(toujours faire)*
- [ ] Page d'accueil + page "API" / "Developers" / "Intégrations" du site éditeur
- [ ] Documentation publique (Swagger / OpenAPI / Postman collection / docs Markdown)
- [ ] Status page (uptime, incidents historiques, fenêtres de maintenance régulières)
- [ ] Page de pricing (cache parfois les rate limits ou scopes payants)
- [ ] GitHub de l'éditeur si SDK / collections publiques

### Niveau 2 — accès UI client *(souvent oublié, très rentable)*
- [ ] Capture du schéma de données via UI admin (export, vue admin, listes de tables)
- [ ] Exports CSV / Excel d'échantillons réels (anonymisés si sensibles)
- [ ] Captures d'écran du parcours utilisateur (les écrans qu'on remplacera ou que n8n alimentera)
- [ ] Mails d'onboarding ou de support contenant des explications sur des cas limites
- [ ] Inspection navigateur (DevTools → Network) pendant un parcours utilisateur typique : révèle les calls XHR utilisés par le SaaS lui-même, parfois plus complets que la doc API publique

### Niveau 3 — dialogue avec l'éditeur
- [ ] Demande d'accès à la doc API privée (SaaS B2B fournissent souvent une doc plus riche aux comptes payants)
- [ ] Email/ticket support avec une question test ("est-ce qu'il existe un webhook sur événement X ?")
- [ ] LinkedIn de l'éditeur si France/Europe : identifier un product owner, lui poser une question publique (souvent répond)

### Niveau 4 — tests live *(avec accord du client)*
- [ ] Token API du client + 1 appel test en lecture seule, **jamais en écriture sans validation explicite**
- [ ] Si on a l'accord : pointer un webhook configurable du logiciel sur un endpoint de test n8n pour capturer 1 vrai payload (puis débrancher tout de suite)
- [ ] Charger un export CSV dans NocoDB en local pour mesurer le volume et la propreté des données

---

## 3. Structure de la fiche-logiciel

Format Markdown, 1 fichier = 1 logiciel, slug stable (`phone-check.md`, pas `phonecheck-v2.md`).

### Frontmatter

```yaml
---
software: "{{Nom commercial}}"
editor: "{{Éditeur (entreprise)}}"
category: "{{CRM | ERP | WMS | Compta | Diag | Sheets | Custom}}"
client_site: "{{kyklos | acme | ...}}"
date_ingested: "{{YYYY-MM-DD}}"
ingested_by: "{{Atelier B - prénom}}"
status: "{{ingest-en-cours | complete | rebloqué}}"
integration_verdict: "{{open | partial | closed}}"   # rouge/orange/vert de la 3.4
---
```

### Sections obligatoires

#### 3.1 Identité
- Nom commercial, éditeur
- Version utilisée (si auto-hosted) ou date d'observation (si SaaS)
- Hébergement : SaaS / on-premise / hybride
- Langue de la doc (fr / en / autre)
- Site web officiel + lien vers la doc API

#### 3.2 Fonction métier
En 3 phrases : que fait-il pour le client, qui s'en sert, à quelle fréquence.

#### 3.3 Modèle de données
- Entités principales (≤ 10) avec leur identifiant stable
- Relations entre entités (1-n, n-n)
- Champs critiques (qui sont les "clés business" : IMEI, SKU, n° commande, n° facture...)

#### 3.4 Surface d'intégration

**API** :
- REST / GraphQL / SOAP / propriétaire
- Auth : token / OAuth2 / Basic / cookie de session / propriétaire
- Scopes / permissions (en lecture seule possible ?)
- Versioning / stabilité

**Webhooks sortants** :
- Événements disponibles (liste)
- Format payload (JSON / XML / form-data)
- Configurables par le client ou via API ?
- Retry policy de l'éditeur (à savoir absolument)

**Exports** :
- CSV / JSON / XLSX ?
- Accessibles via UI seule ou via API/URL signée ?
- Fréquence possible (à la demande ? planifiable ?)

**Imports / écritures** :
- API d'écriture ? Webhooks entrants ? UI seule ?

**Verdict d'intégration** *(remonter dans le frontmatter `integration_verdict`)* :
- 🟢 **open** : API ouverte avec scope lecture/écriture, doc claire, auth standard
- 🟡 **partial** : exports CSV ou API en lecture seule ; on peut faire du polling/import
- 🔴 **closed** : aucune sortie de données ; il faudra contourner (NocoDB devient source pour le nouveau processus)

#### 3.5 Volumes observés
- Lignes en base actuellement (ordre de grandeur)
- Requêtes/jour estimées si polling
- Fréquence des changements de données métier

#### 3.6 Contraintes
- Rate limit (req/sec ou /min — souvent dans la doc, parfois empirique)
- ToS / restrictions d'usage automatisé (certains SaaS interdisent contractuellement le scraping/automation)
- Coûts par appel ou plan d'abonnement à respecter pour ne pas faire exploser la facture client

#### 3.7 Owners côté client
- Qui sait s'en servir
- Qui détient les credentials API / accès admin
- Qui paie l'abonnement (≠ qui s'en sert souvent)

#### 3.8 Risques d'intégration
Verrous techniques, légaux ou humains qui peuvent bloquer le POC. Au moins **un** risque listé — si on n'en voit aucun, c'est qu'on n'a pas creusé assez.

#### 3.9 Hypothèses non vérifiées
Tout ce qu'on suppose mais qu'on n'a pas confirmé empiriquement. À confirmer avant qu'un PRD POC s'appuie dessus.

### Sections optionnelles

- Captures pertinentes (écrans, schémas)
- Liens vers exemples concrets : payload webhook anonymisé, export CSV échantillon, call API exemple
- Notes côté éditeur (qualité support, réactivité, communauté)

---

## 4. Checklist de clôture

Avant de marquer `status: complete` :

- [ ] J'ai au moins **1 chemin viable** d'intégration (lecture, écriture, ou les deux)
- [ ] L'auth est documentée : type, scopes, qui détient le secret côté client
- [ ] J'ai au moins **un exemple concret** de payload (CSV, JSON webhook, ou call API)
- [ ] Les volumes ont un ordre de grandeur (même approximatif)
- [ ] Les owners sont nommés (pas "le service IT" en général)
- [ ] Le verdict d'intégration est arbitré (🟢/🟡/🔴) et reporté dans le frontmatter
- [ ] J'ai listé au moins **un risque** ou hypothèse

Si bloqué : `status: rebloqué` + lister les questions ouvertes en haut du fichier. Ne pas attendre la perfection pour committer la fiche — on travaille en draft.

---

## 5. Quand passer à un PRD POC

Une fiche-logiciel **n'est pas** un PRD. C'est une **input** pour rédiger un PRD POC (cf. [`prd-template.md`](prd-template.md)).

On ouvre un PRD POC quand :
- On a au moins **1 fiche complète** sur le ou les logiciels touchés (au moins une à 🟢 ou 🟡 dans la chaîne)
- Le pain client correspondant est identifié (cf. questionnaire onboarding Q0.4 / Q1.x / Q3.x)
- Le niveau Spark visé est arbitré (cf. niveaux 1-7 du manifeste)

Si on doute, mieux vaut écrire le PRD en `draft` avec des trous explicites (`{{TBD : confirmer rate limit}}`) que d'attendre indéfiniment la fiche parfaite. Le PRD pousse parfois à creuser la fiche.

---

## 6. Réutilisation entre clients

Une fiche-logiciel est **spécifique au client** (volumes, owners, contraintes contractuelles). Mais des éléments **transverses** peuvent émerger :

- *"Pennylane API v1 a un rate limit de 60 req/min"* → vrai pour tous les clients Pennylane
- *"Pennylane n'expose pas les écritures futures par webhook, il faut polling"* → idem

Quand un fait transverse émerge, le promouvoir vers :
- `spark-kit/playbooks/<software>/` si on construit une brique d'intégration spécifique réutilisable *(chantier A)*
- ou `spark-kit/methodology/legacy-knowledge.md` (notes croisées sur les éditeurs courants — fichier à créer dès qu'il y a 2-3 faits à mettre dedans, pas avant)

> Ces deux structures n'existent pas encore. Elles émergeront naturellement après les 2-3 premiers clients.

---

## 7. Anti-patterns à éviter

- **Tout ingérer avant de faire quoi que ce soit** : on prend 3 semaines à étudier 12 logiciels, le client trouve qu'on glande. Stratégie : 1 logiciel suffisant pour 1 POC > 12 logiciels parfaitement documentés.
- **Recopier la doc de l'éditeur dans la fiche** : la fiche est une **distillation client-spécifique**, pas une copie. Lien vers la doc, mention de ce qui s'applique au cas précis du client.
- **Oublier les niveaux 2 et 4** (UI client + tests live). C'est là que sortent les vraies surprises (rate limits, formats incohérents, champs custom).
- **Démarrer un PRD sans aucune fiche** : on rédige des suppositions, on les valide sur le tard, on découvre que l'API ne fait pas ce qu'on croyait. Toujours au moins une fiche en input.

---

*Procédure v1.0 (2026-05-06). À enrichir après chaque ingest réelle (ajouter sources rencontrées, anti-patterns observés).*
