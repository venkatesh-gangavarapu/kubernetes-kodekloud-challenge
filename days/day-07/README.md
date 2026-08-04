# Day 07 — Creating a ReplicaSet in Kubernetes

> #KodeKloud Kubernetes Challenge | Day 7 of 30

---

## 📌 The Task

| Requirement      | Value              |
|------------------|--------------------|
| Kind             | ReplicaSet         |
| Name             | `httpd-replicaset` |
| Image            | `httpd:latest`     |
| Container name   | `httpd-container`  |
| Label `app`      | `httpd_app`        |
| Label `type`     | `front-end`        |
| Replica count    | `4`                |
| Namespace        | `default`          |

---

## 🧠 Core Concepts

### There Is No `kubectl create replicaset` Command

This is the first task in this challenge where the imperative shortcut simply does not exist. `kubectl create deployment` exists. `kubectl run` exists. **`kubectl create replicaset` does not.** The only supported approach is a YAML manifest.

On a CKA exam, this catches engineers who rely on `--dry-run=client -o yaml` as a universal skeleton generator. For a ReplicaSet you either write the YAML from memory, or you use a Deployment dry-run as a rough starting point and edit heavily — but by the time you've stripped the `strategy`, `progressDeadlineSeconds`, and other Deployment-specific fields and changed the `kind`, writing from scratch is faster.

This task is a test of manifest fluency, not imperative flag knowledge.

### What Is a ReplicaSet?

A **ReplicaSet** is the Kubernetes controller responsible for maintaining a stable number of identical Pod replicas running at any given time. It watches the cluster and takes corrective action whenever the actual Pod count diverges from the desired count:

- Too few Pods → ReplicaSet creates replacements
- Too many Pods → ReplicaSet deletes the excess
- A node dies taking a Pod with it → ReplicaSet schedules a replacement on a healthy node

Day 02 introduced the Deployment → ReplicaSet → Pod chain. Every Deployment you've created since Day 02 has been creating and managing a ReplicaSet automatically. Today you create one directly, bypassing the Deployment layer.

### ReplicaSet vs Deployment — The Critical Operational Difference

| Capability | ReplicaSet | Deployment |
|------------|-----------|------------|
| Maintains desired replica count | ✅ Yes | ✅ Yes (via RS) |
| Self-healing (reschedule on node failure) | ✅ Yes | ✅ Yes |
| Rolling update on image change | ❌ No | ✅ Yes |
| Rollback history | ❌ No | ✅ Yes |
| `rollout status` / `rollout undo` | ❌ No | ✅ Yes |
| Used directly in production | Rarely | Standard |

**The most important difference:** if you update the image in a ReplicaSet's Pod template, **existing Pods are NOT replaced**. The new image only appears in Pods that are newly created (e.g., after a scale-up or a Pod is manually deleted). A Deployment wraps the ReplicaSet precisely to add rolling update and rollback capabilities on top of it.

In production, you use a ReplicaSet directly only in specific advanced scenarios — custom controllers, operators, or cases where you need raw replica management without update semantics. For everything else, the Deployment is the right abstraction.

### The `selector.matchLabels` Contract

This is the mechanism that wires a ReplicaSet to the Pods it owns — and it must be exact. The spec has three places where labels appear:

```yaml
metadata:
  labels:           # Labels on the ReplicaSet object itself (for querying RSes)
    app: httpd_app
    type: front-end

spec:
  selector:
    matchLabels:    # The selector the RS uses to find/claim Pods — IMMUTABLE after creation
      app: httpd_app
      type: front-end

  template:
    metadata:
      labels:       # Labels applied to each Pod the RS creates — MUST match matchLabels
        app: httpd_app
        type: front-end
```

If `selector.matchLabels` and `template.metadata.labels` do not match, Kubernetes rejects the ReplicaSet at admission with a validation error. If they match correctly, the ReplicaSet claims ownership of any existing Pods in the namespace with those labels — even ones it did not create. This label-adoption behaviour is important: if a loose Pod from a previous attempt has the same labels, the ReplicaSet counts it toward its desired total.

### `apiVersion: apps/v1` — Not `v1`

ReplicaSet is in the `apps` API group, not the core group. A common mistake is writing `apiVersion: v1` (correct for Pods and Namespaces) instead of `apiVersion: apps/v1` (required for ReplicaSets, Deployments, StatefulSets, DaemonSets). The API server rejects `apiVersion: v1` for a ReplicaSet with a "no kind ReplicaSet is registered" error.

