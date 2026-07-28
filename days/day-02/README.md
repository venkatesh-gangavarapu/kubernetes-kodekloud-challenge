# Day 02 — Creating a Deployment in Kubernetes

> #KodeKloud Kubernetes Challenge | Day 2 of 30

---

## 📌 The Task

| Requirement     | Value          |
|-----------------|----------------|
| Object type     | Deployment     |
| Deployment name | `nginx`        |
| Image           | `nginx:latest` |
| Access method   | `kubectl` on jump-host |

---

## 🧠 Core Concepts

### Why Deployments Exist — The Problem With Bare Pods

On Day 01 we created a bare Pod. A bare Pod has a fundamental flaw in production: **no self-healing**. If the node running the Pod dies, or the Pod crashes, nothing brings it back. The scheduler placed it once and moved on.

A **Deployment** solves this. It is a higher-level Kubernetes object that declares your *desired state* — "I want 1 replica of nginx:latest running" — and then continuously reconciles actual state against that desire. If your Pod disappears, the Deployment controller notices the count dropped below desired and creates a replacement automatically.

This is the control loop pattern at the heart of Kubernetes: declare what you want, let a controller make it happen and keep it that way.

### The Three-Layer Hierarchy: Deployment → ReplicaSet → Pod

When you create a Deployment, Kubernetes actually creates three objects:

```
Deployment (nginx)
  └── ReplicaSet (nginx-<hash>)
        └── Pod (nginx-<hash>-<hash>)
```

- **Deployment** — owns the desired state spec and the rollout strategy. This is what you manage.
- **ReplicaSet** — created automatically by the Deployment controller; responsible for keeping the correct number of Pods running. You rarely interact with it directly.
- **Pod** — the actual running container, created and owned by the ReplicaSet.

The naming reflects this chain. Your Deployment is `nginx`. The ReplicaSet gets a suffix based on the Pod template hash (e.g., `nginx-7848d4b86f`). The Pod gets another suffix on top (e.g., `nginx-7848d4b86f-xk9p2`).

**Critical rule:** never edit a ReplicaSet directly. The Deployment owns it and will overwrite your changes on the next reconciliation cycle. Always edit the Deployment.

### The `selector.matchLabels` Mechanism

A Deployment does not own Pods by reference — it owns them by **label selection**. The Deployment spec defines a `selector.matchLabels` block, and any Pod whose labels match that selector is considered owned by the Deployment.

This is the same label-as-selector pattern from Day 01, now wired into the control loop. If `selector.matchLabels` and `template.metadata.labels` don't match, Kubernetes rejects the Deployment at creation time.

### Rolling Updates and Rollback

A Deployment's default update strategy is `RollingUpdate`. When you update the image version, the Deployment:

1. Creates a new ReplicaSet with the updated Pod template
2. Scales up the new ReplicaSet incrementally
3. Scales down the old ReplicaSet incrementally
4. Keeps old ReplicaSets around (scaled to 0) for rollback

This means zero-downtime updates are built in by default — no special configuration required for basic cases.

### Image Tag Discipline

`nginx:latest` means "the most recent image pushed with the `latest` tag on Docker Hub." In production this is dangerous — `latest` is mutable; a new push can change what gets pulled on the next Pod creation. Production workloads should pin to a digest or a semantic version (`nginx:1.27.0`). For this task, `:latest` is explicitly required — specify it.

---

## 🔧 Step-by-Step Solution

### Method 1 — kubectl Imperative + dry-run (Exam Technique)

Unlike `kubectl run` from Day 01, `kubectl create deployment` is purpose-built for Deployments and produces the full three-layer hierarchy correctly. The `--dry-run=client -o yaml` pattern generates the manifest for inspection and version control before applying.

**Step 1 — Verify cluster access**
```bash
kubectl get nodes
```

**Step 2 — Generate the Deployment YAML via dry-run**
```bash
kubectl create deployment nginx \
  --image=nginx:latest \
  --dry-run=client -o yaml > nginx-deployment.yaml
```

Review what was generated:
```bash
cat nginx-deployment.yaml
```

**Step 3 — Apply the manifest**
```bash
kubectl apply -f nginx-deployment.yaml
```

**Step 4 — Verify all three layers**
```bash
# Deployment
kubectl get deployment nginx -n default

# ReplicaSet (created automatically)
kubectl get replicaset -n default

# Pod (created automatically by the ReplicaSet)
kubectl get pods -n default
```

