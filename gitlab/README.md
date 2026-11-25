# Gitlab Stack

This stack deploys the following services:

## 1. GitLab Community Edition (`gitlab`)

### Role
Git project hoster, issue tracker, and DevOps integration server.

### External Links
- **Official Project**: [https://about.gitlab.com/](https://about.gitlab.com/)
- **Docker Image Maintainer**: [GitLab](https://hub.docker.com/r/gitlab/gitlab-ce)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `GITLAB_DATA_DIR` | Persistent host directory path for volume mount: GITLAB_DATA_DIR. | *None (empty)* |
| `GITLAB_HOSTNAME` | Required. Host name of the instance, used for `hostname` and `external_url`. | `git.example.lan` |
| `GITLAB_IP_2` | Network IP address configuration. | *None (empty)* |
| `GITLAB_LOGS_DATA_DIR` | Persistent host directory path for volume mount: GITLAB_LOGS_DATA_DIR. | *None (empty)* |

---

## Global / Other Variables
The following variables are defined in `.env.example` but are either global configs or not directly referenced in the compose services:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `GITLAB_IP_1` | Network IP address configuration. | *None (empty)* |
| `GITLAB_IP_3` | Network IP address configuration. | *None (empty)* |

