# Platform as Code

A fully automated three-tier platform provisioned by **Terraform**, configured by **Ansible**, deployed by **Docker**, and shipped by **GitHub Actions**. Built to learn what "infrastructure as code" actually means in practice — not just the tools, but the workflows, trade-offs, and failure modes that come with them.

[![CI](https://github.com/Alexander76678/platform-as-code/actions/workflows/ci.yml/badge.svg)](https://github.com/Alexander76678/platform-as-code/actions/workflows/ci.yml)
[![CD](https://github.com/Alexander76678/platform-as-code/actions/workflows/cd.yml/badge.svg)](https://github.com/Alexander76678/platform-as-code/actions/workflows/cd.yml)
[![Terraform](https://img.shields.io/badge/Terraform-%E2%89%A51.10-7B42BC?logo=terraform)](https://www.terraform.io/)
[![Ansible](https://img.shields.io/badge/Ansible-core-EE0000?logo=ansible)](https://www.ansible.com/)
[![Docker](https://img.shields.io/badge/Docker-ready-2496ED?logo=docker)](https://www.docker.com/)

---

## Table of Contents

- [What This Is](#what-this-is)
- [Architecture](#architecture)
- [Quick Start](#quick-start)
- [Tech Stack](#tech-stack)
- [Repository Layout](#repository-layout)
- [The Build Journey](#the-build-journey)
- [Design Decisions & Trade-offs](#design-decisions--trade-offs)
- [What Broke and What I Learned](#what-broke-and-what-i-learned)
- [CI/CD Pipeline](#cicd-pipeline)
- [On OIDC and Static Keys](#on-oidc-and-static-keys)
- [Known Limitations](#known-limitations)
- [Roadmap](#roadmap)
- [Author](#author)

---

## What This Is

- **Three-tier application** — Nginx load balancer, two FastAPI app servers, MongoDB
- **Provisioned with Terraform** — VPC, subnet, gateway, security group, key pair, EC2 instances
- **Configured with Ansible** — four idempotent roles (`docker`, `app`, `database`, `loadbalancer`)
- **Zero-downtime rolling deploys** — `serial: 1` with drain → restart → health-check → rejoin
- **Full CI/CD** — linting and validation on every PR; build, push, and deploy on every merge to `main`
- **Teardown in one command** — `terraform destroy` removes everything

---

## Architecture

```text
┌───────────────────────────────────────────────┐
│                   INTERNET                    │
└───────────────────────┬───────────────────────┘
                        │ :80
                        ▼
                 ┌──────────────┐
                 │      lb      │  ← Public IP
                 │  Nginx :80   │
                 └──────┬───────┘
                        │  VPC private network
           ┌────────────┴────────────┐
           ▼                         ▼
    ┌─────────────┐           ┌─────────────┐
    │    app1     │           │    app2     │
    │   FastAPI   │           │   FastAPI   │
    │    :8000    │           │    :8000    │
    └──────┬──────┘           └──────┬──────┘
           │                         │
           └────────────┬────────────┘
                        ▼
                 ┌──────────────┐
                 │      db      │
                 │   MongoDB    │
                 │    :27017    │
                 └──────────────┘
```

| Tier | Host | Role |
|------|------|------|
| Load balancer | `lb` | Nginx reverse proxy on :80 |
| Database | `db` | MongoDB on :27017 (VPC-only) |
| App servers | `app1`, `app2` | FastAPI in Docker on :8000 |

---

## Quick Start

```bash
# 1. Provision infrastructure
cd terraform
terraform init
terraform apply -auto-approve

# 2. Generate the Ansible inventory from Terraform outputs
cd ..
./terraform/render_inventory.sh

# 3. Configure servers and deploy the app
ansible-playbook site.yml

# 4. Test it
curl http://<lb-public-ip>/visit
curl http://<lb-public-ip>/visit   # counter should increment

# 5. Tear it all down
cd terraform && terraform destroy -auto-approve
```

> The app image is pre-built and pushed to GHCR by the CD workflow, so `site.yml` pulls the latest image rather than building one locally.

---

## Tech Stack

| Layer | Tool | Why |
|-------|------|-----|
| Provisioning | Terraform ≥ 1.10 | Reproducible, versionable; `terraform destroy` is the ultimate cost-control lever |
| Configuration | Ansible-core | Agentless, role-based, idempotent — same tool for both servers and (in a future version) network devices |
| App | FastAPI + PyMongo | Small and fast; the infra is the point |
| Containerization | Docker | The app ships as one artifact that runs identically everywhere |
| Image registry | GHCR | Free for public images, integrates with GitHub Actions and PAT auth |
| Database | MongoDB 7.0 | Document model fits the "visit" counter demo; also a chance to learn a NoSQL system that i have a module about in school|
| Load balancer | Nginx | Upstream pools, passive health checks, graceful reloads |
| CI/CD | GitHub Actions | Native to the repo, no extra service to wire up |
| Cloud | AWS EC2 + VPC | Free tier covers the lab; real cloud experience beats local VMs |

---

## Repository Layout

```text
platform-as-code/
├── app/
│   ├── main.py                    # FastAPI: /health, /visit
│   ├── requirements.txt
│   └── Dockerfile
│
├── terraform/
│   ├── providers.tf               # AWS provider, default tags
│   ├── variables.tf
│   ├── main.tf                    # VPC, subnet, SG, key pair, EC2
│   ├── outputs.tf                 # IPs for Ansible
│   └── render_inventory.sh        # Terraform outputs → hosts.yml
│
├── inventory/
│   ├── hosts.yml                  # Generated by render_inventory.sh
│   └── ci/hosts.yml               # Dummy inventory for --syntax-check
│
├── group_vars/
│   └── all/
│       ├── vars.yml               # Non-secret vars
│       └── vault.yml              # Encrypted (GHCR token)
│
├── roles/
│   ├── docker/                    # Install Docker from official repo
│   ├── app/                       # Deploy the FastAPI container
│   ├── database/                  # MongoDB 7.0
│   └── loadbalancer/              # Nginx + upstream template
│
├── site.yml                       # Provisioning: install + configure
├── deploy.yml                     # Rolling deploy: serial: 1
│
└── .github/workflows/
    ├── ci.yml                     # Lint, validate on PR
    └── cd.yml                     # Build, push, deploy on main
```

---

## The Build Journey

### Phase 0 — The wrong start

I planned to run this locally with Vagrant + VirtualBox on an 8 GB Windows laptop i know crazy. four VMs never got past `vagrant up` The lesson: cloud is a cheaper lab than your laptop when the laptop is the bottleneck.

### Phase 1 — Pivot to AWS

Signed up for AWS Free Tier, set a zero-spend budget alert, and built the lab by clicking through the console. Three `t3.micro` instances in one VPC. and of course i needed to stop the instances when im done to save the budget.

### Phase 2 — The app

A FastAPI app with two endpoints: `/health` returns a constant JSON, `/visit` writes a document to MongoDB and returns the count. Dockerized and pushed to GHCR. yes small but the infra is the point.

### Phase 3 — Ansible roles

`docker` and `app` roles first. The moment it felt real was the second `ansible-playbook site.yml` run: `changed=0` across every task. and i learned about ansible's idempotency.

### Phase 4 — The rolling deploy

MongoDB and Nginx added. Then `deploy.yml`: `serial: 1` per host, drain from Nginx upstream → wait 3 s → pull new image → recreate container → poll `/health` until 200 → rejoin upstream → reload Nginx. I ran a continuous `curl` loop in one terminal while the deploy ran in another. The 200s never broke. That was the single most satisfying moment of the project.


https://github.com/user-attachments/assets/2b06e337-e5da-41be-a73e-19f0bce0ccc7


### Phase 5 — Terraform

Replaced every manual console click with `terraform apply`. The tricky part was the handoff: Terraform's outputs feed a small `render_inventory.sh` that generates `hosts.yml`. No `local-exec` provisioner, no Ansible dependency inside Terraform — just two tools and a file between them.

### Phase 6 — CI/CD

The "thousand errors" phase. YAML that parses locally but fails in Actions. Secrets that don't resolve.  Every error was a lesson in how CI environments differ from local ones. The final pipeline: lint + validate on PRs, build + deploy on merges to `main`.

---

## Design Decisions & Trade-offs

| Decision | Rationale | Production alternative |
|----------|-----------|------------------------|
| Static AWS keys in GitHub Secrets | OIDC unavailable on the AWS Free Tier plan | OIDC with short-lived role credentials |
| No MongoDB authentication | VPC isolation only — port 27017 not exposed publicly | SCRAM auth + TLS + credentials in Ansible Vault |

Naming the trade-off is more valuable than pretending it doesn't exist.

---

## What Broke and What I Learned

- **Vagrant wouldn't boot VMs on 8 GB RAM.** First a VirtualBox serial-port path error, then repeated OOM failures. Learned that hardware is a legitimate constraint and pivoting to cloud was the right engineering decision.
- **Terraform's `for_each` over a local map vs. three separate `aws_instance` resources.** Refactored mid-project. Adding another VM became one line instead of twenty.
- **GitHub Actions YAML is not the same as Ansible YAML.** 

---

## CI/CD Pipeline

### `ci.yml` — runs on every pull request to `main`

1. `terraform fmt -check` — formatting gate
2. `terraform validate` — syntax and provider schemas
3. `tflint` — best-practice linting
4. `yamllint` + `ansible-lint` — Ansible code quality
5. `ansible-playbook site.yml --syntax-check -i inventory/ci/hosts.yml` — parse-only, no cloud calls

### `cd.yml` — runs on every push to `main`

1. **Build job** — builds the FastAPI Docker image, pushes to `ghcr.io/<owner>/platform-as-code:latest` and `:<git-sha>`
2. **Deploy job** — `terraform apply` → `render_inventory.sh` → `ansible-playbook site.yml` → `ansible-playbook deploy.yml`

---

## On OIDC and Static Keys

This project uses static IAM credentials stored as GitHub Secrets. That's a deliberate choice, not an oversight: OIDC federation is not available on the AWS Free Tier plan this project is built on. The IAM user backing the keys has a least-privilege policy limited to the resources Terraform creates. In a paid account, OIDC with a GitHub-assumed role would replace every static key with short-lived tokens — a much smaller blast radius if leaked.


---

## Known Limitations

- **No automated tests.** No `pytest` for the FastAPI app, no Molecule for the Ansible roles. CI validates syntax and style, not behavior.
- **MongoDB without authentication.** Relies entirely on security-group isolation.
- **No backup or restore story.** `terraform destroy` deletes the database with no snapshot.
- **`deploy.yml` is not fully idempotent.** Because the drain-rejoin template changes each time, a second consecutive run still reports `changed=1` per host. Functionally correct, but not "clean idempotency."
- **CI does not run Ansible against real hosts.** The `--syntax-check` step is parse-only. A full run against ephemeral infrastructure would need either ephemeral AWS sandboxing or a `--check --diff` stage against a known-good environment.

---

## Roadmap

- [ ] Add Redis as a session cache layer between the app and MongoDB (started, paused)
- [ ] Add `pytest` for the FastAPI app and Molecule for the Ansible roles
- [ ] Add SCRAM authentication and TLS to MongoDB
- [ ] Deploy the same app on k3s and write a comparison document ("VMs vs Kubernetes")
- [ ] Integrate the InfluxDB + Grafana monitoring stack from my other project to visualize the four VMs
- [ ] Add Grafana alerting to trigger automated Ansible remediation (the "self-healing" experiment)

---

## Author

**Alexander** — [@Alexander76678](https://github.com/Alexander76678)

Built as part of a self-directed journey into DevOps and infrastructure engineering. The trade-offs in this README are deliberate; the limitations are honest; the rolling deploy is real.
