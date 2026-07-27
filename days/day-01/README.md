# Day 01 — Creating Your First Pod in Kubernetes

> #KodeKloud Kubernetes Challenge | Day 1 of 30

---

## 📌 The Task

| Requirement      | Value             |
|------------------|-------------------|
| Pod name         | `pod-nginx`       |
| Image            | `nginx:latest`    |
| Container name   | `nginx-container` |
| Label (`app`)    | `nginx_app`       |
| Access method    | `kubectl` on jump-host |

---

## 🧠 Core Concepts

### What is a Pod?

A **Pod** is the smallest deployable unit in Kubernetes — not a container, not a VM, but a logical wrapper around one or more containers that share the same network namespace, IP address, and storage volumes.

Think of it this way: Docker gives you containers. Kubernetes gives you Pods *around* those containers so the scheduler, the networking layer, and the control plane all have a consistent abstraction to work with regardless of the runtime underneath.

In production you almost never create bare Pods directly — you use Deployments, StatefulSets, or DaemonSets that manage Pods for you. But understanding bare Pod creation is foundational, and it maps directly to what those higher-level controllers do under the hood every time they spin up a replica.

### Pod Anatomy

A Pod spec has a handful of required fields:

- **`apiVersion: v1`** — Pods are a core resource available since Kubernetes 1.0; no `apps/` prefix needed
- **`kind: Pod`** — the resource type
- **`metadata`** — the control-plane-facing identity: name, namespace, labels, annotations
- **`spec.containers[]`** — the actual workload: image, name, ports, env, resources, probes

### Labels — Why They Matter More Than You Think

Labels like `app: nginx_app` are not metadata decoration. They are the **selector mechanism** that connects almost every Kubernetes concept together:

- A **Service** finds its target Pods by matching labels
- A **Deployment** knows which Pods it owns by matching labels
- **NetworkPolicies**, **PodDisruptionBudgets**, and **HorizontalPodAutoscalers** all operate on label selectors

Setting labels correctly at Pod creation is a habit that pays off the moment you layer Services or Deployments on top.

### Container Name vs Pod Name

These are separate identities:

- **Pod name** (`pod-nginx`) — what `kubectl get pods` shows; how the scheduler tracks it
- **Container name** (`nginx-container`) — what `kubectl logs <pod> -c <container>` and `kubectl exec` target; critical when a Pod runs multiple containers (sidecars, init containers)

Even in single-container Pods, naming your container explicitly is good practice because it makes multi-container evolution easier later — and because task validators check it.

### Why `kubectl run` Alone Is Not Enough Here

`kubectl run` is the imperative shortcut for creating Pods. It is fast and useful — but it has one hard limitation: **there is no flag to set a custom container name**. The container always inherits the Pod name. So `kubectl run pod-nginx` creates a container also named `pod-nginx`, not `nginx-container`.

This is not a missing feature — it is by design. For full spec control, Kubernetes expects you to write a manifest. The right imperative workflow is to use `kubectl run --dry-run=client -o yaml` to generate a YAML skeleton and then patch the container name before applying.

---

## 🔧 Step-by-Step Solution

### Method 1 — kubectl Imperative + dry-run (Exam Technique)

The CKA exam pattern: let `kubectl run` generate the YAML skeleton imperatively, patch the container name, then apply. Faster than writing YAML from scratch, and gives you full spec control.

**Step 1 — Verify cluster access**
```bash
kubectl get nodes
```

**Step 2 — Generate the Pod YAML skeleton using dry-run**
```bash
kubectl run pod-nginx \
  --image=nginx:latest \
  --labels="app=nginx_app" \
  --dry-run=client -o yaml > pod-nginx.yaml
```
`--dry-run=client -o yaml` prints what the object would look like without creating anything in the cluster. Redirect it to a file so you can edit it.

**Step 3 — Patch the container name**

Open `pod-nginx.yaml` and change the container name from `pod-nginx` to `nginx-container`:
```bash
# The generated file has:  name: pod-nginx  under spec.containers
# Change it to:            name: nginx-container

sed -i 's/  name: pod-nginx/  name: nginx-container/' pod-nginx.yaml
```

Verify the edit looks correct:
```bash
cat pod-nginx.yaml
```

