# Day 03 — Namespaces and Deploying a Pod Into One

> #KodeKloud Kubernetes Challenge | Day 3 of 30

---

## 📌 The Task

| Requirement    | Value            |
|----------------|------------------|
| Namespace      | `dev`            |
| Pod name       | `dev-nginx-pod`  |
| Image          | `nginx:latest`   |
| Access method  | `kubectl` on jump-host |

---

## 🧠 Core Concepts

### What is a Namespace?

A **namespace** is a logical partition within a single Kubernetes cluster. Think of it as a virtual cluster inside the real one — resources in different namespaces are isolated from each other's view by default, even though they share the same underlying nodes, networking, and control plane.

The problem namespaces solve: as teams grow and the number of applications on a cluster scales, you need a way to separate workloads cleanly. Without namespaces, every team's Pods, Services, and Deployments would be in the same flat space — naming collisions, permission bleed-through, and accidental deletions become inevitable.

With namespaces:
- **Team A** can deploy a Service called `nginx` in namespace `team-a`
- **Team B** can deploy a Service also called `nginx` in namespace `team-b`
- No collision, and RBAC policies can be scoped so Team A can't touch Team B's resources at all

### The Four System Namespaces

Every fresh Kubernetes cluster ships with these:

| Namespace | Purpose |
|-----------|---------|
| `default` | Where resources land when you don't specify `-n`. Day 01 and Day 02 both used this. |
| `kube-system` | Control plane components: `kube-apiserver`, `kube-scheduler`, `coredns`, `kube-proxy`. Never deploy user workloads here. |
| `kube-public` | Readable by all unauthenticated users. Used for cluster-level public info (e.g., the `cluster-info` ConfigMap). Rarely touched. |
| `kube-node-lease` | Holds `Lease` objects for node heartbeats — the mechanism by which the control plane detects node failures. Fully managed by Kubernetes. |

### Namespace-Scoped vs Cluster-Scoped Resources

Not every resource lives inside a namespace. This distinction matters for RBAC and operational clarity:

- **Namespace-scoped:** Pods, Deployments, Services, ConfigMaps, Secrets, ReplicaSets, PVCs — these exist *within* a namespace and are invisible across namespace boundaries unless explicitly targeted
- **Cluster-scoped:** Nodes, PersistentVolumes, StorageClasses, Namespaces themselves, ClusterRoles, ClusterRoleBindings — these have no namespace and are visible cluster-wide

You can verify which resources are namespace-scoped vs cluster-scoped:
```bash
kubectl api-resources --namespaced=true   # namespace-scoped
kubectl api-resources --namespaced=false  # cluster-scoped
```

### Why Always Specify `-n` Explicitly

Without `-n`, `kubectl` uses whatever namespace is set in your kubeconfig context (usually `default`). In a lab this is fine. In production, implicit namespacing is how you accidentally deploy to the wrong environment, or `kubectl delete pod` something you shouldn't have.

The habit established in Day 01 — always pass `-n <namespace>` — pays off the moment you start working across multiple namespaces. It is also a CKA exam requirement: the exam gives you tasks across different namespaces explicitly, and forgetting `-n` is one of the most common marks lost.

### Namespace and the Pod Name Prefix Convention

The pod is named `dev-nginx-pod` — with a `dev-` prefix that echoes the namespace. This is a common convention in teams: prefix resource names with the namespace or environment (`dev-`, `staging-`, `prod-`) to make log tailing and `kubectl get` output readable at a glance even when you forget to filter by namespace. It is a naming convention, not enforced by Kubernetes.

---

## 🔧 Step-by-Step Solution

### Method 1 — kubectl Imperative + dry-run (Exam Technique)

Two-step process: create the namespace first, then generate and apply the Pod manifest targeting it.

**Step 1 — Verify cluster access**
```bash
kubectl get nodes
```

**Step 2 — Create the namespace**
```bash
kubectl create namespace dev
```

**Step 3 — Verify the namespace exists**
```bash
kubectl get namespace dev
```
Expected:
```
NAME   STATUS   AGE
dev    Active   5s
```

**Step 4 — Generate the Pod manifest via dry-run**

The `-n dev` flag on `kubectl run` sets the namespace in the generated manifest's `metadata.namespace` field.
```bash
kubectl run dev-nginx-pod \
  --image=nginx:latest \
  --dry-run=client -o yaml \
  -n dev > dev-nginx-pod.yaml
```

Review the manifest:
```bash
cat dev-nginx-pod.yaml
```

**Step 5 — Apply the manifest**
```bash
kubectl apply -f dev-nginx-pod.yaml
```

**Step 6 — Verify the Pod is Running**
```bash
kubectl get pod dev-nginx-pod -n dev
```

---

### Method 2 — YAML Manifest (Declarative — Production Grade)

**Step 1 — Write the namespace manifest**

```yaml
# dev-namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: dev
```

