# ☸️ Kubernetes Challenge — KodeKloud

[![Days Completed](https://img.shields.io/badge/Days%20Completed-3%2F30-blue?style=for-the-badge)](/)
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
| [Day 02](./days/day-02/README.md) | Create a Deployment | `kubectl run` creates a Pod, not a Deployment — use `kubectl create deployment`; Deployment → ReplicaSet → Pod ownership chain; `rollout status` is the authoritative readiness check | ✅ Done |
| [Day 03](./days/day-03/README.md) | Namespaces + Pod | `-n <namespace>` must be on the `--dry-run` command, not just `apply`; `kubectl get pods -A` for cross-namespace visibility; namespace deletion cascades | ✅ Done |
| [Day 04](./days/day-04/README.md) | Resource Requests & Limits | Requests = scheduler reservation; Limits = runtime enforcement; CPU over limit → throttled; memory over limit → OOMKilled; mismatched requests/limits → Burstable QoS not Guaranteed | ✅ Done |
| [Day 05](./days/day-05/README.md) | Rolling Updates | `kubectl set image` needs the container name not the deployment name — inspect first; `rollout status` blocks until complete; old ReplicaSet kept at 0 for instant rollback | ✅ Done |
| [Day 06](./days/day-06/README.md) | Rollback | Always inspect `rollout history` before rolling back; `rollout undo` is asynchronous — block on `rollout status`; revision numbers shift after rollback; `revisionHistoryLimit: 0` removes rollback entirely | ✅ Done |
| [Day 07](./days/day-07/README.md) | ReplicaSet | No `kubectl create replicaset` exists — YAML only; both labels in 3 locations; RS has no rolling update semantics; image changes don't update existing Pods | ✅ Done |
| [Day 08](./days/day-08/README.md) | CronJob | CronJob → Job → Pod hierarchy; `restartPolicy: Always` rejected at admission — use `OnFailure`; `apiVersion: batch/v1`; range-restricted `sed` for container name patch; manually trigger with `--from=cronjob/` | ✅ Done |
| [Day 09](./days/day-09/README.md) | Job | `kubectl create job` omits `spec.template.metadata.name` — write YAML directly; `Never` = new Pod per retry (logs preserved); `OnFailure` = restart in-place (logs overwritten); `Completed` is the correct Pod status after success | ✅ Done |
| [Day 10](./days/day-10/README.md) | ConfigMap + Env + Volume | Namespace → ConfigMap → Pod creation order; ConfigMap in wrong namespace → `CreateContainerConfigError`; shell constructs require `/bin/sh -c`; volume name must match in `volumes[]` and `volumeMounts[]` | ✅ Done |
| [Day 11](./days/day-11/README.md) | Pod Troubleshooting | Investigate before fixing: describe → logs → `--previous`; ubuntu:latest exits immediately without a command → ImagePullBackOff; pod spec immutable → delete + reapply; READY=2/2 not just STATUS=Running | ✅ Done |
| [Day 12](./days/day-12/README.md) | Kubernetes: Update Deployment + Service (nginx) | kubectl patch/scale/set image, rolling update, jsonpath verification, rollout status gate | ✅ Done |
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
