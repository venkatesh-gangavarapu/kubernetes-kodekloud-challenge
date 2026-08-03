# Day 06 — Rolling Back a Kubernetes Deployment

> #KodeKloud Kubernetes Challenge | Day 6 of 30

---

## 📌 The Task

| Requirement         | Value              |
|---------------------|--------------------|
| Existing deployment | `nginx-deployment` |
| Action              | Rollback to previous revision |
| Namespace           | `default`          |

---

## 🧠 Core Concepts

### Why Rollback Exists — and What Day 05 Set Up

Day 05 covered rolling updates: how Kubernetes creates a new ReplicaSet for the updated image and scales it up while scaling down the old one. Critically, the old ReplicaSet is **never deleted** — it is kept at 0 replicas after the update completes.

Today's task is the other half of that mechanism. A bug was introduced in the new release. The fastest path to recovery is not redeploying from scratch, re-building the image, or manually editing the manifest. It is reversing the scale direction on the two ReplicaSets that already exist:

```
AFTER DAY 05 UPDATE (before rollback):
Deployment (nginx-deployment)
  ├── ReplicaSet A  DESIRED=0  READY=0   ← old version, kept dormant
  └── ReplicaSet B  DESIRED=3  READY=3   ← current (buggy) version

AFTER ROLLBACK:
Deployment (nginx-deployment)
  ├── ReplicaSet A  DESIRED=3  READY=3   ← previous version, restored
  └── ReplicaSet B  DESIRED=0  READY=0   ← buggy version, now dormant
```

No image re-pull. No manifest edit. No CI/CD pipeline run. The kubelet already has the old image layers cached on the node. Recovery can complete in seconds.

### Revision History — The Rollback Ledger

Every time a Deployment's Pod template changes, Kubernetes increments a **revision number** and saves the corresponding ReplicaSet as a historical record. This is the rollback ledger:

```bash
kubectl rollout history deployment/nginx-deployment -n default
```

Typical output:
```
DEPLOYMENT   CHANGE-CAUSE
1            <none>          ← original deploy (e.g., nginx:latest)
2            <none>          ← update from Day 05 (nginx:1.18)
```

`CHANGE-CAUSE` shows `<none>` unless you annotated the rollout with `kubectl annotate` or used the deprecated `--record` flag. In production, annotating rollouts with the triggering commit SHA or ticket number makes the history useful rather than just a list of revision numbers.

### `rollout undo` — What It Does Under the Hood

`kubectl rollout undo deployment/nginx-deployment` is shorthand for "roll back to the previous revision." It does the following:

1. Identifies the current active revision (highest revision number)
2. Identifies the target revision (previous revision number, or `--to-revision=N` if specified)
3. Updates the Deployment's Pod template to match the target ReplicaSet's template
4. Triggers a rolling update using the same `maxSurge`/`maxUnavailable` mechanism as a forward update
5. Scales up the old ReplicaSet, scales down the current one
6. Renumbers: the target revision becomes the new highest revision number

This last point catches engineers off guard — after a rollback, the revision that was "1" becomes "3" (or whatever the next number is). The old revision 1 no longer exists as revision 1 in the history. It is now the latest.

### `--to-revision` — Targeted Rollback

Without `--to-revision`, `rollout undo` always goes back exactly **one revision**. In a scenario with multiple sequential bad updates, you may need to jump back further:

```bash
# Roll back one step (previous revision)
kubectl rollout undo deployment/nginx-deployment -n default

# Roll back to a specific revision
kubectl rollout undo deployment/nginx-deployment --to-revision=1 -n default
```

Always run `kubectl rollout history` first to see which revision numbers exist and which image each corresponds to.

### `revisionHistoryLimit` — How Far Back You Can Go

Kubernetes keeps a maximum of `revisionHistoryLimit` old ReplicaSets (default: **10**). Once you exceed this limit, the oldest ReplicaSet is garbage-collected and that revision is no longer available for rollback. In environments with frequent deployments, this limit can be reached faster than expected. Set it explicitly in your Deployment spec:

```yaml
spec:
  revisionHistoryLimit: 5   # keep 5 old ReplicaSets for rollback
```

Setting it to `0` means no history is kept — the moment a rolling update completes, the old ReplicaSet is deleted and rollback to that version is impossible.

---

## 🔧 Step-by-Step Solution

### Method 1 — kubectl rollout undo (Imperative — Exam Standard)

**Step 1 — Verify cluster access**
```bash
kubectl get nodes
```

**Step 2 — Confirm the deployment exists and check current state**
```bash
kubectl get deployment nginx-deployment -n default
kubectl get deployment nginx-deployment -n default \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
```

**Step 3 — Inspect rollout history**

Always check the history before rolling back. This confirms how many revisions exist and identifies which revision is the "previous" one you are about to restore.
```bash
kubectl rollout history deployment/nginx-deployment -n default
```

**Step 4 — Inspect the specific revision you are rolling back to**

This shows the Pod template (including image) of a specific revision — critical for confirming you are restoring the right version:
```bash
kubectl rollout history deployment/nginx-deployment \
  --revision=1 \
  -n default
```

**Step 5 — Execute the rollback**
```bash
kubectl rollout undo deployment/nginx-deployment -n default
```

**Step 6 — Block until rollback is complete**
```bash
kubectl rollout status deployment/nginx-deployment \
  -n default \
  --timeout=120s
```
Expected:
```
Waiting for deployment "nginx-deployment" rollout to finish: 1 out of 1 new replicas have been updated...
deployment "nginx-deployment" successfully rolled out
```

**Step 7 — Verify all pods are operational**
```bash
kubectl get pods -n default
kubectl get deployment nginx-deployment -n default
```

**Step 8 — Confirm the image has reverted**
```bash
kubectl get deployment nginx-deployment -n default \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
```

**Step 9 — Check updated rollout history**
```bash
kubectl rollout history deployment/nginx-deployment -n default
```
Note: the restored revision now appears as the **highest revision number** — not as revision 1 again.

---

### Method 2 — kubectl rollout undo --to-revision (Targeted Rollback)

Use this when you need to skip back more than one revision — for example, if two consecutive bad updates were deployed.

**Step 1 — Check full revision history**
```bash
kubectl rollout history deployment/nginx-deployment -n default
```

**Step 2 — Inspect each revision to identify the target**
```bash
kubectl rollout history deployment/nginx-deployment --revision=1 -n default
kubectl rollout history deployment/nginx-deployment --revision=2 -n default
```

**Step 3 — Roll back to the specific revision**
```bash
kubectl rollout undo deployment/nginx-deployment \
  --to-revision=1 \
  -n default
```

**Step 4 — Monitor rollout**
```bash
kubectl rollout status deployment/nginx-deployment -n default
```

---

### Method 3 — Edit Deployment YAML (Declarative Rollback)

Less common for emergency rollback but appropriate for GitOps workflows where the Deployment manifest in source control is the source of truth.

**Step 1 — Export current manifest**
```bash
kubectl get deployment nginx-deployment -n default -o yaml > nginx-deployment.yaml
```

**Step 2 — Revert the image in the manifest**
```bash
# Edit manually or via sed — replace buggy image with known-good version
sed -i 's|image: nginx:1.18|image: nginx:latest|' nginx-deployment.yaml
```

**Step 3 — Apply the reverted manifest**
```bash
kubectl apply -f nginx-deployment.yaml
```

**Step 4 — Watch rollout**
```bash
kubectl rollout status deployment/nginx-deployment -n default
```

---

## 💻 Commands Reference

