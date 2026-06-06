# Gitlab-runner Stack

## Role
Execution agent for running CI/CD pipeline jobs in GitLab.

## External Links
- **Official Project**: [https://docs.gitlab.com/runner/](https://docs.gitlab.com/runner/)
- **Docker Image Maintainer**: [GitLab](https://hub.docker.com/r/gitlab/gitlab-runner)

## Configuration Variables
Define the following environment variables in your local `.env` file:

| Variable Name | Description | Placeholder / Default |
| :--- | :--- | :--- |
| `GITLAB_RUNNER_DATA_DIR` | Persistent host directory path for volume mount: GITLAB_RUNNER_DATA_DIR. | *None (empty)* |

