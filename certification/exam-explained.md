# 🎓 Kubernetes Certification Exam — All 10 Questions Explained Simply

> Earned by: Venkatesh Gangavarapu | KodeKloud Kubernetes Challenge

---

## How to Read This Document

Every question has three parts:
- 🧒 **Simple Explanation** — imagine you are 6 years old
- 🔧 **What We Did** — the actual commands
- ✅ **Why It Worked** — the concept behind it

---

## Question 1 — Create a Pod

**Task:** Create a pod named `pod-httpd-t1q1` using image `httpd:latest`, label `app=httpd_app_t1q1`, container name `httpd-container-t1q1`.

---

### 🧒 Simple Explanation

Imagine Kubernetes is a **big toy box**. A **Pod** is like a small box inside the big box that holds one toy (your app). We needed to put a specific toy called `httpd` into a box, give the box a name tag (`pod-httpd-t1q1`), and also give the toy inside its own name (`httpd-container-t1q1`).

The tricky part: the tool we use (`kubectl run`) always names the toy the same as the box. We had to trick it — first ask it to write down what it *would* do (dry-run), then cross out the toy's name and write the correct one.

---

### 🔧 What We Did

```bash
# Step 1: Generate the blueprint without creating anything yet
kubectl run pod-httpd-t1q1 \
  --image=httpd:latest \
  --labels="app=httpd_app_t1q1" \
  --dry-run=client -o yaml > pod-httpd-t1q1.yaml

# Step 2: Fix the container name in the blueprint
sed -i 's/    name: pod-httpd-t1q1/    name: httpd-container-t1q1/' pod-httpd-t1q1.yaml

# Step 3: Create the pod from the fixed blueprint
kubectl apply -f pod-httpd-t1q1.yaml
```

---

### ✅ Why It Worked

`kubectl run` is a shortcut tool — fast but limited. It cannot set a custom container name. It always uses the pod name as the container name.

The `--dry-run=client -o yaml` flag says: *"Show me what you would create, but don't actually create it."* We redirect that output to a file, fix the one wrong field (`name`), and then apply the corrected file.

The `sed` command finds `name: pod-httpd-t1q1` at exactly 4 spaces of indentation (the container entry) and replaces it. The pod's own name at 2 spaces is untouched.

**Key lesson:** `kubectl run` names the container after the pod. When the task requires a different container name — use dry-run + sed.

---

## Question 2 — Init Containers

**Task:** Create a pod `red-devops-t1q5` with an init container `red-init-devops-t1q5` (ubuntu:latest, `echo "Welcome!"`) and a main container `red-main-devops-t1q5` (ubuntu:latest, `sleep 1000`).

---

### 🧒 Simple Explanation

Imagine you are going to a party (the main container). But before you can go in, a helper (the init container) needs to set up the decorations first.

The **init container** runs first, finishes its job, and then leaves. Only after the helper is done does the main party (the main container) start. If the helper fails, the party never starts.

In our case:
- Helper's job: print "Welcome!" and leave
- Party: sleep for 1000 seconds (stay running)

---

### 🔧 What We Did

```yaml
# Written directly as YAML — no imperative shortcut for init containers
apiVersion: v1
kind: Pod
metadata:
  name: red-devops-t1q5
spec:
  initContainers:           # ← runs FIRST, must complete before main starts
    - name: red-init-devops-t1q5
      image: ubuntu:latest
      command:
        - /bin/bash
        - -c
        - echo "Welcome!"
  containers:               # ← runs AFTER init container completes
    - name: red-main-devops-t1q5
      image: ubuntu:latest
      command:
        - /bin/bash
        - -c
        - sleep 1000
```

```bash
kubectl apply -f red-devops-t1q5.yaml
```

---

### ✅ Why It Worked

Init containers are defined under `spec.initContainers` — completely separate from `spec.containers`. Kubernetes runs them in order before any main container starts.

There is no `kubectl run` or imperative shortcut for init containers — you must write the YAML.

The pod lifecycle:
1. Init container starts → prints "Welcome!" → exits with code 0 (success)
2. Main container starts → runs `sleep 1000` → stays Running

**Key lesson:** Init containers run setup tasks before the main app. Use them for: waiting for a database, downloading configs, running migrations.

