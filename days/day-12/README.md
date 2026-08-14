# Day 14 — Kubernetes: Update Deployment and Service (nginx-deployment)

> **#100DaysOfCloud | Day 14 of 100**

---

## 📌 The Task

> *Apply three changes to a live nginx deployment and service — without deleting either resource.*

**Changes required:**

| # | Resource | Change |
|---|----------|--------|
| 1 | `nginx-service` | NodePort `30008` → `32165` |
| 2 | `nginx-deployment` | Replicas `1` → `5` |
| 3 | `nginx-deployment` | Image `nginx:1.17` → `nginx:latest` |

**Constraint:** Do not delete `nginx-deployment` or `nginx-service`.

---

## 🧠 Core Concepts

### Three kubectl Mutation Patterns

Each change uses a different kubectl command — each is the right tool for its specific job:

| Change | Command | Why |
|--------|---------|-----|
| NodePort | `kubectl patch` | Surgical JSON Patch — modifies a specific field at a known path |
| Replicas | `kubectl scale` | Purpose-built replica control — cleaner than patching `spec.replicas` |
| Image | `kubectl set image` | Purpose-built image update — triggers rolling update automatically |

### `kubectl patch` — Surgical Field Updates

`kubectl patch` modifies specific fields of a live resource without touching anything else. Three patch types:

```bash
# JSON Patch (RFC 6902) — most explicit, targets exact path
kubectl patch service nginx-service \
    --type='json' \
    -p='[{"op":"replace","path":"/spec/ports/0/nodePort","value":32165}]'

# Strategic Merge Patch — merge a partial object (default)
kubectl patch service nginx-service \
    -p='{"spec":{"ports":[{"nodePort":32165}]}}'

# Merge Patch — simple key-value merge
kubectl patch deployment nginx-deployment \
    --type='merge' \
    -p='{"spec":{"replicas":5}}'
```

JSON Patch is the most precise — it targets `/spec/ports/0/nodePort` (index 0 in the ports array) so it never accidentally affects other ports if multiple exist.

### `kubectl scale` — Replica Control

```bash
kubectl scale deployment nginx-deployment --replicas=5
```

Simple and purpose-built. Under the hood this patches `spec.replicas`, but `kubectl scale` is the conventional command used in runbooks, on-call docs, and interviews. Always follow with `kubectl rollout status` to block until ready.

### `kubectl set image` — Rolling Update Trigger

```bash
kubectl set image deployment/nginx-deployment <container-name>=nginx:latest
```

The container name is required and must match the name in the deployment's `spec.template.spec.containers[].name`. Get it first:

```bash
kubectl get deployment nginx-deployment \
    -o jsonpath='{.spec.template.spec.containers[0].name}'
```

`kubectl set image` triggers a **rolling update** — Kubernetes replaces pods one-by-one (respecting `maxUnavailable` and `maxSurge` settings) so the application stays available during the image change.

### Rolling Update Mechanics

With 5 replicas and default rolling update settings (`maxSurge: 25%`, `maxUnavailable: 25%`):

```
Before update:  5 × nginx:1.17 pods
During update:  4 × nginx:1.17 + 1 × nginx:latest (surge by 1, kill 1 old)
               3 × nginx:1.17 + 2 × nginx:latest
               ...
After update:   5 × nginx:latest pods
```

`kubectl rollout status deployment/nginx-deployment` blocks and streams progress until complete — the right gate to use in scripts before declaring success.

### NodePort Services — How Port Numbers Work

```
Client → NodePort (32165 on every node) → ClusterIP → Pod (port 80)
```

NodePort range: `30000–32767` (Kubernetes default). Each NodePort is opened on **every** node in the cluster. A request to `<any-node-ip>:32165` reaches the service regardless of which node the pod is on.

Changing the NodePort modifies the rule on every node simultaneously — Kubernetes updates the `kube-proxy` iptables rules across all nodes within seconds.

---

## 🔧 Step-by-Step Solution

### Method 1 — kubectl (Imperative, Fastest)

```bash
# Change 1: NodePort
kubectl patch service nginx-service \
    --type='json' \
    -p='[{"op":"replace","path":"/spec/ports/0/nodePort","value":32165}]'

# Change 2: Replicas
kubectl scale deployment nginx-deployment --replicas=5
kubectl rollout status deployment/nginx-deployment

# Change 3: Image
CONTAINER=$(kubectl get deployment nginx-deployment \
    -o jsonpath='{.spec.template.spec.containers[0].name}')
kubectl set image deployment/nginx-deployment ${CONTAINER}=nginx:latest
kubectl rollout status deployment/nginx-deployment
```

### Method 2 — YAML (Declarative)