**Step 2 — Write the Pod manifest**

```yaml
# dev-nginx-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: dev-nginx-pod
  namespace: dev          # namespace declared in the manifest — no need for -n on apply
  labels:
    app: dev-nginx
spec:
  containers:
    - name: dev-nginx-pod
      image: nginx:latest
      ports:
        - containerPort: 80
```

**Step 3 — Apply both manifests**
```bash
kubectl apply -f dev-namespace.yaml
kubectl apply -f dev-nginx-pod.yaml
```

Or in one command if manifests are in the same directory:
```bash
kubectl apply -f .
```

**Step 4 — Wait for the Pod to be Ready**
```bash
kubectl wait pod/dev-nginx-pod \
  --for=condition=Ready \
  --timeout=60s \
  -n dev
```

**Step 5 — Verify Pod status**
```bash
kubectl get pod dev-nginx-pod -n dev
```
Expected:
```
NAME            READY   STATUS    RESTARTS   AGE
dev-nginx-pod   1/1     Running   0          20s
```

**Step 6 — Confirm namespace in the Pod spec**
```bash
kubectl get pod dev-nginx-pod -n dev -o jsonpath='{.metadata.namespace}'
```
Expected: `dev`

**Step 7 — Verify image tag**
```bash
kubectl get pod dev-nginx-pod -n dev \
  -o jsonpath='{.spec.containers[0].image}'
```
Expected: `nginx:latest`

**Step 8 — Full describe**
```bash
kubectl describe pod dev-nginx-pod -n dev
```

---

## 💻 Commands Reference

```bash
# Cluster check
kubectl get nodes

# Namespace management
kubectl create namespace dev
kubectl get namespaces
kubectl get namespace dev
kubectl describe namespace dev

# Method 1 — Imperative dry-run
kubectl run dev-nginx-pod \
  --image=nginx:latest \
  --dry-run=client -o yaml \
  -n dev > dev-nginx-pod.yaml
kubectl apply -f dev-nginx-pod.yaml

# Method 2 — Declarative
kubectl apply -f dev-namespace.yaml
kubectl apply -f dev-nginx-pod.yaml

# Verification
kubectl get pod dev-nginx-pod -n dev
kubectl get pod dev-nginx-pod -n dev --show-labels
kubectl get pod dev-nginx-pod -n dev -o wide
kubectl get pod dev-nginx-pod -n dev -o jsonpath='{.metadata.namespace}'
kubectl get pod dev-nginx-pod -n dev -o jsonpath='{.spec.containers[0].image}'
kubectl describe pod dev-nginx-pod -n dev
kubectl wait pod/dev-nginx-pod --for=condition=Ready --timeout=60s -n dev

# Cross-namespace visibility
kubectl get pods --all-namespaces          # every pod in every namespace
kubectl get pods -A                        # shorthand for --all-namespaces

# Logs
kubectl logs dev-nginx-pod -n dev

# Cleanup (run manually when done)
# Deleting the namespace cascades — all resources inside dev are deleted
# kubectl delete namespace dev
# kubectl delete pod dev-nginx-pod -n dev
# kubectl delete -f dev-nginx-pod.yaml
# rm -f dev-namespace.yaml dev-nginx-pod.yaml
```

---

## ⚠️ Common Mistakes

1. **Creating the Pod in `default` instead of `dev`**
   Omitting `-n dev` from `kubectl run` places the Pod in the `default` namespace. The validator looks in `dev` and finds nothing. Always set `-n <namespace>` on every command, including the dry-run generation step — the namespace propagates into the manifest's `metadata.namespace` field.

2. **`kubectl get pods` without `-n` shows nothing**
   After creating the Pod in `dev`, running `kubectl get pods` (no namespace flag) queries the `default` namespace and returns nothing. This looks like the Pod doesn't exist. It does — in `dev`. Always add `-n dev` or use `-A` / `--all-namespaces` to verify across all namespaces.

3. **Namespace deletion cascades — everything inside is gone**
   `kubectl delete namespace dev` does not ask for confirmation. It immediately begins deleting every Pod, Service, Deployment, ConfigMap, and Secret inside that namespace. In production this is catastrophic if done accidentally. Know what is in a namespace before deleting it.

4. **Namespace names must follow RFC 1123 DNS label rules**
   Namespace names must be lowercase, alphanumeric, and may contain hyphens — no underscores, no uppercase, no dots. `Dev`, `DEV`, `dev_env`, and `dev.env` are all invalid. `dev`, `dev-env`, `dev-01` are valid.

5. **Assuming `kube-system` is safe to deploy into**
   `kube-system` runs core Kubernetes components. Deploying user workloads there can interfere with control-plane scheduling, admission webhooks, and resource quotas. Never do it, even in labs.