---

## Question 3 — Scale a Deployment

**Task:** Change `blue-app-t2q5` replicas from 1 to 3.

---

### 🧒 Simple Explanation

Imagine you have one lemonade stand (1 replica). It's so popular that the line is too long! So you open **two more identical stands** next to it (3 replicas total). Now three stands serve customers at the same time — less waiting, more happy customers.

**Scaling up** in Kubernetes means making more identical copies of your app so more people can use it at the same time.

---

### 🔧 What We Did

```bash
kubectl scale deployment blue-app-t2q5 --replicas=3 -n default
```

One command. Done.

---

### ✅ Why It Worked

`kubectl scale` is purpose-built for changing replica counts. It updates `spec.replicas` in the Deployment — the ReplicaSet notices it needs 2 more pods and creates them immediately.

**Important:** `kubectl scale` does NOT change the container image or trigger a rolling update. It only changes the count. Existing pods keep running unchanged.

The Deployment controller sees:
- Desired: 3
- Current: 1
- Action: create 2 more pods with the same spec

**Key lesson:** Scale up before high-traffic events. Scale down afterward to save resources. `kubectl scale` is the fastest way to do both.

---

## Question 4 — Rollback a Deployment

**Task:** Roll back `nginx-deployment-t2q2` to the previous revision after a buggy release.

---

### 🧒 Simple Explanation

Imagine you painted your bedroom wall blue and you loved it. Then one day you painted over it with purple — but the purple looked terrible. What do you do?

You get the old blue paint and paint it back!

In Kubernetes, when a new version of the app has a bug, we **rollback** — go back to the previous working version. Kubernetes keeps the old version stored (like keeping the old paint) just for this reason.

---

### 🔧 What We Did

```bash
# Check what versions are available
kubectl rollout history deployment/nginx-deployment-t2q2 -n default

# Go back one version
kubectl rollout undo deployment/nginx-deployment-t2q2 -n default

# Wait until the rollback completes
kubectl rollout status deployment/nginx-deployment-t2q2 -n default
```

---

### ✅ Why It Worked

Every time you update a Deployment's image, Kubernetes creates a new **ReplicaSet** (a snapshot of that version). The old ReplicaSet is kept at 0 replicas — not deleted. This is the rollback safety net.

`kubectl rollout undo` simply:
1. Scales the previous ReplicaSet back up
2. Scales the current (buggy) ReplicaSet back down

No image re-pull needed — the old image is still cached on the nodes.

After rollback, revision numbering shifts — the restored version becomes the new highest revision number.

**Key lesson:** Always keep `revisionHistoryLimit` above 0 (default is 10). Setting it to 0 deletes old ReplicaSets and makes rollback impossible.

---

## Question 5 — Create a Job

**Task:** Create job `countdown-devops-t3q2` with template name `countdown-devops-t3q2`, container `container-countdown-devops-t3q2`, image `ubuntu:latest`, command `sleep 5`, restart policy `Never`.

---

### 🧒 Simple Explanation

A **Job** in Kubernetes is like a chore — it has a beginning and an end. It is NOT like a lemonade stand that stays open forever. It is like washing dishes: you do it, you finish, you stop.

Our job runs `sleep 5` — it waits 5 seconds and then finishes. Once it finishes successfully, Kubernetes marks it "Complete" and does not restart it.

The tricky part: the task required a special name on the **template** inside the job. The normal shortcut (`kubectl create job`) forgets to write that name. So we wrote the full YAML ourselves.

---

### 🔧 What We Did

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: countdown-devops-t3q2
spec:
  backoffLimit: 6
  template:
    metadata:
      name: countdown-devops-t3q2      # ← this field kubectl create job skips
    spec:
      restartPolicy: Never
      containers:
        - name: container-countdown-devops-t3q2
          image: ubuntu:latest
          command:
            - sleep
            - "5"
