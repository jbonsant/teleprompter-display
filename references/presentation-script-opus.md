# Script de présentation — GPSN — Université Laval

**Durée :** 60 min contenu + 30 min questions
**Présentateur :** Jeremie Bonsant, Webisoft Technologie Inc.

---

## Ouverture (~1 min)

Merci de nous recevoir. Je suis Jeremie Bonsant, fondateur de Webisoft.

- Aujourd'hui : 6 sujets en 60 minutes, puis vos questions
- Notre fil conducteur : le GPSN est un projet de **numérisation du métier notarial** — la technologie est au service de la profession, pas l'inverse
- On va montrer des diagrammes et des maquettes tirés directement de notre proposition — ce sont les mêmes artefacts qui ont guidé la rédaction

On commence.

---

## Section 1 — Documentation et modélisation des processus d'affaires notariaux

[⏱ 0:00 — cible 5:00]

### Accroche

Le GPSN n'est pas un projet techno — c'est un projet de numérisation métier. Tout part de la compréhension du travail notarial.

### Points clés

**Consultant notarial dédié**
- 70 heures budgétées — pas un à-côté, un livrable structurant
- Workflows standardisés par type d'acte : testament, succession, mandat de protection, transaction immobilière, procuration
- Validés par un expert du métier avant d'écrire une seule ligne de code

**Cinq profils utilisateurs modélisés de bout en bout**
- Citoyen, notaire, administrateur Chambre, administrateur système, auditeur
- Chacun avec des parcours RBAC distincts — ce qu'on voit, ce qu'on peut faire, ce qu'on ne peut pas faire
- Séparation stricte : un citoyen ne voit jamais les billets d'un autre

**Dimensionnement concret**
- 2 700 notaires actifs, croissance 10 % par an — on est à 3 594 dans 3 ans
- 3 000 sessions simultanées, 4 000 interactions par jour
- Ça guide tout : la taille des files d'attente, les performances, les tableaux de bord

[MONTRER : 05-f01-functional-module-map.png]

**Cartographie modulaire** (~1 min sur le diagramme)
- 5 blocs : demandes de service, coffre-fort numérique, calendrier, intégrations tierces, administration
- Chaque bloc est indépendant mais interconnecté
- Le coffre-fort est le point d'arrivée naturel de chaque transaction — on y revient en section 5

### Transition

Maintenant qu'on a vu comment on modélise le métier, regardons sur quoi tout ça repose techniquement.

[⏱ cible : 5:00]

---

## Section 2 — Architecture logicielle de la solution

[⏱ 5:00 — cible 15:00]

### Accroche

L'architecture, c'est ce qui détermine si une solution va pouvoir évoluer, se transférer et être maintenue par vos équipes. On a fait des choix défensifs et éprouvés.

### Points clés

[MONTRER : 01-t01-architecture-overview.png]

**Architecture tri-couche modulaire** (~2 min)
- Présentation : React + TypeScript — interface moderne, accessible SGQRI 008 3.0
- Logique métier : Django + Python — règles notariales, contrôles d'accès, orchestrations
- Données : PostgreSQL — persistance relationnelle, 3 schémas logiques distincts
- Chaque couche modifiable et testable indépendamment
- CryptoGuard pour la GRC : même pile, même architecture — éprouvée en production fédérale

[MONTRER : 13-t01-component-layers.png]

**7 services conteneurisés** (~2 min)
- Frontend React, API Django, worker Celery, ordonnanceur Celery Beat, PostgreSQL, RabbitMQ, Redis
- Chaque service a son cycle de vie propre — un incident sur un composant ne force pas l'arrêt de la plateforme
- `docker compose up --build` : plateforme complète en moins de 5 minutes
- L'évaluateur peut valider module par module selon les jalons du PoC

**Pile 100 % open source** (~1 min)
- Django BSD-3, React MIT, PostgreSQL libre, RabbitMQ MPL-2.0
- Zéro redevance, zéro verrouillage fournisseur
- Fichier `LICENSES.md` livré avec le dépôt — tout est documenté

