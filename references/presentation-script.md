# Script de présentation — GPSN — Université Laval

**Durée :** 60 min contenu + 30 min questions
**Présentateur :** Jeremie Bonsant, Webisoft Technologie Inc.

Format volontairement oral.
Les accroches et transitions peuvent être dites telles quelles.
Le reste = repères courts à parcourir du regard.

## Ouverture (~1 min)

Merci de nous recevoir. Je suis Jeremie Bonsant.

- 6 sujets en 60 minutes, puis vos questions
- Fil conducteur: le GPSN est un projet de numérisation du métier notarial
- La technologie est au service de la profession, pas l'inverse
- On va montrer des diagrammes et des maquettes tirés directement de notre proposition

On commence.

---

## 1. Documentation et modélisation des processus d'affaires notariaux

[⏱ 0:00 — cible 5:00]

Cette solution, pour nous, commence par le métier notarial. La technologie vient après, au service du parcours, de la conformité et du temps gagné pour le notaire.

[MONTRER: 05-f01-functional-module-map]

- Point de départ: projet de numérisation métier, pas simple projet TI
- Consultant notarial externe dédié
- 70 heures budgétées pour valider les parcours et les règles métier
- Modèles standardisés par type d'acte
- Testament
- Succession
- Mandat de protection
- Transaction immobilière
- Procuration
- Cinq profils couverts de bout en bout
- Citoyen
- Notaire
- Administrateur Chambre
- Administrateur système
- Auditeur
- RBAC distinct pour chaque profil
- Parcours, écrans, permissions, journaux
- Dimensionnement concret dès la conception
- 2 700 notaires actifs
- Croissance projetée de 10 % par an
- 3 594 notaires à trois ans
- 3 000 sessions simultanées
- 4 000 interactions quotidiennes côté services notariaux
- Cartographie modulaire pensée pour le travail réel
- demandes de service
- coffre-fort numérique
- rendez-vous et calendrier
- intégrations tierces
- administration et supervision
- Le coffre-fort est le point d'arrivée naturel de chaque transaction
- Idée simple à faire passer: chaque module répond à un moment précis du parcours notarial

Si on doit couper:

- garder consultant notarial
- garder 5 profils
- garder chiffres de volumétrie
- finir sur la cartographie modulaire

Maintenant qu'on a vu comment on modélise le métier, regardons sur quoi tout ça repose techniquement.

---

## 2. Architecture logicielle de la solution

[⏱ 5:00 — cible 15:00]

L'architecture, c'est ce qui détermine si la solution va pouvoir évoluer, se transférer et être maintenue. On a fait des choix défensifs et éprouvés.

[MONTRER: 01-t01-architecture-overview]

- Référence technique à poser une seule fois, clairement
- même pile de base que CryptoGuard pour la GRC
- même logique de traçabilité, de modularité, de portabilité
- Architecture tri-couche
- React + TypeScript pour l'interface
- Django pour la logique métier
- PostgreSQL pour la persistance
- 3 schémas logiques distincts pour isoler les périmètres sensibles
- Séparation nette entre présentation, règles métier, données
- Avantage direct
- chaque couche peut évoluer sans casser les autres
- tests plus simples
- maintenance plus simple
- transfert plus simple vers ULaval

[MONTRER: 13-t01-component-layers]

- Sept services conteneurisés
- frontend
- API
- Celery worker
- Celery Beat
- PostgreSQL
- RabbitMQ
- Redis
- Cycles de vie indépendants
- redémarrage ciblé
- montée en charge ciblée
- diagnostic plus rapide
- Démonstration et validation par blocs possibles
- Très utile pour la phase PoC
- Démarrage simple
- `docker compose up --build`
- environnement complet en moins de 5 minutes

- Pile 100 % open source
- Django BSD-3
- React MIT
- PostgreSQL licence PostgreSQL
- RabbitMQ, Docker, Redis, Celery
- zéro redevance
- zéro verrouillage fournisseur

[MONTRER: 15-t03-infrastructure-overview]

- Hébergement initial aligné sur votre cible
- Azure App Service
- Infrastructure définie en code avec Terraform
- Point important: portabilité réelle
- migration possible vers eStruxture
- migration possible vers Mantle
- migration possible vers ThinkOn
- sans refonte applicative

- Observabilité native dès le premier sprint
- OpenTelemetry
- Prometheus
- Grafana
- Traces corrélées du navigateur jusqu'à la base de données
- On ne découvre pas les problèmes à la fin
- on les voit dès le départ

Si on doit couper:

- garder tri-couche
- garder 7 services
- garder open source
- garder portabilité + Terraform