**Step 4 — Apply the patched manifest**
```bash
kubectl apply -f pod-nginx.yaml
```

**Step 5 — Verify**
```bash
kubectl get pod pod-nginx -n default
kubectl get pod pod-nginx -n default --show-labels
kubectl get pod pod-nginx -n default -o jsonpath='{.spec.containers[0].name}'
```

---

### Method 2 — YAML Manifest (Declarative — Production Grade)

Write the full manifest from scratch. No ambiguity, no patching, no intermediate steps.

**Step 1 — Write the manifest**

```yaml
# pod-nginx.yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-nginx
  namespace: default
  labels:
    app: nginx_app
spec:
  containers:
    - name: nginx-container   # explicitly set — cannot be done via kubectl run alone
      image: nginx:latest
      ports:
        - containerPort: 80
```

**Step 2 — Apply**
```bash
kubectl apply -f pod-nginx.yaml
```

**Step 3 — Wait for Running state**
```bash
kubectl wait pod/pod-nginx --for=condition=Ready --timeout=60s -n default
```

**Step 4 — Verify Pod status**
```bash
kubectl get pod pod-nginx -n default
```
Expected:
```
NAME        READY   STATUS    RESTARTS   AGE
pod-nginx   1/1     Running   0          15s
```

**Step 5 — Verify labels**
```bash
kubectl get pod pod-nginx -n default --show-labels
```
Expected:
```
NAME        READY   STATUS    RESTARTS   AGE   LABELS
pod-nginx   1/1     Running   0          30s   app=nginx_app
```

**Step 6 — Verify container name**
```bash
kubectl get pod pod-nginx -n default -o jsonpath='{.spec.containers[0].name}'
```
Expected:
```
nginx-container
```

**Step 7 — Full describe**
```bash
kubectl describe pod pod-nginx -n default
```

---

## 💻 Commands Reference

```bash
# Cluster check
kubectl get nodes

# Method 1 — Imperative dry-run + patch
kubectl run pod-nginx \
  --image=nginx:latest \
  --labels="app=nginx_app" \
  --dry-run=client -o yaml > pod-nginx.yaml
sed -i 's/  name: pod-nginx/  name: nginx-container/' pod-nginx.yaml
kubectl apply -f pod-nginx.yaml

# Method 2 — Declarative apply
kubectl apply -f pod-nginx.yaml

# Verification
kubectl get pod pod-nginx -n default
kubectl get pod pod-nginx -n default --show-labels
kubectl get pod pod-nginx -n default -o wide
kubectl get pod pod-nginx -n default -o jsonpath='{.spec.containers[0].name}'
kubectl describe pod pod-nginx -n default

# Logs
kubectl logs pod-nginx -n default -c nginx-container

# If recreating after a failed attempt
kubectl delete pod pod-nginx -n default

# Cleanup (run manually when done)
# kubectl delete -f pod-nginx.yaml
# rm -f pod-nginx.yaml
```

---

## ⚠️ Common Mistakes

1. **`kubectl run` has no `--container-name` flag — this broke the first attempt**
   Running `kubectl run pod-nginx --image=nginx:latest` creates a container named `pod-nginx`, not `nginx-container`. The task validator checks the container name and rejects the Pod. There is no workaround within pure `kubectl run` — you must use `--dry-run=client -o yaml`, edit the name, and apply.

2. **The `sed` patch targets the wrong line**
   The `kubectl run` YAML output has `name: pod-nginx` in two places: once under `metadata` (the Pod name) and once under `spec.containers` (the container name). The `sed` command above uses leading spaces (`  name: pod-nginx`) to target only the container entry. Without that, you risk renaming the Pod itself.

3. **Omitting the image tag**
   `--image=nginx` and `--image=nginx:latest` both work at runtime but the task explicitly requires `:latest` to be specified. Match the spec exactly — validators are literal.

4. **Wrong label key syntax with `kubectl run`**
   `--labels="app=nginx_app"` works. `--label` (singular) does not exist on `kubectl run`. Common typo under time pressure.

5. **Spec fields are immutable after Pod creation**
   If you created a Pod with the wrong container name, `kubectl edit` will not let you change `spec.containers[].name` — it is immutable. You must delete and recreate: `kubectl delete pod pod-nginx -n default && kubectl apply -f pod-nginx.yaml`.