### Labels in This Task — Two Labels, Three Locations

Both `app: httpd_app` and `type: front-end` must appear in all three label locations (RS metadata, selector.matchLabels, and template.metadata.labels). Missing either label from the template means Pods are created without that label, the selector does not match them, and the ReplicaSet enters a creation loop — spinning up new Pods endlessly while orphaning the ones it just created.

---

## 🔧 Step-by-Step Solution

### Method 1 — Deployment Dry-Run + Convert (Closest Imperative Approximation)

There is no `kubectl create replicaset` command. The closest imperative approach for a CKA exam is generating a Deployment skeleton and editing it into a ReplicaSet. This works but requires significant editing — judge whether writing from scratch (Method 2) is faster.

**Step 1 — Generate a Deployment skeleton as a starting point**
```bash
kubectl create deployment httpd-replicaset \
  --image=httpd:latest \
  --replicas=4 \
  --dry-run=client -o yaml > httpd-replicaset.yaml
```

**Step 2 — Edit the manifest into a valid ReplicaSet**

Open `httpd-replicaset.yaml` and make these changes:
- Change `kind: Deployment` → `kind: ReplicaSet`
- Remove the `strategy: {}` block entirely (ReplicaSets have no update strategy)
- Remove `progressDeadlineSeconds`, `revisionHistoryLimit` (Deployment-only fields)
- Add `type: front-end` label to `metadata.labels`, `selector.matchLabels`, and `template.metadata.labels`
- Change container name from `httpd-replicaset` to `httpd-container`

**Step 3 — Apply and verify**
```bash
kubectl apply -f httpd-replicaset.yaml
kubectl get replicaset httpd-replicaset -n default
```

For this task, **Method 2 is faster and less error-prone.**

---

### Method 2 — YAML Manifest Written Directly (Recommended for ReplicaSet)

**Step 1 — Write the manifest**

```yaml
# httpd-replicaset.yaml
apiVersion: apps/v1          # NOT v1 — ReplicaSet is in the apps API group
kind: ReplicaSet
metadata:
  name: httpd-replicaset
  namespace: default
  labels:
    app: httpd_app           # labels on the RS object itself
    type: front-end
spec:
  replicas: 4                # desired Pod count
  selector:
    matchLabels:             # RS uses this to claim and count owned Pods
      app: httpd_app         # must exactly match template.metadata.labels
      type: front-end
  template:                  # Pod template — RS uses this to create new Pods
    metadata:
      labels:
        app: httpd_app       # must exactly match selector.matchLabels
        type: front-end
    spec:
      containers:
        - name: httpd-container   # explicit container name required by task
          image: httpd:latest
          ports:
            - containerPort: 80
```

**Step 2 — Apply the manifest**
```bash
kubectl apply -f httpd-replicaset.yaml
```

**Step 3 — Wait for all 4 replicas to be ready**
```bash
kubectl wait replicaset/httpd-replicaset \
  --for=jsonpath='{.status.readyReplicas}'=4 \
  --timeout=90s \
  -n default
```

**Step 4 — Verify ReplicaSet status**
```bash
kubectl get replicaset httpd-replicaset -n default
```
Expected:
```
NAME               DESIRED   CURRENT   READY   AGE
httpd-replicaset   4         4         4       30s
```
All three columns must match: `DESIRED=4 CURRENT=4 READY=4`.

**Step 5 — Verify all 4 Pods are Running**
```bash
kubectl get pods -n default -l app=httpd_app
```
Expected: 4 Pods, all `STATUS=Running`, all `READY=1/1`.

**Step 6 — Verify labels on the ReplicaSet**
```bash
kubectl get replicaset httpd-replicaset -n default --show-labels
```
Expected: `app=httpd_app,type=front-end`

**Step 7 — Verify labels on the Pods**
```bash
kubectl get pods -n default --show-labels -l app=httpd_app
```
Expected: all Pods carry both `app=httpd_app` and `type=front-end`.

**Step 8 — Verify container name**
```bash
kubectl get replicaset httpd-replicaset -n default \
  -o jsonpath='{.spec.template.spec.containers[0].name}'
```
Expected: `httpd-container`

**Step 9 — Verify image tag**
```bash
kubectl get replicaset httpd-replicaset -n default \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
```
Expected: `httpd:latest`

**Step 10 — Full describe**
```bash
kubectl describe replicaset httpd-replicaset -n default
```
Check: `Replicas: 4 current / 4 desired`, both labels present, image correct.