```bash
# Pre-rollback inspection
kubectl get deployment nginx-deployment -n default
kubectl get deployment nginx-deployment -n default \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
kubectl get replicaset -n default
kubectl get pods -n default

# Rollout history — always check before rolling back
kubectl rollout history deployment/nginx-deployment -n default

# Inspect a specific revision's pod template
kubectl rollout history deployment/nginx-deployment \
  --revision=1 -n default
kubectl rollout history deployment/nginx-deployment \
  --revision=2 -n default

# Rollback to previous revision (one step back)
kubectl rollout undo deployment/nginx-deployment -n default

# Rollback to a specific revision
kubectl rollout undo deployment/nginx-deployment \
  --to-revision=1 -n default

# Block until rollback completes
kubectl rollout status deployment/nginx-deployment \
  -n default --timeout=120s

# Post-rollback verification
kubectl get deployment nginx-deployment -n default
kubectl get pods -n default
kubectl get replicaset -n default
kubectl get deployment nginx-deployment -n default \
  -o jsonpath='{.spec.template.spec.containers[0].image}'

# Updated history after rollback (revision numbers shift)
kubectl rollout history deployment/nginx-deployment -n default

# Full describe
kubectl describe deployment nginx-deployment -n default

# Pause a rollout mid-update (if needed)
kubectl rollout pause deployment/nginx-deployment -n default

# Resume a paused rollout
kubectl rollout resume deployment/nginx-deployment -n default
```

---

## ⚠️ Common Mistakes

1. **Not inspecting revision history before rolling back**
   `kubectl rollout undo` without checking `rollout history` first is a guess. In environments with multiple revisions, "previous" might not be the stable version you think it is. Always run `rollout history` and inspect the target revision's image with `--revision=N` before executing the undo.

2. **Expecting revision numbering to stay fixed after a rollback**
   After `rollout undo`, the restored version becomes the **new highest revision number**. The old revision 1 no longer exists as revision 1 — it becomes revision 3 (or N+1). Engineers who assume revision numbers are stable get confused when `--to-revision=1` fails or points to the wrong version on a second rollback attempt.

3. **Skipping `rollout status` after `rollout undo`**
   `rollout undo` is asynchronous — it triggers a rolling update in reverse, not an instant swap. If the rollback fails (for example, if the old image is somehow no longer pullable), you will not know without watching `rollout status`. Always block on it.

4. **Assuming `rollout undo` is instant**
   It uses the same rolling update mechanism as a forward update — `maxSurge` and `maxUnavailable` constraints apply. For a multi-replica Deployment, the rollback takes time. In a production incident, this is expected behaviour, but engineers unfamiliar with it sometimes abort the rollback thinking it is stuck.

5. **Confusing `rollout restart` with `rollout undo`**
   `kubectl rollout restart deployment/nginx-deployment` cycles all Pods using the **current image** — it does not revert the image. `rollout undo` reverts the Pod template to a previous revision. These are completely different operations. During an incident, using the wrong one wastes critical minutes.

6. **`revisionHistoryLimit: 0` means no rollback is possible**
   Some teams set `revisionHistoryLimit: 0` to save etcd storage space. This deletes old ReplicaSets immediately after a successful rollout. `rollout undo` then has nothing to revert to and fails. The default of 10 is reasonable; lowering it to 0 removes your safety net entirely.

7. **Using `--record` flag expecting annotated history**
   The `--record` flag on `kubectl set image` or `kubectl apply` was the historical way to populate `CHANGE-CAUSE` in `rollout history`. It is deprecated in Kubernetes 1.25+ and removed in later versions. In newer clusters, use `kubectl annotate deployment/nginx-deployment kubernetes.io/change-cause="your message"` separately after the update to document the change.

---

## 🌍 Real-World Context

The scenario in this task — customer-reported bug triggers emergency rollback — is one of the most common production events in any organisation running on Kubernetes. The standard incident playbook looks like this:

```bash
# 1. Confirm the bad release is the culprit
kubectl rollout history deployment/nginx-deployment -n production

# 2. Identify the last known-good revision
kubectl rollout history deployment/nginx-deployment \
  --revision=1 -n production

# 3. Execute rollback
kubectl rollout undo deployment/nginx-deployment -n production

# 4. Block the incident channel until it's confirmed
kubectl rollout status deployment/nginx-deployment \
  -n production --timeout=120s

# 5. Confirm traffic is healthy
kubectl get pods -n production
```