[MONTRER : 15-t03-infrastructure-overview.png]

**Portabilité souveraine** (~2 min)
- Azure App Service en cible initiale — compatible avec votre environnement
- Infrastructure définie en code avec Terraform — pas de configuration manuelle
- Migration possible vers eStruxture, Mantle, ThinkOn sans refonte du code applicatif
- Mantle Technology : partenaire Webisoft sur CryptoGuard, expertise stockage distribué sécurisé
- La valeur : préserver la liberté d'hébergement pour les données notariales sensibles

**Observabilité temps réel** (~1 min)
- OpenTelemetry + Prometheus + Grafana dès le premier sprint
- Traces corrélées du navigateur jusqu'à la base de données
- On n'attend pas la production pour instrumenter — c'est intégré dès le PoC

### Transition

Vous avez vu la structure. Maintenant, entrons dans le cœur du sujet : comment le moteur de workflow orchestre concrètement une demande notariale de bout en bout.

[⏱ cible : 15:00]

---

## Section 3 — Moteur de workflow et gestion de l'évolution d'une demande

[⏱ 15:00 — cible 35:00]

> Section la plus longue — 20 min, structurée en 4 sous-blocs. C'est la priorité du comité.

### Accroche

Le moteur de processus, c'est le cœur du GPSN. C'est ce qui fait qu'un notaire qui gère 5 dossiers par jour ne perd pas de temps à chercher quoi faire — le système le guide.

---

### Sous-bloc A : Cycle de vie complet d'une demande

[⏱ 15:00 — cible 21:00 | ~6 min]

[MONTRER : 06-f01-demande-service-flow.png]

> Diagramme central — rester dessus ~3 min. Pointer les étapes en parlant.

**Création de la demande — côté citoyen**
- Catalogue de services administrable : testament, mandat, procuration, succession, immobilier
- Option « billet libre » — le citoyen qui ne sait pas quoi choisir décrit son besoin en texte
- Numéro unique attribué automatiquement — même identifiant de l'ouverture à l'archivage
- Suggestion de notaires par proximité géographique (code postal), sinon ordre alphabétique
- Le notaire peut aussi initier : il génère un lien d'invitation sécurisé, le citoyen reprend le parcours

**Prise en charge — côté notaire**
- Tableau de bord avec filtres : statut, type, date, citoyen
- 3 actions possibles : accepter, refuser (avec motif), réassigner
- Chaque action horodatée et tracée dans le journal d'audit

**Traitement guidé**
- Le moteur charge automatiquement les étapes selon le type d'acte
- Seules les transitions autorisées sont permises
- Conditions de passage définies — impossible de sauter une étape obligatoire

[MONTRER : 17-f01-suivi-demande.png]

**Suivi temps réel** (~1 min)
- Vue partagée citoyen/notaire — même vision de la progression
- Prochaines étapes et actions attendues affichées clairement
- Notifications multicanal à chaque changement d'état : courriel + notification intégrée + SMS

---

### Sous-bloc B : Flexibilité et automatisation du moteur

[⏱ 21:00 — cible 25:00 | ~4 min]

**Processus adaptables**
- Modèles par type d'acte validés avec le consultant notarial
- Étapes facultatives : le notaire peut en ajouter selon le dossier (vérification supplémentaire, rencontre additionnelle)
- Étapes réglementaires : verrouillées, impossibles à supprimer ou contourner
- Flexibilité encadrée : on adapte le parcours sans casser la conformité

**Automatisations**
- Vérification automatique de complétude des pièces
- Rappels automatiques quand un dossier stagne
- À la finalisation : déclenchement automatique de la certification blockchain — aucune action manuelle

[MONTRER : 07-f01-authentification-flow.png] (~30 sec)

- Authentification Interac via OIDC + PKCE
- Mode IVS principal, IDVS pour assurance accrue
- Profil citoyen pré-rempli automatiquement à partir des claims vérifiés

[MONTRER : 19-t04-chaine-audit.png]

