# Portainer Stacks Migrator to Git

Ce projet contient un script Python autonome pour exporter proprement toutes les configurations de vos **stacks Portainer** (fichiers `docker-compose.yml` et variables d'environnement) afin de les versionner dans un dépôt Git.

## Fonctionnalités

- 🚀 **Zéro dépendance** : Fonctionne avec la bibliothèque standard Python 3. Pas besoin de `pip` ni d'environnement virtuel.
- 🔐 **Sécurité renforcée** :
  - Génère un fichier `.env` avec les valeurs réelles de vos variables d'environnement.
  - Génère un fichier `.env.example` avec les clés uniquement (sans les valeurs sensibles) pour que vous puissiez le commiter dans Git de façon sécurisée.
  - Crée automatiquement un fichier `.gitignore` racine qui exclut les fichiers `.env` afin d'éviter les fuites accidentelles de mots de passe ou clés d'API.
- 🔑 **Double méthode d'authentification** : Supporte les jetons d'accès API Portainer (recommandé) ou l'authentification classique par Identifiant/Mot de passe.
- 🛡️ **Support SSL flexible** : Possibilité d'ignorer la vérification SSL si votre instance Portainer utilise des certificats auto-signés.
- 🗂️ **Structure propre** : Organise l'export sous la forme `nomstack/docker-compose.yml`.

---

## Stacks Hébergées dans ce Dépôt

Voici la liste complète des stacks Docker Compose gérées dans ce dépôt :

| Stack | Description | Service principal |
| :--- | :--- | :--- |
| [**adguard**](./adguard/README.md) | Bloqueur de publicités et traqueurs au niveau DNS | AdGuard Home |
| [**audiomuse_ai**](./audiomuse_ai/README.md) | Suite d'outils audio alimentée par l'IA | Audiomuse AI |
| [**beszel**](./beszel/README.md) | Outil léger de monitoring et tableaux de bord de serveurs | Beszel Hub |
| [**beszel-agent**](./beszel-agent/README.md) | Agent de monitoring léger pour Beszel | Beszel Agent |
| [**bookmarks**](./bookmarks/README.md) | Gestionnaire de favoris et partage de liens | Shaarli |
| [**cloudflared**](./cloudflared/README.md) | Connecteur sécurisé pour tunnels Cloudflare | Cloudflare Tunnel |
| [**code-server**](./code-server/README.md) | Environnement VS Code accessible via navigateur | VS Code Server |
| [**crowdsec**](./crowdsec/README.md) | Moteur de détection d'intrusions et pare-feu collaboratif | CrowdSec |
| [**dockhand**](./dockhand/README.md) | Automatisation de la gestion des conteneurs Docker | Dockhand |
| [**freshrss**](./freshrss/README.md) | Agrégateur et lecteur de flux RSS auto-hébergé | FreshRSS |
| [**frigate**](./frigate/README.md) | Système de NVR pour caméras avec détection d'objets par IA | Frigate |
| [**gitea**](./gitea/README.md) | Serveur Git ultra-léger et auto-hébergé | Gitea |
| [**gitlab**](./gitlab/README.md) | Plateforme DevOps complète et gestion de dépôt Git | GitLab |
| [**gitlab-runner**](./gitlab-runner/README.md) | Exécuteur de tâches CI/CD pour GitLab | GitLab Runner |
| [**glance**](./glance/README.md) | Tableau de bord personnel personnalisable | Glance Dashboard |
| [**grafana**](./grafana/README.md) | Plateforme d'analyse et de visualisation de métriques | Grafana |
| [**homeassistant**](./homeassistant/README.md) | Système domotique libre pour contrôler votre maison | Home Assistant |
| [**immich**](./immich/README.md) | Solution d'auto-hébergement haute performance de photos & vidéos | Immich |
| [**karakeep**](./karakeep/README.md) | Gestionnaire de favoris performant avec recherche | Karakeep |
| [**manyfold**](./manyfold/README.md) | Gestionnaire de fichiers 3D pour l'impression 3D | Manyfold |
| [**minio**](./minio/README.md) | Serveur de stockage d'objets compatible Amazon S3 | MinIO |
| [**netbox**](./netbox/README.md) | Outil d'inventaire d'infrastructure réseau et DCIM | NetBox |
| [**netdata**](./netdata/README.md) | Monitoring des performances système en temps réel | Netdata |
| [**nextcloud**](./nextcloud/README.md) | Plateforme collaborative de stockage et partage de fichiers | Nextcloud |
| [**ng**](./ng/README.md) | Suite de serveurs multimédias et de téléchargement | Arr Stack |
| [**ollama**](./ollama/README.md) | Serveur d'inférence local de modèles d'IA (LLM) | Ollama |
| [**omni-tools**](./omni-tools/README.md) | Ensemble de petits utilitaires pratiques du quotidien | Omni-Tools |
| [**openproject**](./openproject/README.md) | Logiciel de gestion de projet collaboratif libre | OpenProject |
| [**librespeed**](./librespeed/README.md) | Testeur de bande passante réseau local privé | LibreSpeed |
| [**overleaf**](./overleaf/README.md) | Éditeur LaTeX collaboratif en ligne auto-hébergé | Overleaf (ShareLaTeX) |
| [**photoprism**](./photoprism/README.md) | Gestionnaire de photos alimenté par l'IA | PhotoPrism |
| [**plex**](./plex/README.md) | Serveur multimédia de diffusion de films et séries | Plex Media Server |
| [**scanopy**](./scanopy/README.md) | Solution de numérisation et archivage de documents | Scanopy |
| [**spotify-to-plex**](./spotify-to-plex/README.md) | Outil de synchronisation de playlists Spotify vers Plex | Spotify to Plex |
| [**stable-diffusion**](./stable-diffusion/README.md) | Générateur d'images par IA | Stable Diffusion WebUI |
| [**todo**](./todo/README.md) | Gestionnaire de tâches et de listes de choses à faire | Donetick |
| [**trilium**](./trilium/README.md) | Base de connaissances hiérarchique personnelle pour notes | Trilium Notes |
| [**tududi**](./tududi/README.md) | Gestionnaire de tâches personnel ultra-simple | Tududi |
| [**vaultwarden**](./vaultwarden/README.md) | Gestionnaire de mots de passe compatible Bitwarden | Vaultwarden |
| [**watchtower**](./watchtower/README.md) | Automatisation des mises à jour des conteneurs Docker | Watchtower |

---

## Prérequis

- **Python 3.x** installé sur votre machine.
- Une instance **Portainer (CE ou EE)**.
- Un **Jeton d'accès API (API Key)** (généré dans votre Portainer sous *User settings* > *Access tokens*) **OU** vos identifiants de connexion.

---

## Utilisation

Rendez-vous dans le répertoire du script et lancez-le avec l'une des commandes suivantes :

### Option A : Authentification par Clé d'API (Recommandée & Sécurisée)

1. Obtenez votre clé d'API depuis l'interface Portainer (*Mon Compte / User settings* -> *Access Tokens*).
2. Lancez le script :

```bash
./export_portainer.py --url "https://portainer.votre-domaine.com" --token "ptr_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

### Option B : Authentification par Identifiant / Mot de passe

Le script vous demandera votre mot de passe de manière interactive et sécurisée :

```bash
./export_portainer.py --url "https://portainer.votre-domaine.com" --username "mon_admin"
```

### Options Supplémentaires

- **Certificats SSL auto-signés** : Si votre Portainer utilise HTTPS avec un certificat non vérifié, ajoutez l'option `--insecure` :
  ```bash
  ./export_portainer.py --url "https://192.168.1.100:9443" --token "..." --insecure
  ```
- **Spécifier le dossier de destination** : Par défaut, l'export se fait dans le dossier courant. Vous pouvez définir une autre destination avec `--output` :
  ```bash
  ./export_portainer.py --url "..." --token "..." --output "./stacks-export"
  ```

---

## Configuration des Git Hooks (Prévention des Fuites de Secrets)

Pour éviter de commiter accidentellement des fichiers contenant des secrets (comme les fichiers `.env` réels) ou des informations sensibles dans votre dépôt Git, un système de détection des fuites est configuré dans le dossier `.githooks`.

Pour activer cette protection automatique dans votre dépôt local, exécutez les commandes suivantes depuis la racine de votre projet :

```bash
# 1. Rendre les scripts de hooks exécutables
chmod +x .githooks/pre-commit .githooks/post-commit .githooks/git-leak-shield.py

# 2. Configurer Git pour utiliser le dossier .githooks
git config core.hooksPath .githooks
```

### Fonctionnement

- **`pre-commit`** : Analyse automatiquement vos fichiers indexés (`staged`) avant chaque validation. Si un fichier `.env`, un secret, une clé d'API ou une donnée sensible est détecté, le commit est immédiatement bloqué.
- **`post-commit`** : Affiche un message de confirmation une fois le commit validé en toute sécurité.

---

## Structure du Dépôt après Export

Une fois l'export terminé, votre dossier ressemblera à ceci :

```text
gitea/
├── export_portainer.py
├── README.md
├── .gitignore               # Protège vos secrets en ignorant tous les .env
├── stack-nginx/
│   ├── docker-compose.yml   # Fichier compose brut
│   ├── .env                 # Variables réelles de Portainer (Ignoré par Git)
│   └── .env.example         # Gabarit vide prêt à être commité
└── stack-database/
    ├── docker-compose.yml
    ├── .env
    └── .env.example
```

---

## Guide de Migration vers Git & Portainer (Sans coupure)

Voici la méthode complète pour versionner vos configurations et transformer vos stacks Portainer existantes en stacks gérées par Git, **sans perte de données et avec moins de 10 secondes de coupure**.

---

### Étape 1 : Initialiser et pousser le dépôt Git

Grâce au fichier `.gitignore` généré à la racine, vos variables d'environnement réelles (`.env`) ne seront jamais poussées vers Git. Seuls vos fichiers de déploiement et leurs gabarits (`.env.example`) seront versionnés.

```bash
# 1. Initialiser le dépôt Git local
git init

# 2. Ajouter tous les fichiers (les .env réels sont automatiquement exclus)
git add .

# 3. Effectuer le premier commit
git commit -m "feat: migration initiale des stacks Portainer"

# 4. Configurer le dépôt distant (ex: Gitea) et pousser les fichiers
git remote add origin <URL_DE_VOTRE_DEPOT_GIT>
git branch -M main
git push -u origin main
```

---

### Étape 2 : Comprendre la persistance des données

> [!NOTE]
> Dans Docker, les bases de données et fichiers de configuration sont stockés dans des **volumes** ou des **dossiers locaux (bind mounts)**.
> Supprimer une stack dans Portainer arrête uniquement les conteneurs mais **ne supprime pas vos données**. Le fait de recréer la stack à l'identique re-connectera instantanément les conteneurs à vos volumes existants.

---

### Étape 3 : Migrer une stack existante vers le mode Git

Pour passer une stack du mode "Web Editor" au mode "Git Repository" sans perdre de configurations :

1. **Copier les variables d'environnement** :
   - Ouvrez le dossier local de la stack exportée (ex: `./plex/`).
   - Ouvrez le fichier `.env` contenant les variables réelles et **copiez l'intégralité de son contenu** (`CLE=VALEUR`).

2. **Supprimer l'ancienne stack dans Portainer** :
   - Dans Portainer, ouvrez la stack correspondante et cliquez sur **Delete this stack** (les conteneurs s'arrêtent, mais les données persistent).

3. **Recréer la stack en mode Git** :
   - Cliquez immédiatement sur **Add stack** en haut à droite.
   - Configurez les champs suivants :
     - **Name** : Saisissez exactement le **même nom** que l'ancienne stack (ex: `plex`).
     - **Build method** : Sélectionnez **Repository**.
     - **Repository URL** : Saisissez l'URL HTTP/SSH de votre dépôt Git (ex: `https://gitea.home.lan/pascal/stacks.git`).
     - **Repository reference** : Saisissez votre branche (ex: `refs/heads/main`).
     - **Compose path** : Spécifiez le chemin exact du fichier (ex: `plex/docker-compose.yml`).
   - Dans la section **Environment variables** :
     - Cliquez sur le bouton **Advanced mode** (en haut à droite de la section).
     - **Collez directement** l'intégralité du contenu du fichier `.env` copié à l'étape 1.
   - Cliquez sur **Deploy the stack**.

Docker va recréer la stack en quelques secondes. Vos conteneurs redémarreront à l'identique, raccordés à leurs volumes existants, mais seront désormais connectés à votre Git pour toutes les futures mises à jour !