```

```bash
kubectl apply -f countdown-devops-t3q2.yaml
kubectl wait job/countdown-devops-t3q2 --for=condition=Complete --timeout=60s
```

---

### ✅ Why It Worked

`restartPolicy: Never` means: if the container exits with an error, don't restart it inside the same pod. Instead, create a brand new pod for the retry (up to `backoffLimit` times). Each failed attempt creates a separate pod — useful for debugging because logs from each attempt are preserved.

`restartPolicy: OnFailure` would restart in the same pod (logs overwritten).
`restartPolicy: Always` is rejected for Jobs — it makes no sense for a task that should finish.

`apiVersion: batch/v1` — Jobs are in the `batch` group, not `apps` or core `v1`.

**Key lesson:** Jobs are for one-time tasks. CronJobs (Q6) are for repeated scheduled tasks. A CronJob creates a new Job each time it fires.

---

## Question 6 — Create a CronJob

**Task:** Create cronjob `devops-t3q1`, schedule `*/12 * * * *`, container `cron-devops-t3q1`, image `httpd:latest`, command `echo Welcome to xfusioncorp!`, restart policy `OnFailure`.

---

### 🧒 Simple Explanation

A **CronJob** is like setting an alarm clock that does a chore automatically every time it goes off.

Imagine you set an alarm every 12 minutes and when it rings, a robot goes and stamps a piece of paper. That stamp is the `echo` command — printing "Welcome to xfusioncorp!" The robot does this automatically, forever, every 12 minutes.

The tricky part: the shortcut tool (`kubectl create cronjob`) always gives the container the same name as the cronjob. We used a trick to fix just that one name.

---

### 🔧 What We Did

```bash
# Generate blueprint via dry-run
kubectl create cronjob devops-t3q1 \
  --image=httpd:latest \
  --schedule="*/12 * * * *" \
  --restart=OnFailure \
  --dry-run=client -o yaml \
  -- echo "Welcome to xfusioncorp!" > devops-t3q1.yaml

# Fix container name using range-restricted sed
# The range /- command:/,/restartPolicy:/ targets only the container block
sed -i '/- command:/,/restartPolicy:/ s/name: devops-t3q1/name: cron-devops-t3q1/' devops-t3q1.yaml

kubectl apply -f devops-t3q1.yaml
```

---

### ✅ Why It Worked

**Cron schedule `*/12 * * * *`** means: every 12th minute of every hour, every day.

```
┌───────── minute (*/12 = every 12 minutes)
│ ┌─────── hour (* = every hour)
│ │ ┌───── day of month (* = every day)
│ │ │ ┌─── month (* = every month)
│ │ │ │ ┌─ day of week (* = every day)
*/12 * * * *
```

The **range-restricted sed** `/- command:/,/restartPolicy:/` only replaces text between those two markers — safely patching the container name without touching the CronJob's own `metadata.name`.

`restartPolicy: OnFailure` = correct for batch/cron jobs. `Always` is rejected.

**Key lesson:** CronJob → creates Job on schedule → Job creates Pod → Pod runs command. Three layers, each with its own lifecycle.

---

## Question 7 — Fix a Broken Service (Selector Typo)

**Task:** `orange-app-deployment-t4q6` inaccessible. Pod Running but website down.

---

### 🧒 Simple Explanation

Imagine a post office (the Service) that delivers letters to a house. The house has a name plate saying **"ORANGE house"**. But someone typed the post office address book wrong — they wrote **"ORAGE house"** (missing the N).

The postman looks for "ORAGE house", can't find it, and the letters (traffic) never arrive. But the house is perfectly fine — the family is home!

The fix: correct the spelling in the address book.

---

### 🔧 What We Did

The diagnosis showed:
```
Service selector:  app: orage-app-t4q6   ← typo (missing 'n')
Pod label:         app: orange-app-t4q6  ← correct
Endpoints:         <none>                ← selector matched nothing
```

```bash
kubectl patch service orange-app-service-t4q6 -n default \
  --type='json' \
  -p='[{"op":"replace","path":"/spec/selector/app","value":"orange-app-t4q6"}]'