---

## 💻 Commands Reference

```bash
# Cluster check
kubectl get nodes

# Apply the manifest
kubectl apply -f httpd-replicaset.yaml

# ReplicaSet status
kubectl get replicaset httpd-replicaset -n default
kubectl get replicaset httpd-replicaset -n default --show-labels
kubectl describe replicaset httpd-replicaset -n default

# Pod verification (label selector filters to RS-owned pods only)
kubectl get pods -n default -l app=httpd_app
kubectl get pods -n default -l app=httpd_app --show-labels
kubectl get pods -n default -l "app=httpd_app,type=front-end"

# Container name check
kubectl get replicaset httpd-replicaset -n default \
  -o jsonpath='{.spec.template.spec.containers[0].name}'

# Image check
kubectl get replicaset httpd-replicaset -n default \
  -o jsonpath='{.spec.template.spec.containers[0].image}'

# Scale the ReplicaSet (not via Deployment — no rollout history)
kubectl scale replicaset httpd-replicaset --replicas=6 -n default

# Imperative scale shorthand
kubectl scale rs httpd-replicaset --replicas=4 -n default   # rs = alias for replicaset

# What happens if you update the image on a bare ReplicaSet
# (existing pods are NOT updated — only new pods get the new image)
kubectl set image replicaset/httpd-replicaset httpd-container=httpd:2.4 -n default
# Then check: old pods still run httpd:latest, only newly created pods run httpd:2.4

# Cleanup (run manually when done)
# kubectl delete replicaset httpd-replicaset -n default
# kubectl delete -f httpd-replicaset.yaml
# rm -f httpd-replicaset.yaml
```

---

## ⚠️ Common Mistakes

1. **Trying `kubectl create replicaset` — this command does not exist**
   There is no imperative shortcut for ReplicaSet. Running `kubectl create replicaset` returns `error: unknown command`. The only path is a YAML manifest. On a CKA exam, knowing the ReplicaSet manifest structure from memory is required — there is no dry-run skeleton generator for this resource kind.

2. **Using `apiVersion: v1` instead of `apps/v1`**
   `v1` is the core API group — correct for Pods, Namespaces, ConfigMaps, Services. ReplicaSet (like Deployment, StatefulSet, DaemonSet) lives in `apps/v1`. The API server returns `no matches for kind "ReplicaSet" in version "v1"` — a clear error but easy to miss under time pressure.

3. **`selector.matchLabels` and `template.metadata.labels` mismatch**
   Both must carry identical label key-value pairs. Missing `type: front-end` from `template.metadata.labels` while having it in `selector.matchLabels` means newly created Pods do not match the selector. The RS treats them as unclaimed and keeps creating more Pods indefinitely while existing ones pile up unowned.

4. **Applying both labels to only one of the three locations**
   The two labels belong in: (1) `metadata.labels` on the RS object, (2) `selector.matchLabels`, and (3) `template.metadata.labels`. Engineers often put them in metadata but forget one or both label locations in the spec, causing validation failures or the creation-loop described above.

5. **Expecting image updates to roll out to existing Pods**
   `kubectl set image replicaset/httpd-replicaset ...` updates the Pod template, but existing Pods are never replaced. Only Pods created after the template change get the new image. If you need existing Pods updated, you must delete them manually — the RS recreates them with the new template. This is the absence of rolling update semantics and the core reason Deployments exist.

6. **Confusing ReplicaSet with ReplicationController**
   `ReplicationController` is the older pre-`apps/v1` resource that served the same purpose as ReplicaSet. It uses equality-based selectors (`selector: app: httpd_app`) rather than set-based ones (`matchLabels`). ReplicationController is deprecated — always use ReplicaSet when you need direct replica management, and Deployment when you need updates.

7. **Not checking `READY` count, only `DESIRED`**
   `kubectl get replicaset` showing `DESIRED=4` does not mean 4 Pods are Running. `CURRENT` shows Pods created, `READY` shows Pods that passed their readiness check. A validator checking for 4 running replicas expects `READY=4`. Always confirm all three columns match before declaring success.

---

## 🌍 Real-World Context

In modern Kubernetes workflows, you almost never write a ReplicaSet manifest directly in production. The Deployment abstraction handles replica management plus rolling updates and rollback — there is rarely a reason to skip it.

That said, ReplicaSets matter in two real-world contexts:

**Custom controllers and operators** — if you are writing a Kubernetes operator (using controller-runtime or kubebuilder), you may create ReplicaSets programmatically for workloads where you want to own the update logic yourself, without Deployment's rolling update behaviour interfering with your controller's reconciliation loop.

**Debugging and forensics** — when a Deployment behaves unexpectedly, inspecting its ReplicaSets directly is often the fastest path to root cause. `kubectl get replicaset -n <namespace>` shows how many RSes exist, which is current, and which old ones are sitting at 0 replicas (the rollback snapshots from Day 06). Understanding what each RS contains tells you exactly what image each revision deployed.

For this migration task, the team has created a bare ReplicaSet as a stepping stone — likely because the workload needs stable replica count without the complexity of a Deployment during the initial migration phase. Once stable, the natural progression is wrapping it in a Deployment for production-grade lifecycle management.

---

## ❓ Interview Q&A

**Q1: What is the difference between a ReplicaSet and a Deployment?**
A ReplicaSet maintains a desired number of Pod replicas and self-heals on node failure, but has no built-in rolling update or rollback capability. Changing the Pod template does not update existing Pods. A Deployment wraps a ReplicaSet and adds rolling update semantics — it creates a new ReplicaSet on template change, incrementally scales it up, and keeps the old ReplicaSet for rollback. In production, you use Deployments; ReplicaSets are managed for you as an implementation detail.

**Q2: What happens if you update the image directly on a ReplicaSet?**
The Pod template is updated, but existing Pods continue running the old image — the ReplicaSet controller does not replace them. Only newly created Pods (from a scale-up or manual Pod deletion) get the new image. This is the fundamental difference from a Deployment: there is no automatic rollout. If you need all Pods updated on a bare ReplicaSet, you must delete existing Pods manually, one or more at a time, and the RS will recreate them with the new template.

**Q3: Why must `selector.matchLabels` exactly match `template.metadata.labels`?**
The selector is how the ReplicaSet identifies which Pods it owns. If a Pod's labels do not match the selector, the RS does not count it toward its desired replica total and creates additional Pods — potentially an infinite loop. Kubernetes enforces this at admission: a ReplicaSet where the selector does not match the template is rejected immediately rather than allowed to create runaway Pods.

**Q4: Can a ReplicaSet adopt Pods it did not create?**
Yes. If a Pod already exists in the namespace with labels that match a ReplicaSet's `selector.matchLabels`, the RS adopts it and counts it toward its desired total. This means: if you already have 2 Pods with matching labels and create a RS with `replicas: 4`, the RS only creates 2 additional Pods (not 4). This adoption behaviour can cause confusion when cleaning up after failed experiments.

**Q5: What is the difference between `ReplicaSet` and `ReplicationController`?**
`ReplicationController` is the older resource that predates ReplicaSet. Its selector uses equality-based matching only (`app: nginx`). ReplicaSet uses set-based selectors (`matchLabels`, `matchExpressions`) — more flexible and consistent with how the rest of Kubernetes uses label selectors. ReplicationController is deprecated; any new workload should use ReplicaSet (or more commonly, Deployment).

**Q6: Why does Deployment keep old ReplicaSets at 0 replicas after an update?**
For rollback. When `kubectl rollout undo` is executed, it simply scales the previous ReplicaSet back up and scales the current one down — no image re-pull, no manifest re-apply. The old RS serves as a versioned snapshot of the previous Pod template. `revisionHistoryLimit` (default: 10) controls how many of these zero-replica RSes are retained.

**Q7: How would you scale a ReplicaSet without a Deployment?**
`kubectl scale replicaset httpd-replicaset --replicas=6 -n default` or the alias `kubectl scale rs httpd-replicaset --replicas=6`. This changes the `spec.replicas` field immediately. There is no rolling behaviour — the RS creates or deletes Pods to reach the new count as fast as the scheduler and kubelet allow. For Deployments, scaling is the same command with `deployment` instead of `replicaset`.

---

## 📚 Resources

- [Kubernetes Docs — ReplicaSet](https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/)
- [Kubernetes Docs — ReplicaSet vs ReplicationController](https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/#replicaset-vs-replicationcontroller)
- [Kubernetes Docs — Label Selectors](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/#label-selectors)
- **Related days:** [Day 01](../day-01/README.md) — Labels as selectors | [Day 02](../day-02/README.md) — Deployment owns a ReplicaSet | [Day 05](../day-05/README.md) — Rolling updates (what a bare RS cannot do)
