Absolutely, Michael — here is a **single, clean, repo‑ready Markdown file** that merges *everything* we designed:

- Architecture  
- Host‑by‑host execution plan  
- Dockerfile  
- Kubernetes manifests  
- Git repo structure  
- Playbooks + roles  
- SSH setup  
- Development workflow  

It’s formatted exactly the way you like: **one comprehensive, copy/paste‑ready Markdown document** you can drop directly into a GitHub repo as `README.md`.

---

# 📘 Ansible Runner on Kubernetes  
### Automated Weekly OS Updates for Lab Infrastructure  
**Author:** Michael  
**Environment:** Kubernetes + WSL2 + GitHub + Ubuntu/Proxmox hosts  
**Purpose:** Run Ansible playbooks from a containerized runner on a Kubernetes worker node using a CronJob.

---

# 🧭 Architecture Overview

This project deploys a **containerized Ansible Runner** into your Kubernetes cluster.  
It executes a weekly scheduled playbook that updates all Linux hosts in your lab.

### Components

| Component | Description |
|----------|-------------|
| **Custom Ansible Docker Image** | Latest Ansible, SSH client, Git, Python |
| **Git Repo (this repo)** | Playbooks, roles, inventory |
| **Kubernetes CronJob** | Runs weekly, clones repo, executes playbook |
| **ServiceAccount** | Identity for runner pod |
| **SSH Secret** | Dedicated SSH key for Ansible user |
| **nodeSelector** | Ensures runner runs on a specific worker node |
| **Target Hosts** | Ubuntu 24.04 servers, Proxmox node, Ubuntu Desktop |

---

# 🖥️ Host Responsibilities

| Host | IP | Purpose |
|------|----|---------|
| **WSL2** | 192.168.1.98 | Primary development workstation (VS Code, Docker, Git) |
| **devserver01** | 192.168.1.10 | Optional Linux build box (not required) |
| **devtools01** | 192.168.1.25 | Ubuntu Desktop VDI for GUI development |
| **K8-master** | — | Apply Kubernetes manifests, manage namespace |
| **K8 worker node** | — | Runs the Ansible Runner pod |

---

# 🧱 Step‑by‑Step Build Plan (Host‑Specific)

## 1. Create Git Repo (Playbooks + Inventory)
**Host:** WSL2  
**Files:** YAML only

```bash
mkdir lab-ansible-maintenance
cd lab-ansible-maintenance
git init
```

Repo structure:

```
lab-ansible-maintenance/
├── inventories/
│   └── lab/
│       ├── hosts.yml
│       └── group_vars/
│           └── all.yml
├── playbooks/
│   └── weekly-updates.yml
├── roles/
│   └── os_updates/
│       ├── tasks/main.yml
│       └── handlers/main.yml
└── README.md
```

---

## 2. Build Custom Ansible Docker Image  
**Host:** WSL2  
**File:** `Dockerfile`

```Dockerfile
FROM python:3.12-slim

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_NO_CACHE_DIR=1 \
    ANSIBLE_FORCE_COLOR=1 \
    PYTHONUNBUFFERED=1

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        openssh-client \
        git \
        ca-certificates \
        bash \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --upgrade pip && \
    pip install "ansible" "ansible-lint" "jinja2" "pyyaml"

RUN useradd -m -u 1000 ansible
USER ansible
WORKDIR /home/ansible

RUN mkdir -p /home/ansible/workdir /home/ansible/.ssh
VOLUME ["/home/ansible/workdir"]

ENTRYPOINT ["sleep", "infinity"]
```

Build + push:

```bash
docker build -t registry.example.com/lab/ansible-runner:latest .
docker push registry.example.com/lab/ansible-runner:latest
```

---

## 3. Generate SSH Keypair  
**Host:** WSL2  
**File:** None (shell only)

```bash
ssh-keygen -t ed25519 -f ansible_id_ed25519
```

- Private key → Kubernetes Secret  
- Public key → Installed on each managed host  

---

## 4. Configure Target Hosts  
**Host:** Each managed host  
**File:** None (shell only)

Run on:

- ubuntu-server-01  
- ubuntu-server-02  
- proxmox-01  
- ubuntu-desktop-01  

```bash
sudo adduser --disabled-password --gecos "" ansible
sudo mkdir -p /home/ansible/.ssh
sudo chmod 700 /home/ansible/.ssh
sudo chown ansible:ansible /home/ansible/.ssh

echo "ssh-ed25519 AAAA... ansible@lab" | sudo tee /home/ansible/.ssh/authorized_keys
sudo chmod 600 /home/ansible/.ssh/authorized_keys
sudo chown ansible:ansible /home/ansible/.ssh/authorized_keys

echo "ansible ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/ansible
sudo chmod 440 /etc/sudoers.d/ansible
```

---

## 5. Create Kubernetes Namespace, ServiceAccount, Secret  
**Host:** K8-master  
**Files:** YAML

