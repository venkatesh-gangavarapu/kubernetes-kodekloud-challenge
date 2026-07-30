# Day 04 — Resource Requests and Limits

> #KodeKloud Kubernetes Challenge | Day 4 of 30

---

## 📌 The Task

| Requirement       | Value              |
|-------------------|--------------------|
| Pod name          | `httpd-pod`        |
| Container name    | `httpd-container`  |
| Image             | `httpd:latest`     |
| Memory request    | `15Mi`             |
| CPU request       | `100m`             |
| Memory limit      | `20Mi`             |
| CPU limit         | `100m`             |
| Namespace         | `default`          |

---

## 🧠 Core Concepts

### Why Resource Management Exists

The performance issues that motivated this task are a classic Kubernetes operational problem. On a shared cluster, one runaway process can consume all available memory on a node — triggering the Linux OOM (Out of Memory) killer across every Pod on that node, not just the offending one. Without resource boundaries, a single misconfigured application affects every other workload that shares the node.

Resource requests and limits are Kubernetes' answer: a contract between the workload and the cluster about how much compute it expects to use and how much it is allowed to use.

### Requests vs Limits — The Core Distinction

These two concepts are frequently confused but serve completely different purposes:

**Requests** answer: *"How much resource does this container need to function?"*
- Used exclusively by the **scheduler** to decide which node to place the Pod on
- The scheduler finds a node where available (allocatable minus already-requested) CPU and memory is ≥ the Pod's total requests
- The container is **not** restricted to its request — it can use more if the node has headroom
- A node can be overcommitted: total requests across all Pods can exceed node capacity, as long as actual usage stays below capacity

**Limits** answer: *"How much resource is this container allowed to consume at maximum?"*
- Enforced by the **container runtime** (via Linux cgroups), not the scheduler
- CPU limit: enforced by CPU throttling — the process is slowed down if it tries to use more
- Memory limit: enforced by OOMKill — the container is killed immediately if it exceeds the limit
- This is the hard ceiling, regardless of available node capacity

```
Node (4 CPU, 8Gi RAM)
├── Pod A: request=1CPU/1Gi   limit=2CPU/2Gi   → scheduler allocates based on 1CPU/1Gi
├── Pod B: request=1CPU/1Gi   limit=2CPU/2Gi   → scheduler allocates based on 1CPU/1Gi
└── Remaining for scheduler: 2CPU/6Gi (but actual usage could peak to 4CPU/4Gi combined)
```

### CPU Units — Millicores

CPU resources are measured in **millicores** (m). The relationship:

| Value | Meaning |
|-------|---------|
| `1000m` | 1 full CPU core |
| `500m` | Half a CPU core |
| `100m` | One-tenth of a CPU core (this task) |
| `1` | 1 full CPU core (equivalent to 1000m) |

`100m` means the container requests one-tenth of a CPU core. On a 4-core node, that is 4% of total compute. If the container hits the CPU limit, the runtime throttles it — it continues running but slows down. **CPU limit exceeded ≠ container death.** It just runs slower.

### Memory Units — Mi vs M

Memory has two unit systems that look similar but differ by about 5%:

| Unit | Name | Value |
|------|------|-------|
| `Mi` | Mebibytes | 1,048,576 bytes (1024 × 1024) |
| `M` | Megabytes | 1,000,000 bytes (1000 × 1000) |
| `Gi` | Gibibytes | 1,073,741,824 bytes |
| `G` | Gigabytes | 1,000,000,000 bytes |

Kubernetes uses binary units (Mi, Gi) internally. `15Mi` ≈ 15.7 MB. The distinction matters in tight memory environments — always use `Mi`/`Gi` to match what Kubernetes reports, preventing unit-mismatch surprises when comparing `kubectl top` output to your configured limits.

