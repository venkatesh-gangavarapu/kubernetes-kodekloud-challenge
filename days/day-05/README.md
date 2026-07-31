# Day 05 — Rolling Updates for a Kubernetes Deployment

> #KodeKloud Kubernetes Challenge | Day 5 of 30

---

## 📌 The Task

| Requirement         | Value              |
|---------------------|--------------------|
| Existing deployment | `nginx-deployment` |
| New image           | `nginx:1.18`       |
| Update strategy     | Rolling update     |
| Post-update check   | All pods operational |
| Namespace           | `default`          |

---

## 🧠 Core Concepts

### What is a Rolling Update?

A rolling update is Kubernetes' default mechanism for deploying a new version of an application **without downtime**. Instead of stopping all existing Pods and starting new ones simultaneously (which would cause a gap in availability), Kubernetes incrementally replaces old Pods with new ones — keeping some instances of the old version running while new ones come up.

The moment you change anything in a Deployment's Pod template (image, environment variables, resource limits), the Deployment controller triggers a rolling update automatically. You do not configure "rolling update mode" per-update — it is the default strategy and it activates on every template change.

### The ReplicaSet Handoff — What Actually Happens Under the Hood

Day 02 introduced the Deployment → ReplicaSet → Pod chain. During a rolling update, that chain does something specific:

```
BEFORE UPDATE:
Deployment (nginx-deployment)
  └── ReplicaSet A (nginx-deployment-abc123)  ← replicas=3, running nginx:old
        ├── Pod 1 (nginx:old)
        ├── Pod 2 (nginx:old)
        └── Pod 3 (nginx:old)

DURING UPDATE:
Deployment (nginx-deployment)
  ├── ReplicaSet A (nginx-deployment-abc123)  ← scaling down
  │     ├── Pod 1 (nginx:old)   ← terminating
  │     └── Pod 2 (nginx:old)
  └── ReplicaSet B (nginx-deployment-def456)  ← scaling up (new pod template)
        └── Pod 4 (nginx:1.18)  ← starting

AFTER UPDATE:
Deployment (nginx-deployment)
  ├── ReplicaSet A (nginx-deployment-abc123)  ← replicas=0, kept for rollback
  └── ReplicaSet B (nginx-deployment-def456)  ← replicas=3, all running nginx:1.18
        ├── Pod 4 (nginx:1.18)
        ├── Pod 5 (nginx:1.18)
        └── Pod 6 (nginx:1.18)
```

The old ReplicaSet is **not deleted** — it is scaled to 0 and kept. This is what makes rollback instantaneous: `kubectl rollout undo` simply reverses the scale direction, scaling up the old RS and scaling down the new one.

### `maxSurge` and `maxUnavailable` — Controlling the Pace

The rolling update speed is controlled by two parameters in the Deployment's `spec.strategy.rollingUpdate`:

| Parameter | Default | Meaning |
|-----------|---------|---------|
| `maxUnavailable` | `25%` | Maximum number of Pods that can be unavailable during the update |
| `maxSurge` | `25%` | Maximum number of extra Pods that can exist above the desired replica count |

For a 3-replica Deployment with defaults:
- `maxUnavailable=25%` → at most 0 Pods can be unavailable (rounds down from 0.75)
- `maxSurge=25%` → at most 1 extra Pod can exist during the update

So for a 3-replica Deployment with these defaults, Kubernetes creates 1 new Pod, waits for it to become Ready, then terminates 1 old Pod — guaranteeing at least 3 Pods are serving traffic at all times.

### Why `kubectl set image` Needs the Container Name

The command syntax for updating an image imperatively is:

```bash
kubectl set image deployment/<deployment-name> <container-name>=<new-image>
```

The `<container-name>` is required because a Pod can have multiple containers. Kubernetes needs to know which container's image you are changing. Getting this wrong results in an error like:

```
error: unable to find container named "wrong-name"
```

The safe workflow is to always **inspect the current container name before running `set image`** — never assume it matches the Deployment name.

### Three Ways to Trigger a Rolling Update