**Traçabilité complète** (~1 min)
- Journal append-only — aucune modification, aucune suppression possible
- Chaînage cryptographique BLAKE2b : chaque entrée liée à la précédente
- Toute altération rompt la chaîne — détectable instantanément
- Vérification quotidienne automatisée
- C'est exactement l'architecture de traçabilité de CryptoGuard pour la GRC

**Parcours de signature**
- ConsignO Cloud (Notarius) pour la signature électronique certifiée
- Empreinte SHA-256 → ancrage Hyperledger Fabric → scellement → dépôt coffre-fort
- On détaille ce flux dans le sous-bloc suivant

---

### Sous-bloc C : Démonstration narrative — Scénario « Testament simple »

[⏱ 25:00 — cible 31:00 | ~6 min]

> Parler comme si on montrait le système en direct. Pointer les étapes sur le diagramme.

[MONTRER : 06-f01-demande-service-flow.png] (reprendre le diagramme central)

Imaginons un citoyen qui veut faire rédiger son testament.

**Étape 1 — Authentification**
- Le citoyen se connecte via Interac — il s'authentifie auprès de sa banque
- OIDC avec PKCE, identifiant pairwise pour protéger la vie privée
- Profil pré-rempli automatiquement — nom, prénom, informations vérifiées
- Pas de formulaire d'inscription classique à remplir

**Étape 2 — Création de la demande**
- Il sélectionne « Testament » dans le catalogue
- Il choisit un notaire par proximité géographique
- Il téléverse ses pièces justificatives — zone glisser-déposer
- Contrôle antivirus automatique, suppression des métadonnées EXIF
- Fichiers jusqu'à 50 Mo acceptés

**Étape 3 — Prise en charge notaire**
- Le notaire reçoit une notification
- Il prend en charge le dossier
- Le moteur charge les étapes du processus « Testament »
- Chaque étape s'affiche dans son tableau de bord avec les actions attendues

**Étape 4 — Rendez-vous**
- Le notaire planifie un rendez-vous via le calendrier intégré
- Synchronisation bidirectionnelle Google Calendar / Outlook
- Filtre de confidentialité : le citoyen ne voit que « disponible / occupé »
- Confirmation simultanée aux deux parties

**Étape 5 — Signature électronique**
- ConsignO Cloud — solution reconnue au Québec
- Statut suivi en temps réel dans l'interface
- Le citoyen et le notaire voient la progression

[MONTRER : 03-t02-blockchain-flow.png]

**Étape 6 — Certification et archivage** (~2 min sur le diagramme)
- Empreinte SHA-256 calculée sur le document signé
- Soumission à l'API blockchain Hyperledger Fabric de l'Université
- L'API retourne un identifiant de transaction — c'est la preuve d'ancrage
- Scellement électronique du document avec la preuve
- Dépôt automatique dans le coffre-fort du citoyen
- Notification envoyée — « votre acte est disponible »
- C'est le même flux d'ancrage que CryptoGuard — même pile, même fiabilité

**Étape 7 — Accès citoyen**
- Le citoyen consulte, télécharge ou partage son acte
- Lien temporaire sécurisé, 24h par défaut, configurable
- Preuves numériques préservées au téléchargement

**Étape 8 — Vérification publique**
- N'importe qui avec le document peut le vérifier
- Interface sans authentification — on dépose le fichier
- Recalcul SHA-256, comparaison avec la blockchain
- Verdict clair : **Authentique** / **Modifié ou inconnu** / **Révoqué**
- Aucun stockage du document soumis — confidentialité totale

---

### Sous-bloc D : Intégrations externes

[⏱ 31:00 — cible 35:00 | ~4 min]

> Si le temps est court, comprimer à 2 min — les détails sont dans la proposition.

[MONTRER : 02-t02-integration-architecture.png]

**6 intégrations, un patron commun**

Toutes suivent le même patron : REST, authentification sécurisée, validation JSON stricte, simulateurs locaux pour le PoC.