**Memory limit exceeded = OOMKill = immediate container death.** Unlike CPU throttling, there is no graceful slowdown. The kernel kills the process instantly and Kubernetes restarts the container (subject to the Pod's `restartPolicy`). A container that repeatedly OOMKills will show increasing `RESTARTS` in `kubectl get pods`.

### QoS Classes — What This Task Creates

Kubernetes assigns every Pod a **Quality of Service (QoS) class** based on its resource configuration. This class determines eviction priority when a node is under memory pressure:

| QoS Class | Condition | Eviction Priority |
|-----------|-----------|-------------------|
| `Guaranteed` | Every container has requests == limits for both CPU and memory | Last to be evicted |
| `Burstable` | At least one container has requests ≠ limits, or only limits set | Middle priority |
| `BestEffort` | No requests or limits set on any container | First to be evicted |

**This task creates a Burstable Pod.** The memory request (15Mi) does not equal the memory limit (20Mi). Even though CPU request == CPU limit (both 100m), one mismatch is enough to classify the whole Pod as Burstable.

A Guaranteed Pod would require both CPU and memory requests equal to their respective limits for every container. That would look like:
```yaml
requests:
  memory: "20Mi"
  cpu: "100m"
limits:
  memory: "20Mi"
  cpu: "100m"
```

In production, Guaranteed is the right class for latency-sensitive workloads. Burstable is appropriate for applications with variable load that can absorb occasional throttling.

---

## 🔧 Step-by-Step Solution

### Method 1 — kubectl Imperative + dry-run (Exam Technique)

`kubectl run` supports `--requests` and `--limits` flags. Combined with the Day 01 lesson — use `--dry-run=client -o yaml` and patch the container name — this is the fastest complete approach.

**Step 1 — Verify cluster access**
```bash
kubectl get nodes
```

**Step 2 — Generate the Pod manifest with resources via dry-run**
```bash
kubectl run httpd-pod \
  --image=httpd:latest \
  --requests='memory=15Mi,cpu=100m' \
  --limits='memory=20Mi,cpu=100m' \
  --dry-run=client -o yaml > httpd-pod.yaml
```

**Step 3 — Patch the container name**

In the generated YAML, `metadata.name` (pod name) sits at 2-space indentation, and `containers[].name` (container name) sits at 4-space indentation. Target the 4-space entry to avoid renaming the Pod:
```bash
sed -i 's/    name: httpd-pod/    name: httpd-container/' httpd-pod.yaml
```

Verify both names are correct:
```bash
cat httpd-pod.yaml
```

**Step 4 — Apply the manifest**
```bash
kubectl apply -f httpd-pod.yaml
```

**Step 5 — Verify**
```bash
kubectl get pod httpd-pod -n default
kubectl get pod httpd-pod -n default -o jsonpath='{.spec.containers[0].name}'
kubectl get pod httpd-pod -n default -o jsonpath='{.spec.containers[0].resources}'
```

---

### Method 2 — YAML Manifest (Declarative — Production Grade)

```yaml
# httpd-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: httpd-pod
  namespace: default
  labels:
    app: httpd
spec:
  containers:
    - name: httpd-container       # explicit container name — cannot be set by kubectl run alone
      image: httpd:latest
      ports:
        - containerPort: 80
      resources:
        requests:
          memory: "15Mi"          # scheduler uses this to choose a node
          cpu: "100m"             # 1/10th of a CPU core
        limits:
          memory: "20Mi"          # OOMKill triggered if exceeded
          cpu: "100m"             # throttled (not killed) if exceeded
```

**Step 1 — Apply the manifest**
```bash
kubectl apply -f httpd-pod.yaml
```

**Step 2 — Wait for Ready**
```bash
kubectl wait pod/httpd-pod --for=condition=Ready --timeout=60s -n default
```

**Step 3 — Verify Pod status**
```bash
kubectl get pod httpd-pod -n default
```
Expected:
```
NAME        READY   STATUS    RESTARTS   AGE
httpd-pod   1/1     Running   0          20s
```

**Step 4 — Verify container name**
```bash
kubectl get pod httpd-pod -n default \
  -o jsonpath='{.spec.containers[0].name}'
```
Expected: `httpd-container`

**Step 5 — Verify resource requests and limits**
```bash
kubectl get pod httpd-pod -n default \
  -o jsonpath='{.spec.containers[0].resources}'
```
Expected:
```json
{"limits":{"cpu":"100m","memory":"20Mi"},"requests":{"cpu":"100m","memory":"15Mi"}}
```

**Step 6 — Verify QoS class**
```bash
kubectl get pod httpd-pod -n default \
  -o jsonpath='{.status.qosClass}'
```
Expected: `Burstable`

**Step 7 — Full describe**
```bash
kubectl describe pod httpd-pod -n default
```
Look for the `QoS Class` and `Limits`/`Requests` fields in the describe output.

---

## 💻 Commands Reference

```bash
# Cluster check
kubectl get nodes

# Method 1 — Imperative dry-run + patch
kubectl run httpd-pod \
  --image=httpd:latest \
  --requests='memory=15Mi,cpu=100m' \
  --limits='memory=20Mi,cpu=100m' \
  --dry-run=client -o yaml > httpd-pod.yaml
sed -i 's/    name: httpd-pod/    name: httpd-container/' httpd-pod.yaml
kubectl apply -f httpd-pod.yaml

# Method 2 — Declarative apply
kubectl apply -f httpd-pod.yaml

# Verification
kubectl get pod httpd-pod -n default
kubectl get pod httpd-pod -n default -o wide
kubectl get pod httpd-pod -n default \
  -o jsonpath='{.spec.containers[0].name}'
kubectl get pod httpd-pod -n default \
  -o jsonpath='{.spec.containers[0].resources}'
kubectl get pod httpd-pod -n default \
  -o jsonpath='{.status.qosClass}'
kubectl describe pod httpd-pod -n default

# Logs
kubectl logs httpd-pod -n default -c httpd-container

# Cleanup (run manually when done)
# kubectl delete pod httpd-pod -n default
# rm -f httpd-pod.yaml
```

---

## ⚠️ Common Mistakes

1. **Container name not set — same failure as Day 01**
   `kubectl run` names the container after the Pod (`httpd-pod`). The task requires `httpd-container`. The fix is the same `--dry-run=client -o yaml` + `sed` pattern from Day 01. The sed target must be the 4-space-indented container name entry, not the 2-space-indented pod metadata name.

2. **Setting limits lower than requests**
   `requests.memory: 20Mi` with `limits.memory: 15Mi` is invalid — Kubernetes rejects it at admission with a validation error. The limit must always be ≥ the request. Requests are the floor, limits are the ceiling.

3. **Using `M` instead of `Mi` for memory**
   `15M` (megabytes) and `15Mi` (mebibytes) are different values. Kubernetes accepts both but stores and reports in mebibytes. Using `M` when the task specifies `Mi` is a literal spec mismatch — the validator checks the stored value, not what you intended.

4. **Using `100M` instead of `100m` for CPU**
   CPU unit `m` is lowercase — it means millicores. `100M` would mean 100 megacores, which is nonsensical and will be rejected. Always lowercase `m` for CPU millicores.

5. **Expecting OOMKill to behave like CPU throttling**
   Engineers sometimes set memory limits aggressively thinking "it'll just slow down." It won't — it kills. When a container hits its memory limit, the kernel issues SIGKILL immediately. The container restarts, loses all in-memory state, and the RESTARTS counter in `kubectl get pods` increments. In a stateful application, repeated OOMKills are a data-integrity risk.

6. **Not checking the QoS class**
   The QoS class determines eviction order under node memory pressure. A Pod you think is Guaranteed may actually be Burstable because one container has mismatched requests/limits. Always verify with `-o jsonpath='{.status.qosClass}'` after creation. A misconfigured QoS class means your "critical" workload gets evicted before it should be.

7. **Forgetting that requests affect scheduling, not runtime**
   Setting `requests.memory: 15Mi` does not prevent the container from using 19Mi at runtime (up to the limit). It only tells the scheduler "reserve 15Mi of node capacity for this Pod." A node reported as 90% memory-utilized by Kubernetes is actually 90% of *requested* memory, not necessarily 90% of *used* memory — these can differ significantly on underutilized clusters.

---

## 🌍 Real-World Context

The performance issues that triggered this task are a production reality. Without resource limits, a single application memory leak can trigger a cascading node-level OOMKill storm, taking down every Pod on the node — including unrelated workloads. This is sometimes called the "noisy neighbour" problem.

In mature production environments, resource configuration is enforced through multiple layers:

**LimitRange** — a namespace-level object that sets default requests and limits for any Pod that doesn't specify them. Without a LimitRange, unspecified resources default to BestEffort (no limits), meaning any Pod on the node is fair game for eviction first.

**ResourceQuota** — limits the total CPU and memory that all Pods in a namespace can request collectively. Prevents one team's namespace from consuming the entire cluster.

**Vertical Pod Autoscaler (VPA)** — observes actual resource usage over time and recommends (or automatically adjusts) requests and limits. Useful for right-sizing Pods that were configured with guesswork.

**Horizontal Pod Autoscaler (HPA)** — scales replica count based on CPU/memory utilization relative to the requests. Without accurate requests, HPA scaling decisions are unreliable.

The values in this task (15Mi memory request, 20Mi limit) are extremely tight — deliberately so for lab constraints. In production, httpd would typically run with at least 64Mi–128Mi memory depending on configuration and traffic. The principle is the same at any scale: request what you need, limit to what you'll allow.

---

## ❓ Interview Q&A

**Q1: What is the difference between a resource request and a resource limit in Kubernetes?**
A request is the amount of resource the scheduler reserves on a node for the container — it guarantees the container has that much available. A limit is the maximum the container is allowed to consume, enforced by the container runtime via Linux cgroups. The scheduler places Pods based on requests, not limits. A container can use between its request and its limit if the node has spare capacity, but cannot exceed its limit.

**Q2: What happens when a container exceeds its memory limit vs its CPU limit?**
Different behaviors entirely. CPU limit: the container runtime throttles the process — it continues running but more slowly, capped at the allocated CPU share. Memory limit: the Linux kernel issues SIGKILL immediately via OOMKill — the container dies instantly and Kubernetes restarts it according to the `restartPolicy`. There is no gradual slowdown for memory — it is a hard kill.

**Q3: What are QoS classes and how does Kubernetes assign them?**
Kubernetes assigns one of three QoS classes to every Pod based on its resource configuration. Guaranteed: every container has requests equal to limits for both CPU and memory — highest eviction protection. Burstable: at least one container has requests not equal to limits — middle priority. BestEffort: no requests or limits on any container — evicted first under memory pressure. The class is auto-assigned at creation and visible under `status.qosClass`.

**Q4: What QoS class does this Pod get and why?**
Burstable. The CPU request and limit are both 100m (equal), but the memory request (15Mi) does not equal the memory limit (20Mi). One mismatch across any resource in any container is enough to make the whole Pod Burstable rather than Guaranteed. To achieve Guaranteed, requests and limits would both need to be 20Mi for memory and 100m for CPU.

**Q5: How does a LimitRange complement resource requests and limits?**
A LimitRange is a namespace-level policy object that sets default requests and limits for Pods that don't specify them, and enforces minimum/maximum bounds. Without it, any Pod deployed without explicit resources is BestEffort — the first evicted under pressure. A LimitRange turns "no resources specified" into "sensible defaults applied automatically," protecting the node from unguarded workloads.

**Q6: Why might `kubectl top nodes` show 30% memory utilization while `kubectl describe node` shows 90% memory requested?**
Because `kubectl top` shows actual current usage, while `kubectl describe node` shows how much of node capacity has been *requested* (reserved by the scheduler). A cluster can be over-requested but under-utilized — many Pods have reserved 100Mi each but are actually using 20Mi. The scheduler refuses to place new Pods even though real memory is available, because it works from requests, not actuals. This is a common cause of "cluster is full" when nodes appear idle.

**Q7: What is CPU throttling and when does it occur?**
CPU throttling is enforced by the Linux CFS (Completely Fair Scheduler) when a container tries to use more CPU than its limit allows. The container's processes are paused periodically to keep their aggregate usage within the cgroup limit. Throttling shows up in `container_cpu_throttled_seconds_total` in Prometheus metrics — a good alert to watch in production. Unlike OOMKill, the application continues running; it just responds more slowly.

---

## 📚 Resources

- [Kubernetes Docs — Resource Management for Pods and Containers](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
- [Kubernetes Docs — Configure Quality of Service for Pods](https://kubernetes.io/docs/tasks/configure-pod-container/quality-service-pod/)
- [Kubernetes Docs — LimitRange](https://kubernetes.io/docs/concepts/policy/limit-range/)
- [Kubernetes Docs — Resource Quotas](https://kubernetes.io/docs/concepts/policy/resource-quotas/)
- **Related days:** [Day 01](../day-01/README.md) — Pod fundamentals and container naming | [Day 03](../day-03/README.md) — Namespaces (where LimitRanges and ResourceQuotas live)