```bash
# Export, edit, apply
kubectl get deployment nginx-deployment -o yaml > dep.yaml
kubectl get service nginx-service -o yaml > svc.yaml

# Edit dep.yaml: spec.replicas: 5, containers[0].image: nginx:latest
# Edit svc.yaml: spec.ports[0].nodePort: 32165

kubectl apply -f dep.yaml
kubectl apply -f svc.yaml
kubectl rollout status deployment/nginx-deployment
```

---

## 💻 Commands Reference

```bash
# --- PRE-CHANGE STATE ---
kubectl get deployment nginx-deployment -o wide
kubectl get service nginx-service -o wide
kubectl get deployment nginx-deployment \
    -o jsonpath='Image: {.spec.template.spec.containers[0].image}, Replicas: {.spec.replicas}{"\n"}'
kubectl get service nginx-service \
    -o jsonpath='NodePort: {.spec.ports[0].nodePort}{"\n"}'

# --- CHANGE 1: NODEPORT ---
kubectl patch service nginx-service \
    --type='json' \
    -p='[{"op":"replace","path":"/spec/ports/0/nodePort","value":32165}]'

# --- CHANGE 2: REPLICAS ---
kubectl scale deployment nginx-deployment --replicas=5
kubectl rollout status deployment/nginx-deployment

# --- CHANGE 3: IMAGE ---
kubectl set image deployment/nginx-deployment \
    $(kubectl get deploy nginx-deployment \
      -o jsonpath='{.spec.template.spec.containers[0].name}')=nginx:latest
kubectl rollout status deployment/nginx-deployment

# --- VERIFY ALL THREE ---
kubectl get deployment nginx-deployment -o wide
kubectl get service nginx-service -o wide
kubectl get pods -l app=nginx

# --- JSONPATH VERIFICATION ---
kubectl get deploy nginx-deployment \
    -o jsonpath='Replicas: {.status.readyReplicas}, Image: {.spec.template.spec.containers[0].image}{"\n"}'
kubectl get svc nginx-service \
    -o jsonpath='NodePort: {.spec.ports[0].nodePort}{"\n"}'

# --- ROLLBACK IF NEEDED ---
kubectl rollout undo deployment/nginx-deployment
kubectl rollout history deployment/nginx-deployment
```

---

## ⚠️ Common Mistakes

**1. Using `kubectl edit` for NodePort and accidentally triggering a full resource replacement**
`kubectl edit service nginx-service` opens the full YAML in an editor. If you accidentally modify any immutable fields or introduce YAML syntax errors and save, the service update fails or the service is briefly disrupted. `kubectl patch` with JSON Patch is surgical and safer — it touches only the specified path.

**2. Not getting the container name before `kubectl set image`**
`kubectl set image deployment/nginx-deployment nginx=nginx:latest` assumes the container is named `nginx`. If the container was named `nginx-container` or `app`, the command silently succeeds but no image changes — Kubernetes applies the image update only to the matching container name. Always resolve the actual container name first with jsonpath.

**3. Not waiting for `rollout status` before verifying**
Immediately running `kubectl get pods` after `kubectl set image` shows pods in `ContainerCreating` or `Terminating` state — the rollout is still in progress. `kubectl rollout status deployment/nginx-deployment` blocks until all replicas are running the new image. Without this gate, verification passes on partial rollout.

**4. Confusing `spec.replicas` (desired) with `status.readyReplicas` (actual)**
After `kubectl scale --replicas=5`, `spec.replicas` is immediately `5` but `status.readyReplicas` may still be `1` while pods are starting. Always verify readiness using `status.readyReplicas` or `kubectl rollout status`, not `spec.replicas`.

**5. Using NodePort outside the valid range 30000–32767**
NodePorts must be in the range `30000–32767` (Kubernetes default). Using `32165` is valid. Using a port like `8080` or `443` fails with `The Service "nginx-service" is invalid: spec.ports[0].nodePort: Invalid value`. The range can be changed via `--service-node-port-range` on the API server, but in KodeKloud labs the default applies.

---

## 🌍 Real-World Context

**Rolling updates in production:** `kubectl set image` is frequently used in CI/CD pipelines as the deployment trigger:
```bash
# GitHub Actions / GitLab CI pattern:
kubectl set image deployment/nginx-deployment \
    nginx=nginx:${DOCKER_IMAGE_TAG}
kubectl rollout status deployment/nginx-deployment --timeout=5m
```

If the rollout fails (new image crashes, health checks fail), `kubectl rollout undo` reverts to the previous version within seconds.

**NodePort vs LoadBalancer vs Ingress:** NodePort is the simplest external access method — expose a port on every node. In production, a LoadBalancer service (cloud provider-managed) or Ingress controller is preferred — NodePort requires clients to know a node IP, and opening ports on every node exposes the service even on nodes that don't have the pod. NodePort is ideal for labs, development clusters, and on-premises environments where a cloud load balancer isn't available.