| Intégration | Ce qu'elle fait |
|-------------|-----------------|
| **Interac** | Vérification d'identité — OIDC, claims vérifiés, IVS/IDVS |
| **Google Calendar / Outlook** | Synchronisation bidirectionnelle des rendez-vous, filtre de confidentialité |
| **Stripe** | Liens de paiement sécurisés, confirmations automatiques |
| **ConsignO Cloud (Notarius)** | Signature électronique certifiée, reconnue au Québec |
| **QuickBooks** | Facturation automatique, synchronisation des paiements |
| **ParaMaître** | Interopérabilité logiciel notarial — adaptateur de métadonnées |

- Chaque intégration a un simulateur local — le PoC fonctionne sans dépendance externe
- En production, on branche les vrais services sans changer l'architecture

### Transition

Vous avez vu le processus en détail. Maintenant, voyons ce que le notaire et le citoyen voient concrètement à l'écran.

[⏱ cible : 35:00]

---

## Section 4 — Exemple d'interface utilisateur et déroulement d'une transaction notariale

[⏱ 35:00 — cible 45:00]

### Accroche

Ces maquettes ne sont pas du marketing. Ce sont des prototypes fonctionnels qui ont guidé la rédaction de la proposition. Chaque écran répond à des exigences précises du devis.

### Points clés

[MONTRER : 05-f01-coffre-fort-vue-principale.png]

**Coffre-fort — Vue principale** (~2 min)
- On commence par le coffre-fort stratégiquement — c'est la concrétisation de la vision de la Chambre
- Catégories : actes notariés, pièces justificatives, correspondances, documents personnels
- Recherche avec filtres : catégorie, type, date, notaire, statut de certification
- Alertes pour les nouveaux dépôts et les changements de statut
- Vue liste, vue grille avec miniatures — pensée pour un coffre alimenté à 365 actes/an/notaire

[MONTRER : 01-f01-televersement-stockage.png]

**Téléversement de documents** (~2 min)
- Zone glisser-déposer intuitive
- Assistant de classement guidé : catégorie, type, métadonnées
- Suggestion automatique de catégorie à partir du nom de fichier
- Barre de progression + indicateurs sécurité : antivirus en cours, EXIF nettoyé, intégrité vérifiée
- Le citoyen n'a pas besoin de comprendre le chiffrement — il voit « sécurisé »

[MONTRER : 02-f01-prise-rendez-vous.png]

**Prise de rendez-vous** (~2 min)
- Calendrier hebdomadaire — créneaux libres visibles
- Choix présentiel ou vidéoconférence
- Confirmation simultanée citoyen + notaire
- Filtre de confidentialité : seule l'information « occupé/disponible » est visible
- Double vérification avant réservation — pas de conflit possible

[MONTRER : 04-f01-partage-documents.png]

**Partage de documents** (~2 min)
- Lien temporaire sécurisé — 24h par défaut, configurable
- 3 niveaux d'accès : consultation, téléchargement, consultation + téléchargement
- Révocation immédiate à tout moment
- Chaque accès consigné dans le journal d'audit
- Le propriétaire garde le contrôle total

[MONTRER : 03-f01-configuration-conditions.png]

**Héritiers numériques** (~1 min)
- Désignation avec droits d'accès par document
- Conditions de déclenchement configurables
- Révocable à tout moment
- Le détail se trouve à la section Coffre-fort de notre proposition

### Transition

Vous avez vu le coffre-fort du point de vue utilisateur. Maintenant, voyons comment le module Services notariaux et le module Coffre-fort travaillent ensemble sous le capot.

[⏱ cible : 45:00]

---

## Section 5 — Articulation entre les modules « Services notariaux » et « Coffre-fort numérique »

[⏱ 45:00 — cible 50:00]

### Accroche

Le coffre-fort n'est pas un module isolé à côté des services notariaux. C'est le point d'arrivée naturel de chaque transaction. L'articulation est automatique, traçable et sans double téléversement.

### Points clés

[MONTRER : 02-t02-integration-architecture.png]