6. **Not creating the namespace before the Pod**
   `kubectl apply -f dev-nginx-pod.yaml` fails with `namespace "dev" not found` if the namespace doesn't exist yet. Namespace creation must come first. When using `kubectl apply -f .`, apply order within a directory is alphabetical — name your namespace file `00-namespace.yaml` or apply it explicitly first.

7. **Mixing `-n` and `--namespace` inconsistently across commands**
   Both `-n dev` and `--namespace dev` are equivalent. The risk is dropping the flag entirely in a rush. Set the namespace explicitly on every single `kubectl` command — make it a reflex, not a decision.

---

## 🌍 Real-World Context

In production, namespaces are one of the first decisions a platform team makes when setting up a cluster for multiple teams or environments. A common pattern:

```
cluster
├── namespace: dev          ← developer sandbox, loose resource quotas
├── namespace: staging      ← pre-production, mirrors prod config
├── namespace: production   ← tight resource limits, PodDisruptionBudgets, strict RBAC
└── namespace: monitoring   ← Prometheus, Grafana, Alertmanager
```

Each namespace gets its own:
- **ResourceQuota** — limits total CPU, memory, and object counts that can be consumed
- **LimitRange** — sets default and max resource requests/limits per Pod
- **RBAC RoleBindings** — scopes which service accounts and users can do what within the namespace
- **NetworkPolicies** — controls which namespaces and Pods can talk to each other

The `dev` namespace in this task is the entry point into all of that. Namespaces are not security boundaries on their own (a compromised Pod in `dev` can still try to reach `production` over the network), but combined with NetworkPolicies and RBAC they form the layered access model that production multi-tenant clusters rely on.

---

## ❓ Interview Q&A

**Q1: What is a Kubernetes namespace and why do teams use them?**
A namespace is a logical partition inside a single cluster that provides isolated scopes for named resources. Teams use them to separate environments (dev/staging/prod), isolate teams from each other, apply resource quotas per team or application, and scope RBAC policies without needing separate clusters. They are the primary multi-tenancy mechanism below the cluster level.

**Q2: What happens if you don't specify a namespace when running kubectl commands?**
`kubectl` uses the namespace from the active kubeconfig context, which is `default` unless explicitly changed with `kubectl config set-context`. Commands silently target the wrong namespace, which is how engineers accidentally deploy to `default` instead of `prod`, or delete something they shouldn't have. Explicit `-n <namespace>` on every command is the safe habit.

**Q3: Are namespaces a security boundary in Kubernetes?**
Not on their own. Pods in different namespaces share the same underlying network and can reach each other by default. True isolation requires NetworkPolicies to restrict cross-namespace traffic, RBAC to scope what service accounts can do within each namespace, and Pod Security Admission (or OPA/Gatekeeper) to enforce what workloads can run. Namespaces give you the scope; the security controls operate within that scope.

**Q4: What is the difference between namespace-scoped and cluster-scoped resources?**
Namespace-scoped resources (Pods, Deployments, Services, ConfigMaps, Secrets) exist within a namespace and are not visible across namespace boundaries without targeting the namespace explicitly. Cluster-scoped resources (Nodes, PersistentVolumes, StorageClasses, ClusterRoles, the Namespace objects themselves) have no namespace and are visible cluster-wide. You can check which is which with `kubectl api-resources --namespaced=true/false`.

**Q5: What happens when you delete a namespace?**
All resources inside it are deleted — Pods, Deployments, Services, ConfigMaps, Secrets, PVCs, and more. It is a cascading, non-reversible operation. The namespace itself goes into `Terminating` status while all resources are garbage-collected, then disappears. In production, namespace deletion is a high-risk operation that should require explicit approval and a resource inventory review first.

**Q6: How do you see Pods across all namespaces at once?**
`kubectl get pods --all-namespaces` or the shorthand `kubectl get pods -A`. This is the first command to run when something is wrong and you're not sure which namespace a workload ended up in. Adding `-o wide` shows the node each Pod is on, which helps with node-level debugging.

**Q7: How do resource quotas interact with namespaces?**
A `ResourceQuota` object applied to a namespace enforces hard limits on the total resources consumed: CPU requests, memory limits, number of Pods, Services, PVCs, and more. If a Pod creation would push the namespace over quota, it is rejected at admission. This is how platform teams prevent a single team or runaway process from exhausting shared cluster resources.

---

## 📚 Resources

- [Kubernetes Docs — Namespaces](https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/)
- [Kubernetes Docs — Resource Quotas](https://kubernetes.io/docs/concepts/policy/resource-quotas/)
- [Kubernetes Docs — kubectl create namespace](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#-em-namespace-em-)
- [Kubernetes Docs — Namespace Walkthrough](https://kubernetes.io/docs/tasks/administer-cluster/namespaces-walkthrough/)
- **Related days:** [Day 01](../day-01/README.md) — Pod fundamentals | [Day 02](../day-02/README.md) — Deployments (all now deployable into any namespace)
