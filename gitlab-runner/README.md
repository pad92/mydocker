# Gitlab-runner Stack

This stack deploys the following services:

## 1. GitLab Runner (`gitlab-runner`)

### Role
Local CI/CD pipeline build executor for GitLab projects.

### External Links
- **Official Project**: [https://docs.gitlab.com/runner/](https://docs.gitlab.com/runner/)
- **Docker Image Maintainer**: [GitLab](https://hub.docker.com/r/gitlab/gitlab-runner)

### Service-Specific Configuration Variables
Define these environment variables which are unique to this service:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `GITLAB_RUNNER_DATA_DIR` | Persistent host directory path for volume mount: GITLAB_RUNNER_DATA_DIR. | *None (empty)* |

---