The whole sequence can complete in under two minutes. Compare this to rebuilding and redeploying from a previous Docker tag — which requires triggering a CI/CD pipeline, waiting for a build, and pushing through environments — potentially 15–30 minutes.

This speed difference is why mature teams invest in clean rollout history, meaningful `CHANGE-CAUSE` annotations, and explicit `revisionHistoryLimit` settings. The rollback mechanism is only as useful as the history it has to work with.

In GitOps workflows (ArgoCD, Flux), rollback is typically done by reverting the commit in the Git repository that holds the Deployment manifest, then letting the GitOps controller re-apply. This preserves the Git history as the source of truth while still using the same Kubernetes rolling update mechanism under the hood.

---

## ❓ Interview Q&A

**Q1: What does `kubectl rollout undo` do under the hood?**
It identifies the previous revision's ReplicaSet, updates the Deployment's Pod template to match it, and triggers a rolling update in reverse — scaling up the old ReplicaSet and scaling down the current one. No image is re-pulled; the kubelet uses cached layers. The old revision is renumbered to become the new highest revision in the history.

**Q2: How does rollback work without re-pulling the image?**
The old ReplicaSet still exists at 0 replicas after a rolling update. Its Pod template contains the full spec including the previous image reference. When `rollout undo` scales it back up, the nodes that ran the old version still have those image layers in their local container image cache. If the image is no longer in cache (unlikely for a recent rollback), it falls back to pulling from the registry.

**Q3: How do you roll back to a specific revision rather than just "previous"?**
`kubectl rollout undo deployment/<name> --to-revision=<N> -n <namespace>`. First run `kubectl rollout history deployment/<name>` to see available revision numbers, then inspect each with `--revision=N` to confirm the image. Specify the target with `--to-revision`.

**Q4: What happens to revision numbering after a rollback?**
The restored revision is renumbered as the new highest revision. If you had revisions 1 and 2, and rolled back from 2 to 1, the resulting history shows revision 2 (current, the old 1 config) and revision 1 is gone. Running `rollout undo` again from here goes back to what was revision 2 (the buggy version). Tracking what each revision contained requires either `rollout history --revision=N` or external annotation of change causes.

**Q5: What is `revisionHistoryLimit` and what risk does setting it to 0 create?**
`revisionHistoryLimit` (default: 10) controls how many old ReplicaSets Kubernetes keeps after they are scaled to 0. Setting it to 0 deletes old ReplicaSets immediately, which means `rollout undo` has nothing to revert to. You lose the ability to roll back at all. Setting it to 0 is sometimes done to reduce etcd storage pressure but removes a critical safety net — not recommended for any customer-facing workload.

**Q6: How would you use rollback in a CI/CD pipeline?**
The pipeline runs `kubectl rollout status` after `kubectl set image`. If `rollout status` exits non-zero (timeout or failure), the pipeline executes `kubectl rollout undo` as the remediation step. This pattern makes rollback automatic on deployment failure without human intervention — the pipeline detects the bad state and reverses it before alerting the team.

**Q7: What is the difference between `rollout undo` and `rollout restart`?**
`rollout undo` reverts the Deployment's Pod template to a previous revision — it changes the image (and any other template fields) back to what they were. `rollout restart` recreates all Pods using the **current** Pod template unchanged — useful for forcing a fresh start after a ConfigMap change or clearing stuck containers. Neither is a substitute for the other during an image-related bug rollback.

---

## 📚 Resources

- [Kubernetes Docs — Rolling Back a Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#rolling-back-a-deployment)
- [Kubernetes Docs — kubectl rollout](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#rollout)
- [Kubernetes Docs — Deployment revisionHistoryLimit](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#revision-history-limit)
- **Related days:** [Day 02](../day-02/README.md) — Deployment + ReplicaSet chain | [Day 05](../day-05/README.md) — Rolling updates (the forward direction of the same mechanism)