**Transmission automatique sans duplication** (~1.5 min)
- Référence interne sécurisée entre le volet GPSN et le coffre-fort
- Pas de copie du fichier — unicité de la source documentaire préservée
- Permissions et preuves d'intégrité suivent le document automatiquement
- Le citoyen associe un document existant de son coffre-fort à une nouvelle demande — zéro re-téléversement

[MONTRER : 03-t02-blockchain-flow.png]

**Chaîne d'intégrité continue** (~1.5 min)
- Empreinte BLAKE2b sur le document
- Ancrage dans Hyperledger Fabric via l'API de l'Université
- Scellement électronique avec la preuve d'ancrage
- C'est le même flux technique que CryptoGuard — ici c'est le rappel légitime
- Vérification croisée possible : racine locale vs condensé ancré dans la blockchain

**Expérience utilisateur unifiée** (~1 min)
- Authentification unique — pas de deuxième connexion pour accéder au coffre-fort
- Coffre-fort accessible depuis la navigation principale et depuis la vue de suivi
- Documents réutilisables sans re-téléversement entre les dossiers

**Architecture d'isolation** (~1 min)
- 3 schémas logiques PostgreSQL : citoyens, notaires, documents
- Filtrage systématique par propriétaire à chaque requête
- Partages explicites, temporaires, révocables
- Un citoyen ne voit jamais les documents d'un autre — garanti par l'architecture, pas par convention

### Transition

L'intégrité est garantie par l'architecture. Maintenant, comment la valide-t-on ? Parlons de la stratégie de tests automatisés.

[⏱ cible : 50:00]

---

## Section 6 — Approche d'essais automatisés et de validation de la solution

[⏱ 50:00 — cible 60:00]

### Accroche

Sur notre plateforme Privara en production : déploiement quotidien, délai de livraison inférieur à 4 heures, taux d'échec inférieur à 5 %. Le GPSN hérite de cette même discipline dès le premier sprint.

### Points clés

[MONTRER : 12-t06-test-strategy-pyramid.png]

**Pyramide de tests à 4 niveaux** (~2 min)
- **Unitaires** — pytest côté Python, Jest côté TypeScript. Règles locales, composants isolés
- **Intégration** — API, flux applicatifs, échanges entre composants. Base de données réelle, pas de mocks
- **Sécurité** — SAST (analyse statique), DAST (analyse dynamique), audit automatique des dépendances
- **UI / E2E** — Playwright rejoue les parcours critiques. Vérifications WCAG à chaque exécution
- Couverture cible : 90 % et plus

**Tests de charge Locust** (~2 min)
- Outil reconnu dans l'industrie, scriptable en Python — scénarios = parcours métier GPSN
- Mode distribué : palier 0 → 3 500 sessions en 10 min, plateau 30 min
- Critères d'acceptation : P95 < 5 secondes, taux d'erreur < 1 %
- Documents réalistes : testaments 30 pages / 5 versions, transactions immobilières 10 docs × 8 pages
- Projection à 3 ans : 2 700 → 3 594 notaires, test de stabilité 4 heures

[MONTRER : 04-t03-deployment-pipeline.png]

**Pipeline CI/CD** (~2 min)
- GitHub Actions : lint → tests → build images → publication Azure Container Registry
- Aucune fusion sans pipeline vert — c'est une porte bloquante
- Reproductible localement : `make test`, `make lint`, `make test-e2e`
- Images Docker versionnées par hash de commit — reproductibilité garantie
- Revues de code obligatoires avant toute fusion

[MONTRER : 16-t03-integration-continue.png] (~30 sec)
- Vue détaillée du pipeline d'intégration continue
- Chaque étape de validation visible

**Observabilité** (~2 min)
- OpenTelemetry : traces corrélées du navigateur à la base de données
- Prometheus : métriques temps réel — temps de réponse, débit, ressources
- Grafana : tableaux de bord SLA préconfigurés. Alerte dès que P95 dépasse 4 secondes
- Loki : journaux centralisés, explorables via LogQL
- Web Vitals : LCP, FID, CLS capturés à chaque exécution de tests