```

---

### ✅ Why It Worked

A Kubernetes **Service** finds its target pods using **label selectors** — it looks for pods that carry specific labels. If there is even a one-character typo, the selector matches nothing. The Service exists but routes traffic nowhere — Endpoints list shows `<none>`.

The pod was Running and healthy the entire time. The bug was purely in the Service's selector.

`kubectl patch --type=json` uses RFC 6902 JSON Patch — the most surgical update. It changes exactly one field (`/spec/selector/app`) without touching anything else.

**Key lesson:** Always check `kubectl get endpoints <service>` when a website is down but pods look healthy. Empty endpoints = selector mismatch. The pod and Service are talking different languages.

---

## Question 8 — Fix Nginx + PHP-FPM + Copy File

**Task:** Fix `nginx-phpfpm-t4q3` and `nginx-config-t4q3`, then copy `/home/thor/index.php` to `/var/www/html` in nginx-container.

---

### 🧒 Simple Explanation

Imagine a kitchen with two chefs:
- **Chef nginx** serves the food to customers (port 80)
- **Chef PHP-FPM** cooks the PHP recipes

They share a fridge (the emptyDir volume). But:
- nginx thinks the fridge is in the **living room** (`/var/www/html`)
- PHP-FPM thinks the fridge is in the **kitchen** (`/usr/share/nginx/html`)

And to make it worse, nginx was shouting orders from the **wrong room** (port 8099 instead of port 80).

The recipe book (ConfigMap) had three wrong instructions, and the restaurant's front door (Service) was sending customers to the wrong entrance too.

---

### 🔧 What We Did

Four bugs found and fixed:

| Bug | Location | Problem | Fix |
|-----|----------|---------|-----|
| 1 | ConfigMap | `listen 8099` | `listen 80` |
| 2 | ConfigMap | `SCRIPT_FILENAME $document_root` (nginx's path) | `/usr/share/nginx/html` (PHP-FPM's path) |
| 3 | Service | `port: 8099` | `port: 80` |
| 4 | Service | `targetPort: 8099` | `targetPort: 80` |

```bash
# Fix Service immediately (no restart needed)
kubectl patch service nginx-service-t4q3 -n default \
  --type='json' \
  -p='[
    {"op":"replace","path":"/spec/ports/0/port","value":80},
    {"op":"replace","path":"/spec/ports/0/targetPort","value":80}
  ]'

# Export pod (bare pod — no auto-recreate)
kubectl get pod nginx-phpfpm-t4q3 -n default -o yaml > backup.yaml

# Fix ConfigMap
kubectl edit configmap nginx-config-t4q3 -n default
# Changed: listen 8099 → 80
# Changed: SCRIPT_FILENAME $document_root → /usr/share/nginx/html

# Restart pod (subPath mount = changes never propagate live)
kubectl delete pod nginx-phpfpm-t4q3 -n default
kubectl apply -f backup.yaml
kubectl wait pod/nginx-phpfpm-t4q3 --for=condition=Ready --timeout=90s -n default

# Copy PHP file
kubectl cp /home/thor/index.php \
  nginx-phpfpm-t4q3:/var/www/html/index.php \
  -c nginx-container -n default
```

---

### ✅ Why It Worked

**The volume mismatch:** Both containers share the same emptyDir but mount it at different paths. `$document_root` expands to nginx's path — useless for PHP-FPM which only knows its own path. Hardcoding PHP-FPM's path in `SCRIPT_FILENAME` fixes this.

**SubPath mount:** When nginx.conf is mounted as a file (not a directory), Kubernetes never updates it after the pod starts. The pod must be deleted and recreated to pick up ConfigMap changes.

**Bare pod:** No `Controlled By:` in describe = no controller = no auto-recreate. Export before deleting.

**kubectl cp:** Copies the file into nginx-container's document root. Because both containers share the same emptyDir, the file also appears in PHP-FPM's path simultaneously.

**Key lesson:** When `curl localhost` from inside the pod works but the website button fails — the Service is always the broken link. Test both paths after every fix.

---

## Question 9 — Add Label to Service Selector

**Task:** Add `component: front-end-t5q5` to the **selector** of `service-t5q5`.

---

### 🧒 Simple Explanation

The Service is like a teacher calling students by name. The **selector** is the list of names the teacher calls. If a student (pod) wants to be called, they need to raise their hand with the right name tag.

We needed to add a **new name** (`component: front-end-t5q5`) to the teacher's call list. Now only pods with that name tag get included.

---

### 🔧 What We Did

```bash
# Add to spec.selector (not metadata.labels)
kubectl patch service service-t5q5 -n default \
  --type='merge' \
  -p='{"spec":{"selector":{"component":"front-end-t5q5"}}}'