```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: ansible-runner
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ansible-runner-sa
  namespace: ansible-runner
---
apiVersion: v1
kind: Secret
metadata:
  name: ansible-ssh-key
  namespace: ansible-runner
type: Opaque
data:
  id_rsa: REPLACE_WITH_BASE64_PRIVATE_KEY
```

Apply:

```bash
kubectl apply -f k8s/namespace-sa-secret.yaml
```

---

## 6. Deploy Kubernetes CronJob  
**Host:** WSL2 (write) → K8-master (apply)  
**File:** YAML

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: weekly-os-updates
  namespace: ansible-runner
spec:
  schedule: "0 3 * * 0"
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: ansible-runner-sa
          restartPolicy: Never
          nodeSelector:
            kubernetes.io/hostname: worker-01
          volumes:
            - name: ssh-key
              secret:
                secretName: ansible-ssh-key
                defaultMode: 0400
            - name: workdir
              emptyDir: {}
          initContainers:
            - name: git-clone-playbooks
              image: alpine/git:latest
              env:
                - name: GIT_REPO_URL
                  value: "https://github.com/YOURORG/lab-ansible-maintenance.git"
                - name: GIT_REPO_BRANCH
                  value: "main"
              volumeMounts:
                - name: workdir
                  mountPath: /workdir
              command:
                - /bin/sh
                - -c
                - |
                  git clone --depth 1 -b "$GIT_REPO_BRANCH" "$GIT_REPO_URL" /workdir/repo
          containers:
            - name: ansible-runner
              image: registry.example.com/lab/ansible-runner:latest
              imagePullPolicy: Always
              env:
                - name: ANSIBLE_REPO_PATH
                  value: /home/ansible/workdir/repo
                - name: ANSIBLE_INVENTORY
                  value: inventories/lab/hosts.yml
                - name: ANSIBLE_PLAYBOOK
                  value: playbooks/weekly-updates.yml
              volumeMounts:
                - name: ssh-key
                  mountPath: /home/ansible/.ssh
                  readOnly: true
                - name: workdir
                  mountPath: /home/ansible/workdir
              workingDir: /home/ansible/workdir/repo
              command:
                - /bin/bash
                - -c
                - |
                  chmod 600 /home/ansible/.ssh/id_rsa || true
                  ansible-playbook -i "$ANSIBLE_INVENTORY" "$ANSIBLE_PLAYBOOK"
```

Apply:

```bash
kubectl apply -f k8s/cronjob.yaml
```

---

## 7. Test the Runner  
**Host:** K8-master  
**File:** None

```bash
kubectl create job --from=cronjob/weekly-os-updates test-run
kubectl logs job/test-run
```

---

# 📁 Playbooks & Roles

## Inventory (`inventories/lab/hosts.yml`)

```yaml
all:
  children:
    ubuntu_servers:
      hosts:
        ubuntu-server-01.lab.local:
        ubuntu-server-02.lab.local:
    proxmox_nodes:
      hosts:
        proxmox-01.lab.local:
    desktops:
      hosts:
        ubuntu-desktop-01.lab.local:
```

## Group Vars (`inventories/lab/group_vars/all.yml`)

```yaml
ansible_user: ansible
ansible_ssh_private_key_file: /home/ansible/.ssh/id_rsa
ansible_ssh_common_args: "-o StrictHostKeyChecking=no"
```

## Role (`roles/os_updates/tasks/main.yml`)

```yaml
---
- name: Ensure apt cache is up to date
  ansible.builtin.apt:
    update_cache: yes
    cache_valid_time: 3600
  become: yes

- name: Upgrade all packages
  ansible.builtin.apt:
    upgrade: dist
    autoremove: yes
  become: yes
```

## Playbook (`playbooks/weekly-updates.yml`)

```yaml
---
- name: Weekly OS updates
  hosts: all
  become: yes
  gather_facts: yes

  roles:
    - os_updates
```

---

# 🧑‍💻 Development Workflow (WSL2)

```bash
git clone git@github.com:YOURORG/lab-ansible-maintenance.git
cd lab-ansible-maintenance
code .
```

Local testing:

```bash
ansible-playbook -i inventories/lab/hosts.yml playbooks/weekly-updates.yml --limit ubuntu-server-01.lab.local
```

Push changes:

```bash
git commit -am "Update role"
git push
```

CronJob will pull latest version automatically.

---

# 🚀 Future Enhancements

- Replace SSH Secret with **HashiCorp Vault Agent sidecar**
- Replace static inventory with **Nautobot dynamic inventory plugin**
- Convert to **Helm chart**
- Add **dry-run CronJob** using `--check`

---

If you'd like, I can also generate:

- A `bootstrap.sh` script for target hosts  
- A `Makefile` for build/deploy automation  
- A Helm chart version of this entire setup  

Just tell me what direction you want to take next.