**Piste d'audit comme couche de validation** (~1 min)
- Journal append-only avec chaînage BLAKE2b — on l'a vu en section 3
- Vérification automatisée quotidienne de la chaîne
- Ancrage mensuel de la racine de Merkle dans Hyperledger Fabric
- Fréquence configurable — mensuel est le minimum contractuel

### Transition

Voilà pour notre approche. Je suis maintenant disponible pour vos questions — et j'ai quelques sujets que vous voudrez peut-être approfondir.

[⏱ cible : 60:00]

---

## Section 7 — Varia et période de questions

[⏱ 60:00 — cible 90:00]

### Point proactif : Stratégie de PoC (2-3 min)

> Présenter avant d'ouvrir aux questions.

[MONTRER : 11-t05-poc-phases.png]

**3 jalons contractuels — Phase 0 sur 16 semaines**

| Jalon | Semaine | Ce qu'on démontre |
|-------|---------|-------------------|
| J1 | S6 | Architecture + authentification + première connexion blockchain |
| J2 | S12 | Services notariaux complets bout en bout |
| J3 | S16 | Intégration blockchain + coffre-fort numérique |

**Validation autonome**
- `docker compose up --build` — moins de 5 minutes
- `make validate` — enchaîne : vérification environnement, démarrage, tests, rapport
- Jeux de données pré-ensemencés, simulateurs locaux pour Interac/ConsignO/blockchain
- Aucune dépendance externe au-delà de Docker et d'un navigateur

C'est exactement l'approche qui a fonctionné pour CryptoGuard : l'évaluateur de la GRC a validé le système complet sans nous contacter.

Je suis maintenant à votre disposition pour vos questions.

---

### Questions anticipées — Fiches de réponse

---

#### Q1 — « Pourquoi Django plutôt que Node.js ? »

- Le devis suggérait Node.js mais ne l'imposait pas
- Django est le choix le plus défensif pour nous :
  - 50+ projets Django livrés en 8 ans
  - CryptoGuard : même pile, même expertise blockchain
  - ORM robuste, framework d'authentification natif, signaux pour l'audit
- Python est mature et lisible — l'évaluateur peut vérifier la qualité du code directement
- Le résultat pour l'Université : une équipe qui maîtrise parfaitement sa pile, pas une équipe qui apprend en cours de mandat

---

#### Q2 — « Résilience blockchain quand l'API est indisponible ? »

- File d'attente persistante RabbitMQ dédiée aux opérations blockchain
- Retentative avec délai progressif — exponential backoff + jitter
- 4 familles d'erreurs :
  - **Temporaire** → reprise auto
  - **Permanente** → arrêt contrôlé, intervention requise
  - **Configuration** → alerte admin prioritaire
  - **Réseau** → reprise auto + surveillance
- Garantie de non-perte : persistance des messages, acquittement seulement après succès confirmé
- Sur CryptoGuard, ce mécanisme a maintenu la disponibilité sous les contraintes de preuve judiciaire de la GRC

---

#### Q3 — « Loi 25 et les 20 règlements de la section C.07 ? »

- Cartographie réglementaire dès le cadrage — obligations par volet fonctionnel
- Consultant notarial externe (70h) — validation des workflows et des interprétations réglementaires
- Mécanismes techniques :
  - Anonymisation sous 30 jours après suppression de compte
  - Minimisation des données — on ne collecte que le nécessaire
  - Journaux protégés en intégrité (BLAKE2b + ancrage blockchain)
- Démarche SOC 2 en cours via Vanta — alignement SMSI

---

#### Q4 — « Accessibilité SGQRI 008 3.0 / WCAG 2.1 AA ? »

- Conformité intégrée dès la conception, pas ajoutée en fin de sprint
- Audits automatisés axe-core à chaque sprint
- Navigation clavier complète, compatibilité lecteurs d'écran
- Tests Playwright incluent des vérifications d'accessibilité
- Web Vitals mesurés systématiquement

---

#### Q5 — « Transfert de connaissances vers l'équipe ULaval ? »