```

---

### ✅ Why It Worked

The Service **selector** (`spec.selector`) is the mechanism that connects the Service to pods. Adding a new key-value pair here means the Service now requires pods to have BOTH the existing labels AND the new `component: front-end-t5q5` label.

This is different from Question 10 — here we changed `spec.selector` (who gets traffic), not `metadata.labels` (how others identify the Service itself).

**Key lesson:**
- `spec.selector` = which pods receive traffic from this Service
- `metadata.labels` = how this Service is identified by other Kubernetes objects

These are two completely different locations with completely different purposes.

---

## Question 10 — Add Label to Service Metadata

**Task:** Add `component: front-end-t5q6` as a **metadata label** on `service-t5q6`.

---

### 🧒 Simple Explanation

Every object in Kubernetes has a **name tag** on the outside (metadata labels) and an **internal filter** (selector). Question 9 changed the internal filter. This question changes the name tag.

Think of it like a library book:
- The **name tag** on the cover (metadata labels) helps the librarian find and organise the book
- The **topic** inside (selector) determines what stories it tells

We needed to add a new category sticker on the cover: `component: front-end-t5q6`.

---

### 🔧 What We Did

```bash
# Add to metadata.labels (not spec.selector)
kubectl patch service service-t5q6 -n default \
  --type='merge' \
  -p='{"metadata":{"labels":{"component":"front-end-t5q6"}}}'
```

---

### ✅ Why It Worked

`metadata.labels` on a Service are used by:
- Other Kubernetes objects to find or select this Service
- `kubectl get service -l component=front-end-t5q6` (filtering by label)
- NetworkPolicies, monitoring tools, and GitOps systems

They do NOT affect which pods receive traffic — that is `spec.selector`'s job.

The `--type=merge` patch merges the new label into the existing labels without overwriting them.

**Key lesson:** The Q9 vs Q10 distinction is a classic exam trap. Always read carefully:
- "Add label **to** the service" = `metadata.labels`
- "Add label **selector** to the service" = `spec.selector`

---

## 🏆 Complete Summary — All 10 Questions

| Q | Concept | The Simple Version | Key Command |
|---|---------|-------------------|-------------|
| 1 | Create Pod | Put a toy in a box with a specific name | `kubectl run --dry-run -o yaml` + `sed` |
| 2 | Init Container | Helper sets up before the party starts | YAML only — write `initContainers:` |
| 3 | Scale Deployment | Open more lemonade stands | `kubectl scale --replicas=3` |
| 4 | Rollback | Go back to the old blue paint | `kubectl rollout undo` |
| 5 | Job | A chore with a beginning and an end | YAML only — `batch/v1`, `restartPolicy: Never` |
| 6 | CronJob | Alarm clock that runs a chore automatically | `kubectl create cronjob --dry-run` + `sed` |
| 7 | Fix Service selector | Fix the spelling in the address book | `kubectl patch spec.selector` |
| 8 | Nginx+PHP-FPM | Two chefs sharing a fridge — paths must align | ConfigMap + Service patch + `kubectl cp` |
| 9 | Service selector label | Add a name to teacher's call list | `kubectl patch spec.selector` |
| 10 | Service metadata label | Add a sticker to the book cover | `kubectl patch metadata.labels` |

---

## 🎯 The Biggest Lessons from All 10

**1. Read before fixing** — `kubectl describe` and `kubectl get -o yaml` always before touching anything.

**2. kubectl run can't set container names** — always dry-run + sed.

**3. Some things have no imperative shortcut** — init containers, ReplicaSets: YAML only.

**4. Test both paths after a Service fix** — inside pod (`curl localhost`) AND via NodePort.

**5. Empty Endpoints = selector mismatch** — the most common "website down but pod healthy" cause.

**6. SubPath ConfigMap mount = restart required** — `path=` in describe output is the signal.

**7. Bare pod = no auto-recreate** — export before delete, always.

**8. `metadata.labels` vs `spec.selector`** — two completely different things on the same object.