**Step 5 — Confirm the image tag**
```bash
kubectl get deployment nginx -n default \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
```
Expected: `nginx:latest`

---
[O
### Method 2 — YAML Manifest (Declarative — Production Grade)

Writing the full Deployment manifest makes every field explicit and version-controllable.

**Step 1 — Write the manifest**

```yaml
# nginx-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  namespace: default
  labels:
    app: nginx
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx          # must match template.metadata.labels exactly
  template:
    metadata:
      labels:
        app: nginx        # must match selector.matchLabels exactly
    spec:
      containers:
        - name: nginx
          image: nginx:latest   # tag explicitly specified
          ports:
            - containerPort: 80
```

**Step 2 — Apply**
```bash
kubectl apply -f nginx-deployment.yaml
```

**Step 3 — Wait for the rollout to complete**
```bash
kubectl rollout status deployment/nginx -n default
```
Expected:
```
deployment "nginx" successfully rolled out
```

**Step 4 — Verify the Deployment**
```bash
kubectl get deployment nginx -n default
```
Expected:
```
NAME    READY   UP-TO-DATE   AVAILABLE   AGE
nginx   1/1     1            1           30s
```

**Step 5 — Verify the ReplicaSet**
```bash
kubectl get replicaset -n default
```
Expected (hash will differ):
```
NAME               DESIRED   CURRENT   READY   AGE
nginx-7848d4b86f   1         1         1       30s
```

**Step 6 — Verify the Pod**
```bash
kubectl get pods -n default
```
Expected:
```
NAME                     READY   STATUS    RESTARTS   AGE
nginx-7848d4b86f-xk9p2   1/1     Running   0          30s
```

**Step 7 — Verify the image tag**
```bash
kubectl get deployment nginx -n default \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
```
Expected: `nginx:latest`

**Step 8 — Full describe**
```bash
kubectl describe deployment nginx -n default
```

---

## 💻 Commands Reference

```bash
# Cluster check
kubectl get nodes

# Method 1 — Imperative dry-run
kubectl create deployment nginx \
  --image=nginx:latest \
  --dry-run=client -o yaml > nginx-deployment.yaml
kubectl apply -f nginx-deployment.yaml

# Method 2 — Direct imperative (no dry-run, no file)
kubectl create deployment nginx --image=nginx:latest

# Rollout status
kubectl rollout status deployment/nginx -n default

# Verify all three layers
kubectl get deployment nginx -n default
kubectl get replicaset -n default
kubectl get pods -n default

# Verify image tag
kubectl get deployment nginx -n default \
  -o jsonpath='{.spec.template.spec.containers[0].image}'

# Full describe
kubectl describe deployment nginx -n default

# Scale (for reference)
kubectl scale deployment nginx --replicas=3 -n default

# Rollback (for reference)
kubectl rollout undo deployment/nginx -n default

# Cleanup (run manually when done)
# kubectl delete deployment nginx -n default
# kubectl delete -f nginx-deployment.yaml
# rm -f nginx-deployment.yaml
```

---

## ⚠️ Common Mistakes

1. **Using `kubectl run` instead of `kubectl create deployment`**
   `kubectl run nginx --image=nginx:latest` creates a bare **Pod**, not a Deployment. No ReplicaSet, no self-healing, no rollout control. For a Deployment, the correct imperative command is `kubectl create deployment`. These produce fundamentally different object types.

2. **Omitting the image tag**
   `--image=nginx` without `:latest` technically works (Docker Hub defaults to `latest`) but the task explicitly requires the tag to be specified. Always match the spec exactly — validators are literal.

3. **Editing the ReplicaSet directly**
   A Deployment continuously reconciles its ReplicaSet. If you `kubectl edit replicaset nginx-<hash>`, your changes will be overwritten on the next reconciliation cycle. Always edit the Deployment itself, and let it propagate the changes to the ReplicaSet.

4. **`selector.matchLabels` and `template.metadata.labels` mismatch**
   If these two blocks don't match exactly, the Deployment is rejected at creation time with a validation error. The selector is immutable after creation — if you get it wrong, delete and recreate.

5. **Not checking all three layers**
   `kubectl get deployment nginx` showing `READY 1/1` is necessary but not sufficient for complete verification. A Deployment can show ready while a Pod is in a restart loop. Always check `kubectl get pods` and `kubectl rollout status` as separate steps.

6. **Confusing `kubectl create` and `kubectl apply`**
   `kubectl create deployment nginx` fails with `already exists` if run twice. `kubectl apply -f nginx-deployment.yaml` is idempotent — safe to run repeatedly. In lab environments where you may be recovering from a failed attempt, `apply` is the safer choice.

7. **Ignoring rollout status**
   `kubectl get deployment nginx` might show `READY 0/1` for several seconds while the image pulls. Always use `kubectl rollout status deployment/nginx` to block until the rollout is truly complete before declaring success.

---

## 🌍 Real-World Context

In production, nearly every stateless application runs as a Deployment. When your team pushes a new Docker image, the CI/CD pipeline runs:

```bash
kubectl set image deployment/nginx nginx=nginx:1.27.1 -n production
kubectl rollout status deployment/nginx -n production
```

If the new version fails its readiness probe, the rolling update stalls automatically — it won't terminate old Pods until new ones are healthy. If the deployment goes badly, one command rolls everything back:

```bash
kubectl rollout undo deployment/nginx -n production
```

This is the operational model that makes Kubernetes the dominant container orchestrator: declarative desired state, continuous reconciliation, and built-in rollout control at the Deployment layer. Every Helm chart, every ArgoCD application, every GitOps workflow is ultimately managing Deployments (or their StatefulSet/DaemonSet equivalents) under the hood.

---

## ❓ Interview Q&A

**Q1: What is the difference between a Deployment and a bare Pod?**
A bare Pod is a single, unmanaged container wrapper. If it crashes or its node dies, nothing replaces it. A Deployment wraps the Pod spec in a control loop — it declares desired state (e.g., 1 replica of nginx:latest) and continuously reconciles actual state against it. Self-healing, rolling updates, and rollback are all properties of the Deployment layer, not the Pod layer.

**Q2: What is a ReplicaSet and why does a Deployment create one?**
A ReplicaSet is the controller responsible for maintaining a stable set of Pod replicas. It watches the cluster and creates or deletes Pods to match the desired count. A Deployment doesn't manage Pods directly — it manages ReplicaSets and delegates the Pod-level work to them. This separation is what enables rolling updates: the Deployment creates a new ReplicaSet with the updated Pod template, scales it up while scaling down the old one, and keeps the old ReplicaSet at 0 replicas for rollback purposes.

**Q3: How does a Deployment perform a rolling update?**
When the Pod template changes (e.g., a new image version), the Deployment controller creates a new ReplicaSet with the updated template. It then incrementally scales up the new ReplicaSet and scales down the old one, respecting `maxSurge` and `maxUnavailable` parameters. At no point does it terminate all old Pods before the new ones are ready — that's what keeps traffic serving during an update.

**Q4: What happens if you delete a ReplicaSet owned by a Deployment?**
The Deployment controller notices the ReplicaSet is gone and creates a new one immediately, restoring it to the desired state. You cannot permanently remove a ReplicaSet that a Deployment owns without first deleting the Deployment. This is the reconciliation loop working as designed.

**Q5: What is `selector.matchLabels` and why is it immutable?**
`selector.matchLabels` is how a Deployment identifies which Pods it owns. It is immutable after creation because changing it would cause the Deployment to "lose" its existing Pods (they no longer match the selector) and create new ones — a potentially destructive operation the API server forces you to do explicitly by deleting and recreating the Deployment.

**Q6: What is `kubectl rollout undo` doing under the hood?**
It scales up the previous ReplicaSet (which the Deployment keeps at 0 replicas after a successful rollout) and scales down the current one, effectively reversing the last update. The Deployment keeps a history of old ReplicaSets up to `revisionHistoryLimit` (default: 10), which is what makes rollback possible without re-pulling old images.

**Q7: How does a Deployment relate to the Pods from Day 01?**
A bare Pod from Day 01 and a Pod created by a Deployment are the same object type (`kind: Pod`) — the difference is ownership. A Deployment-created Pod has `ownerReferences` set to the ReplicaSet, which in turn has `ownerReferences` set to the Deployment. This ownership chain is what triggers garbage collection and recreation when a Pod disappears.

---

## 📚 Resources

- [Kubernetes Docs — Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [Kubernetes Docs — ReplicaSet](https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/)
- [Kubernetes Docs — kubectl create deployment](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#-em-deployment-em-)
- [Kubernetes Docs — Performing a Rolling Update](https://kubernetes.io/docs/tutorials/kubernetes-basics/update/update-intro/)
- **Related days:** [Day 01](../days/day-01/README.md) — Pod fundamentals (the building block a Deployment manages)