- Tout le code est libre de droit et livrable — zéro verrouillage
- Guides de démonstration module par module — livrés avec chaque jalon
- Infrastructure définie en code (Terraform) — pas de configuration manuelle à transmettre
- Formation planifiée en phase d'acceptation (3 mois)
- Document de contribution avec les conventions de codage

---

#### Q6 — « Synchronisation calendrier pour 2 700 notaires ? »

- Synchronisation bidirectionnelle Google Calendar / Outlook via API dédiées
- Filtre de confidentialité : seule l'information « occupé/disponible » transite dans le GPSN
- Réconciliation périodique pour gérer les interruptions
- Double contrôle avant réservation — pas de conflit possible
- Échelle validée par les tests de charge Locust

---

#### Q7 — « Si la Phase 0 identifie un problème majeur ? »

- Le PoC est conçu comme porte contractuelle — 3 jalons progressifs pour détecter tôt
- Le devis prévoit 5 jours ouvrables pour corriger une non-conformité
- Notre approche : démonstrations continues, on ne surprend personne au jalon
- Chaque jalon livre une version étiquetée du docker-compose + données de test

---

#### Q8 — « Mécanisme d'ancrage blockchain des journaux d'audit ? »

- Tâche Celery périodique — calcule la racine de Merkle de toutes les entrées du mois
- Condensé soumis à l'API REST Hyperledger Fabric
- L'API retourne un identifiant de transaction → consigné dans la table d'audit
- Vérification croisée : racine locale vs condensé ancré
- Fréquence configurable — mensuel est le minimum, hebdomadaire ou quotidien possible

---

### Notes pour la gestion des questions

- **Réponses concises** : 2-3 min max par question
- Si les questions tarissent, proposer d'approfondir : sécurité applicative (OWASP Top 10), processus de déploiement détaillé, stratégie de formation
- Ne jamais inventer de chiffres — si la question sort du périmètre : « on vous répond par écrit dans les meilleurs délais »
- Quand un point est détaillé dans la proposition, le dire : « le détail se trouve à la section X de notre proposition »

---

## Notes de rythme — Vue d'ensemble

| Section | Durée | Visuels | Si serré |
|---------|-------|---------|----------|
| 1 — Processus d'affaires | 5 min | 1 diagramme | Max 1 min sur le diagramme |
| 2 — Architecture | 10 min | 3 diagrammes | Couper infrastructure (30 sec) |
| 3 — Moteur de workflow | 20 min | 7 diagrammes | Comprimer 3D (intégrations) à 2 min |
| 4 — Interface utilisateur | 10 min | 5 maquettes | Couper héritiers (1 min) |
| 5 — Articulation modules | 5 min | 2 diagrammes | Fusionner avec fin de section 4 |
| 6 — Tests et validation | 10 min | 3-4 diagrammes | Couper intégration continue détaillée |
| 7 — Questions | 30 min | 1 diagramme (PoC) | — |

**Visuels essentiels (si on doit réduire à 10) :**
1. `05-f01-functional-module-map.png`
2. `01-t01-architecture-overview.png`
3. `06-f01-demande-service-flow.png`
4. `03-t02-blockchain-flow.png`
5. `02-t02-integration-architecture.png`
6. `05-f01-coffre-fort-vue-principale.png`
7. `01-f01-televersement-stockage.png`
8. `12-t06-test-strategy-pyramid.png`
9. `04-t03-deployment-pipeline.png`
10. `11-t05-poc-phases.png`

---

## Discipline CryptoGuard — Rappels autorisés

| Section | Usage | Formulation |
|---------|-------|-------------|
| 2 | Une fois, fortement | « même pile technologique, éprouvée en production fédérale » |
| 3B | Rappel technique | « même architecture de traçabilité » |
| 3C | Certification | « même flux d'ancrage » |
| 5 | Chaîne d'intégrité | « même flux technique — rappel légitime ici » |
| 7 | Réponses aux questions | Exemples concrets, jamais en refrain |

> Ne pas mentionner CryptoGuard plus de 5 fois dans la présentation. Le comité technique verra la répétition comme un manque de substance.