6. **Assuming `default` namespace without verifying**
   Always pass `-n <namespace>` explicitly. If the lab targets a custom namespace and you deploy to `default`, the validator will not find your Pod. Confirm with `kubectl get namespaces` if in doubt.

7. **Reading `STATUS` but not `READY`**
   A Pod can show `STATUS: Running` but `READY: 0/1` if the container is still starting or a readiness probe is failing. Always check both columns. For plain `nginx:latest` with no probe defined this resolves quickly, but it is a habit worth building now.

---

## 🌍 Real-World Context

In production you would almost never run a bare Pod like this. A bare Pod has no self-healing — if the node it runs on dies, the Pod is gone and nothing reschedules it. That is why production workloads always go through a **Deployment** (stateless apps), a **StatefulSet** (databases, ordered workloads), or a **DaemonSet** (one instance per node for agents like Fluentd or Prometheus node-exporter).

That said, bare Pods matter in production contexts:

- **Debugging** — `kubectl run debug-pod --image=busybox --rm -it -- /bin/sh` is how senior engineers drop a temporary shell into a cluster's network namespace to diagnose connectivity issues
- **Sidecar and init container patterns** — understanding Pod spec is prerequisite to building Envoy proxies, log shippers, and cert-refresh init containers
- **Operator and controller development** — custom controllers ultimately reconcile state by creating Pods or their parent resources; Pod spec fluency is non-negotiable

The label `app: nginx_app` you set here becomes the selector in every Service, NetworkPolicy, and HPA that targets this workload. Getting labels right from day one is not ceremony — it is architecture.

---

## ❓ Interview Q&A

**Q1: What is the difference between a Pod and a container?**
A container is a runtime process — a Docker or containerd concept with its own filesystem and process namespace. A Pod is a Kubernetes abstraction that wraps one or more containers and gives them a shared IP address and shared network namespace. Two containers in the same Pod communicate over `localhost` because they share the network stack. Kubernetes schedules and manages Pods, not containers directly.

**Q2: Why would you ever run a bare Pod instead of a Deployment?**
Mostly for debugging and ephemeral tasks — `kubectl run` with `--rm -it` to drop a temporary shell into a cluster's network plane, or one-off batch jobs where you do not need restart semantics. In every production scenario you want a controller managing the Pod lifecycle.

**Q3: What happens to a bare Pod if the node it runs on fails?**
It is gone. A bare Pod has no controller watching it, so the scheduler does not reschedule it. This is exactly why Deployments exist — the ReplicaSet controller notices the count dropped below desired and creates a replacement on a healthy node automatically.

**Q4: Why does label selection matter so much in Kubernetes?**
Labels are the glue. Services route traffic to Pods matching a selector. Deployments claim ownership of Pods the same way. NetworkPolicies restrict traffic based on labels. If your labels are inconsistent, you end up with Services that select nothing and policies with gaps. Treat labels as part of your API contract.

**Q5: Can you change a container's name after a Pod is created?**
No. Container name is part of the Pod spec and most spec fields are immutable after creation. You must delete and recreate the Pod. This is another reason Deployments are preferable in production — rolling updates handle spec changes by creating new Pods with the updated spec and terminating old ones.

**Q6: What is the `--dry-run=client -o yaml` pattern and why is it useful?**
It tells `kubectl` to build the full resource object locally and print it as YAML without sending anything to the API server. For CKA exam scenarios this is the fastest way to get a correct YAML skeleton — let the generator handle `apiVersion`, `kind`, and basic spec structure, then edit only the fields you need to change (like container name or resource limits) before applying.

**Q7: What does `1/1 READY` mean in `kubectl get pods` output?**
It means 1 of 1 containers in the Pod has passed its readiness probe (or started successfully if no probe is configured). `0/1` means the container is not yet ready to serve traffic even if `STATUS` shows `Running`. Always check both columns before declaring a Pod healthy.

---

## 📚 Resources

- [Kubernetes Docs — Pods](https://kubernetes.io/docs/concepts/workloads/pods/)
- [Kubernetes Docs — Labels and Selectors](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/)
- [Kubernetes Docs — kubectl run](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#run)
- [Kubernetes Docs — Pod Lifecycle](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)
- **Related days:** Day 02 will build on Pod fundamentals with multi-container patterns
