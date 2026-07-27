# ☸️ Kubernetes Challenge — KodeKloud

[![Days Completed](https://img.shields.io/badge/Days%20Completed-1%2F30-blue?style=for-the-badge)](/)
[![Platform](https://img.shields.io/badge/Platform-KodeKloud-orange?style=for-the-badge)](https://kodekloud.com/)
[![Tool](https://img.shields.io/badge/Tool-kubectl-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)](https://kubernetes.io/docs/reference/kubectl/)

Publicly documenting a 30-day hands-on Kubernetes challenge on KodeKloud.
Every day: a real task, a full write-up, all commands, and a LinkedIn post.
Failures are documented inline — not hidden.

🔗 **LinkedIn:** [venkatesh-gangavarapu](https://www.linkedin.com/in/venkatesh-gangavarapu)
🔗 **AWS Challenge (Completed ✅):** [100-days-cloud-challenge-AWS](https://github.com/venkatesh-gangavarapu/100-days-cloud-challenge-AWS)
🔗 **Azure Challenge (In Progress):** [100-Days-Of-Cloud-Challenge-Azure](https://github.com/venkatesh-gangavarapu/100-Days-Of-Cloud-Challenge-Azure)

---

## 📅 Daily Log

| Day | Topic | Key Learnings | Status |
|-----|-------|---------------|--------|
| [Day 01](./days/day-01/README.md) | Create a Pod | `kubectl run` can't set container name — use `--dry-run=client -o yaml` + patch; labels are selectors, not decoration | ✅ Done |

---

## 🗂️ Deliverable Structure

Each day produces three files:

| File | Purpose |
|------|---------|
| `README.md` | WHY before HOW, imperative + declarative methods, real failures documented inline, common mistakes, interview Q&A |
| `commands.sh` | Fully runnable script with `set -e`, inline comments, verification steps, and commented cleanup |
| `linkedin_post.txt` | Human-voice post leading with the key technical insight; no "Today I learned" openers |

---

## 📦 Topics Tracker

| Domain | Days Covered |
|--------|-------------|
| Pod fundamentals | Day 01 |
| Multi-container Pods | — |
| Services & Networking | — |
| ConfigMaps & Secrets | — |
| Deployments & ReplicaSets | — |
| Namespaces & RBAC | — |
| Persistent Volumes | — |
| Resource Limits & QoS | — |
| Probes & Health Checks | — |
| Node Affinity & Taints | — |

---

## 🛠️ Lab Environment

- **Platform:** KodeKloud interactive labs
- **Access:** `kubectl` on jump-host (pre-configured kubeconfig)
- **Cluster:** Control plane + worker nodes managed by KodeKloud
- **Approach:** Imperative-first for speed (`--dry-run=client -o yaml` pattern), declarative YAML for production-grade context

---

*Real failures documented inline. Every README reflects what actually happened, not just the happy path.*