**Replica count and Pod Disruption Budgets (PDBs):** Scaling to 5 replicas is safe here. In production, scaling down requires care — a Pod Disruption Budget (`kubectl get pdb`) may enforce a minimum number of available replicas, preventing scale-down below a certain threshold to maintain availability during voluntary disruptions.

---

## ❓ Interview Q&A — As a Real-World DevOps Engineer

**Q1. What are the three kubectl patch types and when would you use each?**
> Strategic Merge Patch (default): merge a partial resource object into the existing one — good for most object modifications where you provide just the changed fields. JSON Patch (RFC 6902): an array of operations (`add`, `remove`, `replace`, `move`, `copy`, `test`) targeting exact JSON paths — most precise, necessary when you need to modify a specific array element by index (like changing one port in a multi-port service). Merge Patch: simpler than strategic merge, replaces lists entirely rather than merging — risky for arrays because it replaces the whole list rather than merging elements. For changing a specific NodePort in a service with multiple ports, JSON Patch is the safest because it targets `/spec/ports/0/nodePort` without touching other ports.

**Q2. What happens during a rolling update, and how do `maxUnavailable` and `maxSurge` control it?**
> Kubernetes replaces pods one by one (or in batches) rather than terminating all old pods and creating new ones simultaneously. `maxUnavailable` sets how many pods can be unavailable below the desired replica count during the update — a value of `1` means at most one pod can be down at any time. `maxSurge` sets how many extra pods can exist above the desired count during the update — `1` means Kubernetes creates one new pod before terminating an old one. With 5 replicas, `maxUnavailable: 1` and `maxSurge: 1`, the sequence is: create one new pod (6 total), wait for it to be ready, terminate one old pod (5 total), repeat. At no point are fewer than 4 pods available, maintaining 80% capacity throughout.

**Q3. How do you roll back a deployment to its previous version?**
> `kubectl rollout undo deployment/nginx-deployment` immediately rolls back to the previous revision. Kubernetes stores revision history (default 10 revisions). To roll back to a specific revision: `kubectl rollout undo deployment/nginx-deployment --to-revision=2`. View history with `kubectl rollout history deployment/nginx-deployment`. Under the hood, a rollback is just another rolling update — it replaces the current pod spec with the previous revision's spec using the same rolling update strategy. The rollback completes as quickly as a forward deployment of the same image.

**Q4. What is the difference between a NodePort service and a LoadBalancer service?**
> A NodePort opens a specific port (30000–32767) on every node in the cluster — traffic to `<any-node-ip>:<nodeport>` reaches the service. It works without any external infrastructure but requires clients to know a node IP, exposes the port on all nodes (even if no pod runs there), and requires a separate load balancer if you want a stable single endpoint. A LoadBalancer service provisions an external cloud load balancer (Azure Load Balancer, AWS ELB, GCP LB) automatically — clients get a stable, cloud-managed IP that distributes traffic to healthy nodes. LoadBalancer implicitly includes a NodePort and ClusterIP. In cloud environments, LoadBalancer is always preferred for externally-accessible services; NodePort is for development, on-premises, or when you control your own external load balancer.

**Q5. If `kubectl rollout status` hangs indefinitely after `kubectl set image`, what would you check?**
> First: `kubectl get pods -l app=nginx` to see pod states — look for `ImagePullBackOff` (wrong image tag, private registry auth issue), `CrashLoopBackOff` (new image starts but crashes), or `Pending` (insufficient cluster resources). Second: `kubectl describe pod <failing-pod-name>` for detailed events — this shows the exact error (e.g. `Back-off pulling image "nginx:latest"`, `OOMKilled`, health check failure). Third: `kubectl rollout history deployment/nginx-deployment` to confirm the update triggered. Fourth: check resource quotas with `kubectl describe resourcequota`. Fifth: if the update is stuck and you need to restore service, `kubectl rollout undo deployment/nginx-deployment` immediately reverts to the previous working image while you investigate.

---

## 📚 Resources

- [kubectl patch](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_patch/)
- [kubectl scale](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_scale/)
- [kubectl set image](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_set/kubectl_set_image/)
- [Rolling Updates](https://kubernetes.io/docs/tutorials/kubernetes-basics/update/update-intro/)
- [NodePort Services](https://kubernetes.io/docs/concepts/services-networking/service/#type-nodeport)

---

*Part of my [#100DaysOfCloud](https://github.com/venkatesh-gangavarapu/100-Days-Of-Cloud-Challenge-Azure) challenge.*
*[LinkedIn](https://www.linkedin.com/in/venkatesh-gangavarapu)*