| Method | Command | Best for |
|--------|---------|---------|
| `kubectl set image` | `kubectl set image deployment/nginx-deployment <container>=nginx:1.18` | Fast, imperative, exam standard |
| `kubectl edit` | `kubectl edit deployment nginx-deployment` | Interactive, useful for multiple simultaneous changes |
| `kubectl apply -f` | Edit the YAML locally, `kubectl apply -f deployment.yaml` | GitOps, version-controlled changes |

All three trigger the same rolling update mechanism — the difference is how the spec change reaches the API server.

---

## 🔧 Step-by-Step Solution

### Method 1 — kubectl set image (Imperative — Exam Standard)

This is the canonical way to trigger a rolling update in a CKA exam or live incident. Two commands: inspect the current state, then update.

**Step 1 — Verify the deployment exists and check current image**
```bash
kubectl get deployment nginx-deployment -n default
kubectl get deployment nginx-deployment -n default \
  -o jsonpath='{.spec.template.spec.containers[*].name}'
```
Note the container name from the output — you need it for `set image`.

**Step 2 — Check current image**
```bash
kubectl get deployment nginx-deployment -n default \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
```

**Step 3 — Discover container name and store it**
```bash
CONTAINER=$(kubectl get deployment nginx-deployment -n default \
  -o jsonpath='{.spec.template.spec.containers[0].name}')
echo "Container name: ${CONTAINER}"
```

**Step 4 — Execute the rolling update**
```bash
kubectl set image deployment/nginx-deployment \
  ${CONTAINER}=nginx:1.18 \
  -n default
```

**Step 5 — Watch the rollout in real time**
```bash
kubectl rollout status deployment/nginx-deployment -n default
```
Expected:
```
Waiting for deployment "nginx-deployment" rollout to finish: 1 out of 1 new replicas have been updated...
deployment "nginx-deployment" successfully rolled out
```

**Step 6 — Verify pods are operational**
```bash
kubectl get pods -n default
kubectl get deployment nginx-deployment -n default
```

**Step 7 — Confirm the new image is running**
```bash
kubectl get deployment nginx-deployment -n default \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
```
Expected: `nginx:1.18`

---

### Method 2 — kubectl patch (Declarative Field Update)

`kubectl patch` updates a specific field without opening an editor or applying a full manifest. Useful when you know the exact JSON/YAML path to change.

```bash
kubectl patch deployment nginx-deployment -n default \
  --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/image", "value": "nginx:1.18"}]'
```

Or using merge patch (simpler syntax, but requires knowing the container name):
```bash
kubectl patch deployment nginx-deployment -n default \
  -p '{"spec":{"template":{"spec":{"containers":[{"name":"nginx-deployment","image":"nginx:1.18"}]}}}}'
```

**Verify rollout:**
```bash
kubectl rollout status deployment/nginx-deployment -n default
```

---

### Method 3 — YAML Edit + Apply (GitOps Approach)

**Step 1 — Export the current deployment spec**
```bash
kubectl get deployment nginx-deployment -n default -o yaml > nginx-deployment.yaml
```

**Step 2 — Update the image in the manifest**
```bash
# Find and replace the image line
sed -i 's|image: nginx:.*|image: nginx:1.18|' nginx-deployment.yaml
```

**Step 3 — Apply the updated manifest**
```bash
kubectl apply -f nginx-deployment.yaml
```

**Step 4 — Watch the rollout**
```bash
kubectl rollout status deployment/nginx-deployment -n default
```

---

## 💻 Commands Reference

