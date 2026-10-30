# Vikunja

Stack Docker Compose pour Vikunja, application de gestion de tâches accessible derrière Traefik. PostgreSQL stocke les données et un volume séparé conserve les pièces jointes et fichiers téléversés.

## Services

- `vikunja` : interface web et API, publiée sur le port interne `3456`.
- `db` : base PostgreSQL 18, accessible uniquement sur le réseau privé de cette stack.

## Configuration

Copier `.env.example` vers `.env`, puis renseigner les valeurs suivantes. Le fichier `.env` est ignoré par Git.

| Variable | Description |
| --- | --- |
| `VIKUNJA_DOMAIN` | Nom DNS utilisé par Traefik, par exemple `vikunja.home.lan`. |
| `VIKUNJA_SERVICE_SECRET` | Secret aléatoire utilisé par Vikunja pour signer les sessions. |
| `VIKUNJA_FILES_DATA_DIR` | Répertoire hôte persistant des pièces jointes. |
| `VIKUNJA_DB_DATA_DIR` | Répertoire hôte persistant de PostgreSQL. |
| `VIKUNJA_POSTGRES_DB` | Nom de la base PostgreSQL. |
| `VIKUNJA_POSTGRES_USER` | Utilisateur PostgreSQL dédié à Vikunja. |
| `VIKUNJA_POSTGRES_PASSWORD` | Mot de passe de cet utilisateur. |

Générer les secrets avec `openssl rand -hex 32`. Créer les répertoires de données avant le démarrage et donner au répertoire de fichiers les droits d’écriture pour l’UID `1000`, utilisé par l’image Vikunja officielle :

```sh
mkdir -p "$VIKUNJA_FILES_DATA_DIR" "$VIKUNJA_DB_DATA_DIR"
sudo chown 1000 "$VIKUNJA_FILES_DATA_DIR"
```

Démarrer la stack depuis ce répertoire avec `docker compose up -d`. Définir `VIKUNJA_SERVICE_PUBLICURL` sur l’URL HTTPS publique permet au client web de joindre correctement l’API derrière le proxy.

Après la création des comptes nécessaires, désactiver l’inscription publique dans la configuration de Vikunja si elle n’est plus requise.

## Documentation officielle

- [Docker Compose complet et configuration Traefik](https://vikunja.io/docs/full-docker-example/)
- [Parcours de démarrage Docker](https://vikunja.io/docs/docker-walkthrough/)
- [Options de configuration](https://vikunja.io/docs/config-options/)
