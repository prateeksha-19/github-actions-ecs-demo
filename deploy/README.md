# Deploy TranscriptionSuite Server to AWS ECS

CI/CD that **builds** the server image in GitHub Actions, **pushes** it to GitHub
Packages (GHCR) **and** Amazon ECR, then **deploys** it to **ECS Fargate**.

```
 push to main ─▶ GitHub Actions
                   │  build server image (server/docker/Dockerfile, PYTORCH_VARIANT=cpu)
                   ├─▶ push ▶ ghcr.io/<owner>/<repo>/transcriptionsuite-server   (GitHub Packages)
                   ├─▶ push ▶ <acct>.dkr.ecr.<region>.amazonaws.com/…-server      (Amazon ECR)
                   └─▶ deploy ▶ ECS Fargate service  ──▶ ALB :80 ──▶ /health
```

- **Compute:** Fargate, **CPU mode** (`PYTORCH_VARIANT=cpu`).
- **Auth:** GitHub **OIDC** → AWS IAM role. No AWS keys stored in GitHub.
- **Persistence:** EFS mounted at `/data` so transcription results survive redeploys.
- **Registries:** image lives in **both** GHCR and ECR; ECS pulls the ECR copy.

---

## Prerequisites

- An AWS account + credentials locally for Terraform (admin-ish, one-time).
- [Terraform](https://developer.hashicorp.com/terraform/downloads) ≥ 1.6 and the AWS CLI.
- Permission to set **Variables** on this GitHub repo.

---

## Step 1 — Provision infrastructure (Terraform)

```bash
cd deploy/terraform
cp terraform.tfvars.example terraform.tfvars   # edit: aws_region, github_repo
terraform init
terraform apply
```

This creates: VPC + subnets, ECR repo, ECS cluster + service + seed task
definition, ALB + target group, EFS, CloudWatch logs, and IAM (GitHub OIDC
provider + deploy role, ECS task roles).

> The service starts before any image exists in ECR, so its first tasks will
> fail to pull and retry. That's expected — Step 3 pushes the first real image.

### If the account already has a GitHub OIDC provider

An AWS account can only have **one** OIDC provider per URL. If you already have
one for `token.actions.githubusercontent.com`, set in `terraform.tfvars`:

```hcl
create_oidc_provider = false
```

## Step 2 — Wire Terraform outputs into GitHub repo Variables

```bash
terraform output      # shows every value below
```

In GitHub: **Settings ▸ Secrets and variables ▸ Actions ▸ Variables ▸ New repository variable**.
Create these (they are **Variables**, not Secrets — none are sensitive):

| Repo Variable         | Terraform output          |
| --------------------- | ------------------------- |
| `AWS_REGION`          | `aws_region`              |
| `AWS_DEPLOY_ROLE_ARN` | `github_actions_role_arn` |
| `ECR_REPOSITORY`      | `ecr_repository_name`     |
| `ECS_CLUSTER`         | `ecs_cluster_name`        |
| `ECS_SERVICE`         | `ecs_service_name`        |
| `ECS_TASK_FAMILY`     | `ecs_task_family`         |
| `CONTAINER_NAME`      | `container_name`          |

Quick copy/paste using the GitHub CLI:

```bash
cd deploy/terraform
gh variable set AWS_REGION          --body "$(terraform output -raw aws_region)"
gh variable set AWS_DEPLOY_ROLE_ARN --body "$(terraform output -raw github_actions_role_arn)"
gh variable set ECR_REPOSITORY      --body "$(terraform output -raw ecr_repository_name)"
gh variable set ECS_CLUSTER         --body "$(terraform output -raw ecs_cluster_name)"
gh variable set ECS_SERVICE         --body "$(terraform output -raw ecs_service_name)"
gh variable set ECS_TASK_FAMILY     --body "$(terraform output -raw ecs_task_family)"
gh variable set CONTAINER_NAME      --body "$(terraform output -raw container_name)"
```

### (Optional) Deploy approval gate

The `deploy` job targets a `production` environment. Either create it under
**Settings ▸ Environments** (add required reviewers for a manual gate), or remove
the `environment: production` line from `.github/workflows/deploy-ecs.yml` to
deploy unattended.

## Step 3 — Trigger the pipeline

Push to `main`, or run it manually:

```bash
gh workflow run "Build, Push & Deploy to ECS"
```

The workflow builds once, pushes to GHCR + ECR, then updates the ECS service and
waits for it to stabilize.

## Step 4 — Verify

```bash
cd deploy/terraform
curl "$(terraform output -raw health_url)"     # -> 200 once tasks are healthy
terraform output alb_url                        # service base URL
```

First deploy is slow: on cold start the container bootstraps CPU PyTorch wheels
into `/runtime` before `/health` returns 200. The ALB health-check grace period
and the container `startPeriod` are set to 900s to absorb this.

---

## Teardown

```bash
cd deploy/terraform
terraform destroy
```

EFS holds your transcription data — Terraform will delete it. Back it up first if
you care about it. The ECR repo is created with `force_delete = true`, so images
are removed too.

---

## Notes, trade-offs & next steps

- **CPU only.** Fargate has no GPU. Transcription runs on CPU (slower). For GPU,
  switch to the ECS **EC2 launch type** with `g4dn`-class instances and a GPU
  capacity provider — a larger change to `ecs.tf` + `network.tf`.
- **Cold-start bootstrap.** Every new task re-runs `uv sync` because `/runtime`
  is ephemeral. To make deploys fast, bake dependencies into the image at build
  time instead of bootstrapping at runtime. For the demo, ephemeral is fine.
- **Sizing.** `task_cpu`/`task_memory`/`ephemeral_storage_gib` are demo defaults.
  If tasks OOM or the health check never passes, raise them in `terraform.tfvars`.
- **HTTP only.** The ALB listens on `:80`. Add an HTTPS listener + ACM cert (and
  a DNS name) before exposing anything real.
- **Source of truth.** Terraform seeds the first task-definition revision; after
  that the **pipeline owns the image tag** and the service ignores Terraform
  drift on `task_definition` / `desired_count`. Change env/CPU/memory in
  `ecs.tf` and re-`apply` when you need structural changes.
- **GHCR image** is published in parallel for anyone who prefers pulling from
  GitHub Packages; ECS itself uses the ECR copy (no registry credentials needed).
```