```bash
# Pre-update inspection
kubectl get deployment nginx-deployment -n default
kubectl get deployment nginx-deployment -n default -o wide
kubectl get deployment nginx-deployment -n default \
  -o jsonpath='{.spec.template.spec.containers[0].name}'
kubectl get deployment nginx-deployment -n default \
  -o jsonpath='{.spec.template.spec.containers[0].image}'

# Discover container name (store for use in set image)
CONTAINER=$(kubectl get deployment nginx-deployment -n default \
  -o jsonpath='{.spec.template.spec.containers[0].name}')

# Method 1 — set image (imperative)
kubectl set image deployment/nginx-deployment \
  ${CONTAINER}=nginx:1.18 \
  -n default

# Method 2 — patch
kubectl patch deployment nginx-deployment -n default \
  --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/image", "value": "nginx:1.18"}]'

# Method 3 — apply edited YAML
kubectl get deployment nginx-deployment -n default -o yaml > nginx-deployment.yaml
sed -i 's|image: nginx:.*|image: nginx:1.18|' nginx-deployment.yaml
kubectl apply -f nginx-deployment.yaml

# Monitor rollout (blocks until complete)
kubectl rollout status deployment/nginx-deployment -n default

# Watch pods live during update
kubectl get pods -n default -w

# Rollout history (audit trail)
kubectl rollout history deployment/nginx-deployment -n default

# Rollback (if update goes wrong)
kubectl rollout undo deployment/nginx-deployment -n default

# Post-update verification
kubectl get deployment nginx-deployment -n default
kubectl get pods -n default
kubectl get deployment nginx-deployment -n default \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
kubectl describe deployment nginx-deployment -n default

# ReplicaSet audit (old RS kept at 0 for rollback)
kubectl get replicaset -n default
```

---

## ⚠️ Common Mistakes

1. **Wrong container name in `kubectl set image`**
   The most common failure. `kubectl set image deployment/nginx-deployment nginx-deployment=nginx:1.18` assumes the container is named `nginx-deployment`, but it might be `nginx` or something else entirely. Always inspect the container name first: `kubectl get deployment nginx-deployment -o jsonpath='{.spec.template.spec.containers[0].name}'`. A wrong name produces `error: unable to find container named "..."` and no update occurs.

2. **Declaring success before `rollout status` completes**
   `kubectl get deployment` may show the old replica count as READY immediately after `kubectl set image`, before new Pods are up. `rollout status` is the only command that actually blocks until the update is complete. Checking too early and assuming success is how broken images make it to "production is down" incidents.

3. **Using `kubectl rollout restart` instead of `kubectl set image`**
   `kubectl rollout restart deployment/nginx-deployment` forces a Pod recreation using the **current image** — useful for picking up ConfigMap changes or clearing stuck Pods, but it does NOT update the image. The task is an image update, not a restart.

4. **Image pull failure stalls the rollout silently**
   If `nginx:1.18` doesn't exist on the registry (typo, private registry auth missing), new Pods enter `ImagePullBackOff`. The rollout stalls — `rollout status` hangs, and old Pods keep running (which is the intended safety behaviour). Always check `kubectl get pods` and `kubectl describe pod <pod>` if rollout status does not resolve quickly.

5. **Editing the ReplicaSet image directly**
   `kubectl edit replicaset nginx-deployment-<hash>` and changing the image there does nothing useful — the Deployment controller will overwrite the ReplicaSet spec on the next sync. Image changes must go through the Deployment, not the ReplicaSet it manages.

6. **Not knowing the rollback command when a bad image deploys**
   A bad image in production needs a fast rollback. The command is `kubectl rollout undo deployment/nginx-deployment -n default`. This scales up the previous ReplicaSet and scales down the current one. Running it without knowing where it is costs time in an incident. Know it before you need it.

7. **Assuming `--record` is still the right way to annotate rollout history**
   `kubectl set image --record` was the traditional way to annotate rollout history with the command that triggered the change. The `--record` flag is deprecated in newer Kubernetes versions. Use `kubectl annotate` or manage change tracking via your CI/CD pipeline instead.

---

## 🌍 Real-World Context

Rolling updates are the daily operational reality of running applications on Kubernetes. Every time a CI/CD pipeline pushes a new Docker image, the pipeline does essentially what this task does:

```bash
# Typical CI/CD image update step
kubectl set image deployment/nginx-deployment \
  nginx=nginx:${NEW_SHA} \
  -n production

kubectl rollout status deployment/nginx-deployment \
  -n production \
  --timeout=300s
```