Vous avez vu la structure. Maintenant, entrons dans le cœur du sujet: comment le moteur de workflow orchestre une demande notariale de bout en bout.

---

## 3. Moteur de workflow proposé et gestion de l'évolution d'une demande

[⏱ 15:00 — cible 35:00]

C'est le cœur du GPSN. Si cette brique fonctionne bien, le reste devient cohérent: service, conformité, expérience utilisateur, traçabilité.

### 3A. Cycle de vie complet d'une demande

[⏱ 15:00 — cible 21:00 | ~6 min]

[MONTRER: 06-f01-demande-service-flow]

- Côté citoyen
- entrée par un catalogue de services administrable
- types d'actes prédéfinis
- possibilité de billet libre si le citoyen ne sait pas nommer le bon service
- numéro unique attribué automatiquement
- pièces justificatives jointes dès l'ouverture
- suggestion de notaires par proximité si code postal fourni
- sinon ordre alphabétique
- liberté de choisir le notaire quand même

- Autre point utile
- le notaire peut aussi initier la demande
- lien d'invitation sécurisé à usage unique
- le citoyen arrive ensuite dans un parcours déjà prérempli

- Côté notaire
- tableau de bord avec filtres par statut, type, date, citoyen
- trois actions immédiates
- accepter
- refuser avec motif
- réassigner
- chaque action est horodatée
- chaque action est journalisée

- Dès que le dossier est pris en charge
- le moteur charge automatiquement le bon processus
- seules les transitions autorisées sont possibles
- impossible de sauter une étape obligatoire
- les documents attendus sont visibles
- les actions attendues sont visibles

[MONTRER: 17-f01-suivi-demande]

- Côté suivi
- vue partagée citoyen / notaire
- étape courante visible
- prochaines actions visibles
- notifications à chaque changement d'état
- courriel
- notification intégrée
- SMS pour les rappels critiques

Phrase à dire:

Le point important, c'est que le citoyen n'est jamais dans le flou, et le notaire n'a pas besoin de reconstruire mentalement où en est le dossier.

### 3B. Flexibilité et automatisation du moteur

[⏱ 21:00 — cible 25:00 | ~4 min]

- Processus standardisés par type d'acte
- validés avec le consultant notarial
- base commune pour sécuriser le traitement

- Flexibilité contrôlée
- le notaire peut ajouter des étapes facultatives
- réorganiser certaines étapes non obligatoires
- les étapes réglementaires restent verrouillées
- on adapte le parcours sans casser la conformité

- Automatisations utiles
- vérification de complétude
- rappels
- relances
- changement de statut
- déclenchement automatique de la certification en fin de parcours

[MONTRER: 07-f01-authentification-flow]

- Rappel rapide sur l'identité
- citoyen via Interac OIDC + PKCE
- notaires et comptes temporaires avec MFA obligatoire
- même exigence de sécurité pour les accès délégués

[MONTRER: 19-t04-chaine-audit]

- Traçabilité complète
- journal append-only
- pas de modification manuelle possible
- chaînage cryptographique BLAKE2b
- une altération rompt la chaîne
- vérification quotidienne automatisée
- ancrage périodique dans Hyperledger Fabric

- Parcours de signature à retenir
- ConsignO Cloud
- signature
- empreinte SHA-256 du document certifié
- ancrage blockchain
- scellement
- dépôt coffre-fort

Phrase à dire:

Donc le workflow n'est pas juste une liste d'étapes. C'est un moteur qui encadre, automatise et prouve.

### 3C. Démonstration narrative — scénario « Testament simple »

[⏱ 25:00 — cible 31:00 | ~6 min]

Je vais le raconter comme si on faisait la démonstration en direct.

[MONTRER: 06-f01-demande-service-flow]

1. Le citoyen arrive dans la plateforme et s'authentifie via Interac.
2. Son profil est créé ou reconnu automatiquement.
3. Il choisit le service « Testament » dans le catalogue.
4. Il choisit un notaire proposé selon la proximité, ou un autre notaire s'il le souhaite.
5. Il téléverse ses pièces justificatives.
6. Le dépôt est contrôlé automatiquement.
7. Antivirus.
8. Suppression des métadonnées sensibles comme les EXIF.
9. Le notaire reçoit une notification et prend en charge le dossier.
10. Le moteur charge le processus « Testament » avec les étapes attendues.
11. Le notaire planifie un rendez-vous.
12. Synchronisation bidirectionnelle avec Google Calendar ou Outlook.
13. Le document est préparé.
14. La signature électronique passe par ConsignO Cloud.
15. Le statut de signature remonte en temps réel dans le dossier.