If `rollout status` exits non-zero (timeout or error), the pipeline triggers an automatic rollback:
```bash
kubectl rollout undo deployment/nginx-deployment -n production
```

The old ReplicaSet sitting at 0 replicas is specifically designed for this pattern — no image re-pull, no manifest re-apply, just a scale direction flip. That's what makes Kubernetes rollbacks significantly faster than re-deploying from scratch.

In production, teams layer additional safety on top of this:
- **Readiness probes** — the rollout does not advance to terminating old Pods until new Pods pass their readiness probe. Without a probe, "Ready" just means the container started, not that it can serve traffic.
- **Progressive delivery** (Argo Rollouts, Flagger) — extends the basic rolling update with canary releases and automated metric-based promotion/rollback
- **`maxUnavailable: 0`** — ensures zero downtime by guaranteeing old Pods stay up until new Pods are confirmed healthy

---

## ❓ Interview Q&A

**Q1: How does a Kubernetes rolling update work at the ReplicaSet level?**
When the Pod template in a Deployment changes, the controller creates a new ReplicaSet with the updated template. It incrementally scales up the new RS and scales down the old one, subject to `maxSurge` and `maxUnavailable` constraints. The old RS is kept at 0 replicas after the update completes, enabling instant rollback without re-pulling images.

**Q2: What is the difference between `kubectl rollout restart` and `kubectl set image`?**
`rollout restart` forces all Pods in the Deployment to be recreated using the **current image** — it cycles Pods without changing the spec. Useful for forcing a ConfigMap reload or clearing stuck containers. `set image` changes the actual image in the Pod template, triggering a rolling update to a new image version. These are fundamentally different operations that look similar from the outside.

**Q3: What happens to traffic during a rolling update?**
With the default `RollingUpdate` strategy and a properly configured Service, traffic continues to flow to old Pods while new ones start up. Kubernetes removes a Pod from the Service's endpoint list the moment it enters `Terminating` state, before its containers stop. If readiness probes are configured, new Pods are not added to the endpoint list until they pass their probe. Combined, these mechanisms keep traffic serving throughout the update.

**Q4: How do you roll back a Deployment to the previous version?**
`kubectl rollout undo deployment/<name> -n <namespace>`. This scales up the previous ReplicaSet and scales down the current one. For a specific revision: `kubectl rollout undo deployment/<name> --to-revision=<n>`. The revision history is kept up to `revisionHistoryLimit` (default 10) ReplicaSets. Check available revisions with `kubectl rollout history deployment/<name>`.

**Q5: What is `maxSurge` and how does it affect the update?**
`maxSurge` defines how many extra Pods above the desired replica count can exist simultaneously during an update. A value of `1` on a 3-replica Deployment means at most 4 Pods can run at once — 3 old and 1 new during the transition. Higher values speed up the rollout but consume more node resources. Setting it to `0` prevents any extra Pods but requires old Pods to terminate before new ones start.

**Q6: How would you update only one container's image in a Pod with multiple containers?**
`kubectl set image deployment/<name> <specific-container-name>=<new-image>`. The container name in the command is what scopes the update. Only that container's image changes in the Pod template; other containers are unaffected. This is why knowing the container name before running `set image` is critical — the wrong name means either an error or no update.

**Q7: How do readiness probes interact with rolling updates?**
A rolling update advances (scales down old Pods) only after new Pods pass their readiness probe. Without a readiness probe, Kubernetes considers a Pod "ready" as soon as the container starts — which may be before the application is actually ready to serve requests. In practice, missing readiness probes on a Deployment means you can have traffic routed to Pods that have started but haven't finished initialising, causing 5xx errors during the rollout window.

---

## 📚 Resources

- [Kubernetes Docs — Deployments: Updating](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#updating-a-deployment)
- [Kubernetes Docs — kubectl set image](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#set)
- [Kubernetes Docs — Rolling Update Strategy](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#rolling-update-deployment)
- [Kubernetes Docs — kubectl rollout](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#rollout)
- **Related days:** [Day 02](../day-02/README.md) — Deployment + ReplicaSet fundamentals (the ownership chain that rolling updates operate on)