[MONTRER: 03-t02-blockchain-flow]

16. Une fois l'acte finalisé, l'empreinte SHA-256 est calculée.
17. Cette empreinte est ancrée dans Hyperledger Fabric via l'API REST.
18. Le document est scellé avec sa preuve.
19. Il est déposé automatiquement dans le coffre-fort numérique du citoyen.
20. Le citoyen reçoit une notification.
21. Il peut consulter, télécharger, ou partager avec un lien temporaire sécurisé.
22. Plus tard, un tiers peut vérifier l'authenticité du document dans une interface publique.
23. Verdict simple et compréhensible.
24. Authentique.
25. Modifié ou inconnu.
26. Révoqué.

Phrase à dire:

Ce qu'on veut éviter ici, c'est toute rupture entre le travail du notaire, la signature, la preuve d'intégrité et la remise finale au citoyen.

### 3D. Intégrations externes

[⏱ 31:00 — cible 35:00 | ~4 min]

[MONTRER: 02-t02-integration-architecture]

- Six intégrations, un patron commun
- Interac pour l'identité
- Google Calendar et Outlook pour les rendez-vous
- Stripe pour les paiements
- ConsignO Cloud pour la signature
- QuickBooks pour la facturation
- ParaMaître pour l'interopérabilité métier

- Logique commune d'intégration
- API REST
- authentification sécurisée
- validation JSON stricte
- HTTPS uniquement
- traitement standardisé des erreurs

- Très important pour le PoC
- simulateurs locaux pour les services externes
- donc démonstration autonome possible
- sans dépendre d'une connexion réelle à chaque service

Si on doit couper:

- ne pas détailler les six intégrations
- garder Interac, ConsignO, calendrier
- finir sur le patron REST + simulateurs locaux

Vous avez vu le processus en détail. Maintenant, voyons ce que le notaire et le citoyen voient concrètement à l'écran.

---

## 4. Exemple d'interface utilisateur et déroulement d'une transaction notariale

[⏱ 35:00 — cible 45:00]

Ces écrans ne sont pas là pour faire joli. Ils nous ont servi à concevoir les parcours, à valider les exigences du devis et à rendre le fonctionnement très concret.

[MONTRER: 05-f01-coffre-fort-vue-principale]

- Je commence par le coffre-fort, parce que c'est la vision la plus tangible pour la Chambre
- catégories claires
- actes notariés
- pièces justificatives
- correspondances
- documents personnels
- recherche
- filtres
- alertes sur les nouveaux dépôts
- statut de certification visible
- même authentification que le reste de la plateforme
- pas de second silo, pas de seconde connexion

[MONTRER: 01-f01-televersement-stockage]

- Téléversement
- zone glisser-déposer
- assistant de classement guidé
- métadonnées utiles au bon endroit
- barre de progression
- contrôle antivirus
- suppression des EXIF
- formats usuels acceptés
- PDF, DOCX, JPG, PNG
- jusqu'à 50 Mo

Phrase à dire:

Le citoyen n'a pas à comprendre le chiffrement ou la blockchain. Il doit juste sentir que le dépôt est simple et fiable.

[MONTRER: 02-f01-prise-rendez-vous]

- Prise de rendez-vous
- vue hebdomadaire claire
- présentiel ou en ligne
- créneaux réellement disponibles
- double contrôle avant réservation
- confirmation envoyée au citoyen et au notaire
- confidentialité préservée
- le citoyen voit seulement libre ou occupé

[MONTRER: 04-f01-partage-documents]

- Partage de documents
- lien temporaire sécurisé
- 24 heures par défaut
- durée configurable
- niveau d'accès configurable
- authentification possible
- révocation immédiate
- chaque accès consigné

[MONTRER: 03-f01-configuration-conditions]

- Fonction héritiers numériques
- désignation d'un ou plusieurs héritiers
- droits d'accès par document ou catégorie
- conditions de déclenchement configurables
- révocation possible à tout moment
- journal d'audit dédié

Si on doit couper:

- garder coffre-fort
- garder téléversement
- garder prise de rendez-vous

Vous avez vu le coffre-fort du point de vue utilisateur. Maintenant, voyons comment le module Services notariaux et le module Coffre-fort travaillent ensemble sous le capot.

---

## 5. Articulation entre les modules « Services notariaux » et « Coffre-fort numérique »

[⏱ 45:00 — cible 50:00]

Le message clé ici est simple: le coffre-fort n'est pas à côté du service notarial. Il est la continuité naturelle de la transaction notariale.

[MONTRER: 02-t02-integration-architecture]

- Transmission automatique entre les deux volets
- pas de double téléversement
- pas de copie sauvage
- référence interne sécurisée
- une seule source documentaire
- zéro re-téléversement

- Ce que cela change concrètement
- moins d'erreurs
- moins de confusion sur la bonne version
- mêmes permissions qui suivent le document
- même piste d'audit qui suit le document

[MONTRER: 03-t02-blockchain-flow]

- Chaîne d'intégrité continue
- empreinte BLAKE2b côté coffre-fort et journal
- certification documentaire avec empreinte SHA-256 dans le flux de signature
- ancrage Hyperledger Fabric
- scellement électronique
- dépôt final dans le coffre-fort

- Expérience utilisateur unifiée
- authentification unique
- accès au coffre-fort depuis la navigation principale
- accès aussi depuis la vue de suivi du dossier
- réutilisation d'un document du coffre-fort dans une nouvelle demande
- sans re-téléverser

- Isolation et sécurité des données
- trois schémas logiques PostgreSQL distincts
- filtrage systématique par propriétaire
- partages explicites
- partages temporaires
- partages révocables
- un citoyen ne voit jamais les documents d'un autre

Phrase à dire:

Autrement dit, un document entre une fois dans l'écosystème, puis il circule de manière contrôlée jusqu'à l'archivage final.

L'intégrité est garantie par l'architecture. Maintenant, comment la valide-t-on? Parlons de la stratégie de tests automatisés.

---

## 6. Approche d'essais automatisés et de validation de la solution

[⏱ 50:00 — cible 60:00]

Sur Privara en production, nos métriques DORA montrent un déploiement quotidien, un délai de livraison inférieur à 4 heures, et un taux d'échec inférieur à 5 %. Le GPSN hérite de cette même discipline dès le premier sprint.

- Pas des tests ajoutés à la fin
- une validation continue dès le départ

[MONTRER: 12-t06-test-strategy-pyramid]

- Pyramide de tests à quatre niveaux
- unitaires avec pytest et Jest
- intégration pour API, flux et intercomposants
- sécurité avec SAST, DAST, audit de dépendances
- UI et E2E avec Playwright
- contrôles WCAG intégrés
- couverture cible: 90 % et plus

- Charge et volumétrie validées avec Locust
- mode distribué
- montée de 0 à 3 500 sessions en 10 minutes
- plateau de 30 minutes
- P95 sous 5 secondes
- taux d'erreur sous 1 %
- jeux de données réalistes
- testament 30 pages, 5 versions
- transaction immobilière 10 documents de 8 pages
- titres numérisés
- projection à trois ans
- 2 700 notaires aujourd'hui
- 3 594 notaires projetés

[MONTRER: 04-t03-deployment-pipeline]

- Pipeline CI/CD
- GitHub Actions
- lint
- tests
- build des images
- publication contrôlée dans Azure Container Registry
- aucune fusion sans pipeline vert

- Reproductibilité locale
- `make test`
- `make test-backend`
- `make test-frontend`
- `make test-e2e`
- `make lint`

[MONTRER: 16-t03-integration-continue]

- Même chaîne en local et en CI
- très important pour la reprise autonome par un tiers

- Observabilité complète
- OpenTelemetry pour les traces corrélées
- Prometheus pour les métriques
- Grafana pour les tableaux de bord SLA
- Loki pour les journaux
- Web Vitals pour le rendu perçu côté interface

- La piste d'audit sert aussi de couche de validation
- journal append-only
- chaînage BLAKE2b
- revalidation quotidienne de la chaîne
- ancrage mensuel de la racine de Merkle dans Hyperledger Fabric

Si on doit couper:

- garder la pyramide
- garder Locust + P95 < 5 s
- garder pipeline vert obligatoire

Voilà pour l'approche. Avant vos questions, je veux vous montrer en une minute comment on sécurise la phase PoC et la validation autonome.

---

## 7. Varia et période de questions

[⏱ 60:00 — cible 90:00]

### 7A. Point proactif avant les questions — stratégie de PoC

[MONTRER: 11-t05-poc-phases]

- Trois jalons contractuels clairs
- S6
- architecture initiale
- authentification
- première connexion blockchain
- S12
- services notariaux complets de bout en bout
- parcours citoyen et notaire
- S16
- intégration blockchain complète
- coffre-fort numérique
- dépôt, consultation, partage

- Validation autonome par un tiers
- `docker compose up --build`
- moins de 5 minutes
- `make validate`
- vérification environnement
- démarrage
- tests
- rapport de validation
- jeux de données préchargés
- simulateurs locaux pour Interac, ConsignO, calendriers, blockchain

Phrase à dire:

C'est exactement l'approche qui a fonctionné pour CryptoGuard: l'évaluateur a pu déployer, tester et valider sans nous appeler.

[⏱ 63:00]

### 7B. Questions anticipées — réponses courtes prêtes

#### Q1. Pourquoi Django plutôt que Node.js?

- Le devis suggérait Node.js
- il ne l'imposait pas
- choix défensif et assumé
- plus de 50 projets Django livrés en 8 ans
- même pile que CryptoGuard
- ORM robuste
- auth native solide
- signaux et middleware utiles pour l'audit
- Python lisible pour l'équipe ULaval
- le résultat: une équipe qui maîtrise parfaitement sa pile, pas une équipe qui apprend pendant le mandat

Phrase d'ouverture:

On a choisi la pile qui réduit le plus le risque d'exécution, pas celle qui sonne le plus moderne sur une diapositive.

#### Q2. Comment gérez-vous une indisponibilité de l'API blockchain?

- file d'attente RabbitMQ dédiée
- transactions persistantes
- retentatives automatiques
- délai progressif
- jitter
- classification des erreurs
- temporaire
- permanente
- configuration
- réseau
- acquittement seulement après succès confirmé
- pas de perte de transaction

Phrase d'ouverture:

Le principe, c'est simple: on ne perd rien, on classe l'erreur correctement, puis on reprend automatiquement quand c'est pertinent.

#### Q3. Comment couvrez-vous la Loi 25 et les règlements applicables?

- cartographie réglementaire dès le cadrage
- obligations rattachées aux volets fonctionnels
- consultant notarial externe pour valider les workflows
- anonymisation sous 30 jours après suppression de compte
- minimisation des données
- journaux protégés en intégrité
- démarche SMSI alignée SOC 2 via Vanta

#### Q4. Comment assurez-vous l'accessibilité SGQRI 008 3.0 / WCAG 2.1 AA?

- accessibilité intégrée dès la conception
- pas une vérification de fin de projet
- audits axe-core à chaque sprint
- navigation clavier complète
- compatibilité lecteurs d'écran
- vérifications Playwright incluses dans la chaîne

#### Q5. Quelle est votre stratégie de transfert de connaissances?

- code livré
- droits d'exploitation complets
- guides de démonstration par module
- README et documentation locale
- infrastructure en code avec Terraform
- pas de configuration manuelle cachée
- formation prévue en phase d'acceptation

#### Q6. Comment synchroniser les calendriers pour 2 700 notaires?

- synchronisation bidirectionnelle Google Calendar / Outlook
- seul le statut occupé / disponible remonte dans GPSN
- pas de détails privés exposés
- mécanisme de réconciliation en cas d'interruption
- double contrôle avant réservation

#### Q7. Que se passe-t-il si la phase 0 révèle un problème majeur?

- le PoC sert justement de porte contractuelle
- trois jalons progressifs
- problèmes détectés tôt
- le devis prévoit 5 jours ouvrables pour corriger une non-conformité
- notre approche: démonstrations continues avant le jalon final

#### Q8. Pouvez-vous détailler l'ancrage blockchain des journaux d'audit?

- tâche Celery périodique
- calcul de la racine de Merkle du lot mensuel
- soumission à l'API REST Hyperledger Fabric
- identifiant de transaction consigné dans la table d'audit
- vérification croisée possible
- racine locale
- racine ancrée
- fréquence configurable
- mensuel = minimum contractuel

### 7C. Si les questions se calment

- proposer d'approfondir la sécurité applicative
- OWASP Top 10
- proposer d'approfondir le pipeline de déploiement
- proposer d'approfondir la stratégie de formation et de reprise

### 7D. Phrase de clôture

Merci. Si vous le souhaitez, on peut maintenant revenir sur l'architecture, refaire le scénario de testament simple, ou entrer plus profondément dans la chaîne de preuve blockchain.

---

## Notes présentateur

- Si le temps serre, compresser d'abord 3D intégrations, puis héritiers numériques, puis la vue CI détaillée
- CryptoGuard: poser fortement en section 2, rappeler sobrement en 3B, 3C, 5 et Q&A
- Ne pas en faire un refrain
- Visuels essentiels si le deck doit être resserré:
- `05-f01-functional-module-map`
- `01-t01-architecture-overview`
- `06-f01-demande-service-flow`
- `03-t02-blockchain-flow`
- `02-t02-integration-architecture`
- `05-f01-coffre-fort-vue-principale`
- `01-f01-televersement-stockage`
- `12-t06-test-strategy-pyramid`
- `04-t03-deployment-pipeline`
- `11-t05-poc-phases`
