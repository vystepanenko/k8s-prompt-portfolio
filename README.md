# Kubernetes prompt portfolio

Prompt engineering examples for **generating and reviewing Kubernetes manifests** with
[kubectl-ai](https://github.com/GoogleCloudPlatform/kubectl-ai) (Google Cloud's AI assistant for
Kubernetes) and Gemini.

The manifests reproduce and review the examples from
[den-vasyliev/go-demo-app/yaml](https://github.com/den-vasyliev/go-demo-app/tree/master/yaml)
(copied unchanged to [`yaml/original/`](yaml/original/)). Every generated (`yaml/<name>.yaml`)
and reviewed (`yaml/<name>.fixed.yaml`) manifest is the unedited output of the prompt in its
table row, validated with [kubeconform](https://github.com/yannh/kubeconform). The Gateway API
file is tool output, see [below](#gateway-api-optional-part).

| | |
|---|---|
| Tool | kubectl-ai 0.0.31 (`--quiet`, one-shot mode) |
| Model | generate: `gemini-3.8-flash`, analyse: `gemini-3.5-flash` (Google AI Studio API key, free tier; see [Notes](#notes)) |
| Validation | `kubeconform -strict -kubernetes-version 1.34.0` |

## Prompt design

The prompts follow the techniques from Google's
[Prompt Engineering whitepaper](https://www.kaggle.com/whitepaper-prompt-engineering):

- **System and role prompting** - one shared system prompt sets the role (senior Kubernetes
  platform engineer), the target version and the output contract for every request.
- **Explicit output format** - exactly one fenced `yaml` block, nothing else, lines of at most
  70 characters, so the result can be extracted mechanically (see [`scripts/kai.sh`](scripts/kai.sh)).
- **Instructions over constraints, specific values over vague wishes** - generate prompts always
  give images and ports, plus probe timings and resource numbers where the manifest has them, so
  the model never invents an image tag.
  Analyse prompts do not, and there the model picks pinned tags itself (`nginx:1.27.4`,
  `redis:7.4.2-alpine`, `glowtools/soccer:4e4254a`) - check that such a tag exists before use.
- **Contextual prompting** - analyse prompts start with a situation ("the pod restarts every
  ~30 seconds", "applying to 1.34 fails") that tells the model what to look for first.
- **One-shot example** - the analysis instructions contain an example of the findings format,
  which the model copies as YAML comments at the top of the fixed manifest.
- **Step-by-step reasoning** - the reviewer is asked to walk through a fixed checklist before
  answering; only the final manifest is returned.
- **Generate and analyse** - every manifest has a *generate* prompt (from a specification) and
  an *analyse* prompt (review the original, return findings + a corrected manifest).

## Shared prompts

<!-- shared:start -->
**System prompt (prepended to every prompt)** - [`prompts/_system.md`](prompts/_system.md):

```text
You are a senior Kubernetes platform engineer who writes production-ready manifests.
Answer from this prompt only: do not call any tool, do not run kubectl or bash, do not inspect or change any cluster.
Target Kubernetes 1.34 and use only stable, non-deprecated apiVersions. Use 2-space indentation.
Keep every line at most 70 characters long; split long comments into several # lines.
Output exactly one fenced code block with the language tag yaml and nothing else: no text before or after it.
```

**Analysis instructions (added to every analyse prompt)** - [`prompts/_analyse.md`](prompts/_analyse.md):

```text
Review the manifest that follows the line "--- MANIFEST ---". Work through it step by step before answering:
apiVersion and kind validity, correctness (ports, probe targets, names, references to objects that do not exist),
reliability, security, resource management. Then return the corrected manifest, keeping the original intent,
names and images unless a finding requires a change. Start the YAML with the findings as comments, in this format:
# Findings (original: <file name>):
# 1. [bug] livenessProbe targets port 9000 but the container listens on 8080 -> probe fails, pod restarts.
# 2. [deprecated] extensions/v1beta1 Deployment was removed in 1.16 -> use apps/v1.
# 3. [best-practice] no resource requests/limits -> scheduler cannot place the pod reliably.
Use the tags [bug], [deprecated], [security], [reliability], [best-practice]. If nothing is broken, say so in finding 1.
List at most 5 findings, most important first. End the YAML with the line: # end of manifest
```
<!-- shared:end -->

## Portfolio

Generate prompts are sent as *system prompt + prompt*. Analyse prompts are sent as
*system prompt + analysis instructions + prompt + the original manifest*.

<!-- table:start -->
| NAME | PROMPT | DESCRIPTION | EXAMPLE |
|---|---|---|---|
| **app** | Create a single Pod manifest for a demo web application.<br>- Pod name: app; labels: app=demo, run=demo.<br>- One container named app, image gcr.io/k8s-k3s/demo:v1.0.0.<br>- It listens on TCP 8000; expose that port with the name http.<br>Do not add anything else: no probes, volumes, resources or extra labels. | Zero-shot generation of a bare Pod. Explicit negative scope ("do not add anything else") keeps the output identical to the specification instead of letting the model "improve" it. | [yaml/app.yaml](yaml/app.yaml) |
| **app-livenessProbe** | Create a Pod manifest that shows an HTTP liveness probe.<br>- Pod name: app-liveness-probe, label app=demo; container app, image gcr.io/smartcity-gl/demo:v1.0.1.<br>- The container listens on TCP 8080, port name http.<br>- Liveness probe: HTTP GET / on the port name http (not a number, so the probe cannot drift from the<br>  container port); initialDelaySeconds 5, timeoutSeconds 1, periodSeconds 10, failureThreshold 3. | HTTP liveness probe. The prompt names the reason for a design choice (probe on the named port so it cannot drift from the container port), which steers the model away from the bug in the original. | [yaml/app-livenessProbe.yaml](yaml/app-livenessProbe.yaml) |
| **app-readinessProbe** | Create a Pod manifest that combines liveness and readiness probes, from this specification:<br>pod: app-readiness-probe (label app=demo)<br>container: app, image gcr.io/smartcity-gl/harmonic:v2.0.2, TCP 8000 named http<br>livenessProbe: GET / on http; initialDelaySeconds 5, timeoutSeconds 1, periodSeconds 10, failureThreshold 3<br>readinessProbe: GET /ready on http; initialDelaySeconds 0, periodSeconds 2, failureThreshold 3, successThreshold 1 | Structured input: the specification is given as key-value lines, so every probe parameter maps 1:1 to a field and nothing is left to the model's defaults. | [yaml/app-readinessProbe.yaml](yaml/app-readinessProbe.yaml) |
| **app-volumeMounts** | Create a Pod manifest for kuard that persists data on the node.<br>- Pod app-volume, label app=demo; container app, image gcr.io/kuar-demo/kuard-amd64:1, TCP 8080 named http.<br>- livenessProbe GET /healthy and readinessProbe GET /ready, both on port http; liveness: delay 5s,<br>  timeout 1s, period 10s, failureThreshold 3; readiness: delay 0s, period 2s, failureThreshold 3.<br>- Volume named data of type hostPath, path /var/lib/app, type DirectoryOrCreate, mounted at /data. | Pod with probes and a hostPath volume. Exact volume type (DirectoryOrCreate) is part of the instruction, so creating a missing node directory is explicit instead of left to the untyped default. | [yaml/app-volumeMounts.yaml](yaml/app-volumeMounts.yaml) |
| **app-cronjob** | Create a CronJob manifest (apiVersion batch/v1) named app-cronjob.<br>- Schedule: every 5 minutes. A run must not start while the previous one is still running.<br>- Keep the last 3 successful and the last 1 failed Jobs.<br>- Container hello, image bash:5.2, command: echo "Hello world"; restartPolicy OnFailure. | CronJob on the current batch/v1 API. Behaviour is described in plain words ("must not start while the previous one is still running") and the model translates it into concurrencyPolicy and history limits. | [yaml/app-cronjob.yaml](yaml/app-cronjob.yaml) |
| **app-job** | Create a batch Job manifest named app-job for a two-step data pipeline on GKE.<br>- Step 1, init container init (image google/cloud-sdk:275.0.0-alpine): sync the bucket into the input<br>  volume with: gsutil -m rsync -dr gs://glow-sportradar/ /data/input<br>- Step 2, container processor (image glowtools/soccer:latest-4e4254a): run /bin/sh -c "ls -l /data/input".<br>- Volumes: data-input from an existing PersistentVolumeClaim named glow-data-input, mounted at<br>  /data/input in both containers; data-output as emptyDir, mounted at /data/output in processor.<br>- Fail fast: restartPolicy Never, backoffLimit 0. No lifecycle hooks. | Contextual prompting: the pipeline is described step by step (sync bucket, then process) and the deprecated in-tree GCE disk is replaced by a PersistentVolumeClaim. No lifecycle hooks, because preStop never fires for a run-to-completion container. | [yaml/app-job.yaml](yaml/app-job.yaml) |
| **app-multicontainer** | Create a Pod manifest named app-two-containers that shows the sidecar content-generator pattern.<br>- Shared emptyDir volume html.<br>- Container nginx (image nginx:1.27) serves the volume mounted at /usr/share/nginx/html.<br>- Container writer (image debian:12-slim) mounts it at /html and appends the current date to<br>  /html/index.html once per second in an endless shell loop. | Pattern-oriented prompt: names the sidecar content-generator pattern and the role of each container, with pinned image tags. | [yaml/app-multicontainer.yaml](yaml/app-multicontainer.yaml) |
| **app-resources** | Create a Pod manifest named app-resource that sets explicit compute resources.<br>- Container app, image gcr.io/kuar-demo/kuard-amd64:1, TCP 8080 named http, label app=demo.<br>- livenessProbe GET /healthy (delay 5s, timeout 1s, period 10s, failureThreshold 3) and readinessProbe<br>  GET /ready (delay 0s, period 2s, failureThreshold 3), both on port http.<br>- Requests: cpu 100m, memory 128Mi. Limits: cpu 1000m, memory 256Mi. | Compute resources with exact requests and limits next to the probes; numbers are given, not left to the model. | [yaml/app-resources.yaml](yaml/app-resources.yaml) |
| **app-secret-env** | Create two documents in one YAML stream, separated by ---:<br>1. Secret mysecret1 (type Opaque) with keys username and password, using stringData with the<br>   placeholder values "change-me" (they will be replaced at deploy time).<br>2. Pod app-secret-env with container mycontainer (image redis:7.4) that reads the secret into the<br>   environment variables SECRET_USERNAME and SECRET_PASSWORD via secretKeyRef; restartPolicy Never. | Multi-document output: the Secret the Pod depends on is generated in the same stream, with placeholder values instead of real credentials. | [yaml/app-secret-env.yaml](yaml/app-secret-env.yaml) |
| **ingress** | Create an Ingress (networking.k8s.io/v1) named app that publishes the demo app over HTTPS.<br>- ingressClassName: nginx.<br>- Host demo.example.com, path / with pathType Prefix, backend Service app on port 80.<br>- TLS for demo.example.com with the Secret demo-tls.<br>Use only standard fields: no controller-specific annotations. | Ingress for the optional Gateway API part: ingressClassName nginx and standard fields only, so ingress2gateway can convert it without losing controller-specific annotations. | [yaml/ingress.yaml](yaml/ingress.yaml) |
| **app (analyse)** | Context: this bare Pod is the first manifest a team deploys for a demo web app.<br>Focus on what a bare Pod lacks for production (self-healing, health checks, resources, security context)<br>and fix it without changing the image, labels or port. | Review of a bare Pod against production expectations (self-healing, health checks, resources, security context), with the constraint to keep image, labels and port. Input: [original](yaml/original/app.yaml). | [yaml/app.fixed.yaml](yaml/app.fixed.yaml) |
| **app-livenessProbe (analyse)** | Context: after deployment this Pod restarts every ~30 seconds.<br>Find the root cause first, then any other problem (namespace, naming, missing probes). | Symptom-first context ("restarts every ~30 seconds"): the model is asked for the root cause before other findings. Finds the probe port 8000 vs container port 8080 mismatch. Input: [original](yaml/original/app-livenessProbe.yaml). | [yaml/app-livenessProbe.fixed.yaml](yaml/app-livenessProbe.fixed.yaml) |
| **app-readinessProbe (analyse)** | Context: the service behind this Pod should only receive traffic once the app is ready.<br>Check that the probes are consistent with each other and with the container port, and that their timings make sense. | Consistency check between the two probes, the container port and the probe timings. Input: [original](yaml/original/app-readinessProbe.yaml). | [yaml/app-readinessProbe.fixed.yaml](yaml/app-readinessProbe.fixed.yaml) |
| **app-volumeMounts (analyse)** | Context: the platform team wants to run this Pod on a shared multi-tenant cluster.<br>Focus on the storage choice and its security / scheduling consequences, then the rest. | Review from the perspective of a multi-tenant platform team: storage choice (hostPath) and its security and scheduling consequences come first. Input: [original](yaml/original/app-volumeMounts.yaml). | [yaml/app-volumeMounts.fixed.yaml](yaml/app-volumeMounts.fixed.yaml) |
| **app-cronjob (analyse)** | Context: applying this manifest to a Kubernetes 1.34 cluster fails.<br>Explain why, fix it, then check scheduling behaviour (overlapping runs, history limits) and the image. | Failure-driven context ("applying to 1.34 fails"): the model explains the removed batch/v1beta1 API, fixes it, then checks overlapping runs, history limits and the untagged image. Input: [original](yaml/original/app-cronjob.yaml). | [yaml/app-cronjob.fixed.yaml](yaml/app-cronjob.fixed.yaml) |
| **app-job (analyse)** | Context: this Job processes a data set on GKE; the team says the preStop hook "never writes its message".<br>Explain why, then review the volume types, the image tag and the failure policy.<br>Keep the answer short: at most 3 findings, and do not add resources or securityContext blocks. | Debugging a reported symptom ("preStop never writes its message"), then a review of volume types and image tag. The answer is capped at 3 findings: the full review did not fit into kubectl-ai's output length. Input: [original](yaml/original/app-job.yaml). | [yaml/app-job.fixed.yaml](yaml/app-job.fixed.yaml) |
| **app-multicontainer (analyse)** | Context: a two-container Pod where one container generates the page another serves.<br>Review naming, image pinning, resource usage of the endless loop and anything that breaks the sidecar pattern. | Review of a two-container Pod: naming, image pinning and resource limits for both containers. Input: [original](yaml/original/app-multicontainer.yaml). | [yaml/app-multicontainer.fixed.yaml](yaml/app-multicontainer.fixed.yaml) |
| **app-resources (analyse)** | Context: this Pod already sets requests and limits. Assess whether the values and the request/limit ratio<br>are sensible and which QoS class the Pod gets; it is fine to report that nothing is broken. | Assessment prompt that explicitly allows "nothing is broken": request/limit ratio and the resulting QoS class. Input: [original](yaml/original/app-resources.yaml). | [yaml/app-resources.fixed.yaml](yaml/app-resources.fixed.yaml) |
| **app-secret-env (analyse)** | Context: the Pod reads credentials from a Secret. Review how the secret is referenced and what happens<br>if it does not exist, plus image pinning and secret-handling security. | Secret handling: what happens when the referenced Secret is missing, plus image pinning and secret-handling security. Input: [original](yaml/original/app-secret-env.yaml). | [yaml/app-secret-env.fixed.yaml](yaml/app-secret-env.fixed.yaml) |
<!-- table:end -->

## Reviewer notes

The analyse outputs are kept as the model returned them. A human review of the fixes found
these problems - check them before using a fixed manifest:

- [`app-volumeMounts.fixed.yaml`](yaml/app-volumeMounts.fixed.yaml) replaces `hostPath` with
  `emptyDir`, so the data no longer survives the Pod; a PersistentVolumeClaim would keep it.
- [`app-secret-env.fixed.yaml`](yaml/app-secret-env.fixed.yaml): finding 1 is wrong - the Pod
  spec holds only the Secret reference, not the value; `optional: false` is already the default,
  so the "fix" for finding 2 changes nothing.
- [`app-job.fixed.yaml`](yaml/app-job.fixed.yaml) points at a PersistentVolumeClaim
  `glow-data-disk-200` that does not exist (it reuses the GCE disk name), and the image tag
  `4e4254a` is invented.
- [`app-cronjob.fixed.yaml`](yaml/app-cronjob.fixed.yaml): finding 2 says job history is
  unbounded, but without the fields Kubernetes keeps 3 successful and 1 failed job.
- [`app-readinessProbe.fixed.yaml`](yaml/app-readinessProbe.fixed.yaml): `initialDelaySeconds: 0`
  on a readiness probe is harmless (a failing readiness probe only holds back traffic), the
  change to 5 only delays traffic.
- [`app.fixed.yaml`](yaml/app.fixed.yaml) and
  [`app-livenessProbe.fixed.yaml`](yaml/app-livenessProbe.fixed.yaml) set `runAsNonRoot`
  without `runAsUser`: if the image runs as root, the kubelet refuses to start the container.
- [`app-livenessProbe.fixed.yaml`](yaml/app-livenessProbe.fixed.yaml) finds the root cause but
  keeps the hard-coded `namespace: demo` and the name typo `app-livenessprob`, although the
  prompt asks about both.

## Gateway API (optional part)

The [Ingress](yaml/ingress.yaml) from the table was converted with
[ingress2gateway](https://github.com/kubernetes-sigs/ingress2gateway) v1.0.0:

```bash
go install github.com/kubernetes-sigs/ingress2gateway@v1.0.0
ingress2gateway print --input-file yaml/ingress.yaml --providers=ingress-nginx \
  > yaml/gateway-httproute.yaml
```

Result: [`yaml/gateway-httproute.yaml`](yaml/gateway-httproute.yaml) (unedited tool output; its
`generator: ingress2gateway-dev` annotation is v1.0.0 - `go install` does not stamp the version).

| | Ingress | Gateway API |
|---|---|---|
| Resources | 1 `Ingress` | 1 `Gateway` + 2 `HTTPRoute` |
| Entry point (class, ports, TLS) | `ingressClassName`, `tls` inside the Ingress | `Gateway` named after the class: listeners on 80 (HTTP) and 443 (HTTPS with the `demo-tls` certificate) |
| Routing `demo.example.com/` → `app:80` | `rules` inside the Ingress | `HTTPRoute app-demo-example-com`, attached to the 443 listener via `parentRefs` |
| HTTP → HTTPS redirect | implicit (ingress-nginx default when TLS is set) | explicit `HTTPRoute app-demo-example-com-http` with a `RequestRedirect` filter (308) on the 80 listener |

**Key difference between Ingress and HTTPRoute.** An Ingress mixes the entry point (class, TLS)
and the routing rules in one object, and everything beyond host + path (redirects, rewrites,
header matching, traffic splitting) lives in controller-specific annotations that do not carry
over to another controller. An `HTTPRoute` only describes routing and attaches to a `Gateway`
through `parentRefs`; matching on path, headers, query and method, filters (redirects, rewrites,
header changes) and weighted `backendRefs` for canary releases are part of the standard spec, so
behaviour that was implicit in ingress-nginx becomes visible, as the redirect route above shows.

**Who should own the Gateway and who the HTTPRoute.** Gateway API is role-oriented. The
**platform / cluster operator** owns the `Gateway` (and the infrastructure provider the
`GatewayClass`): listeners, ports, TLS certificates and which namespaces may attach routes
(`allowedRoutes`) are shared infrastructure. **Application teams** own the `HTTPRoute` objects in
their own namespaces: they change their routing (paths, canary weights, redirects) without access
to the shared entry point or its certificates, and one team's route cannot break another team's
listener. RBAC can follow the same split.

Validation: `kubeconform` with the Gateway API schemas from the
[CRDs-catalog](https://github.com/datreeio/CRDs-catalog) accepts the `Gateway` and the first
`HTTPRoute`, and rejects the generated `status: {parents: null}` of the redirect route (the
schema wants an array). The `status` block is written by ingress2gateway and ignored by the API
server on `kubectl apply`; the file is kept as the tool produced it.

```bash
kubeconform -strict -summary -kubernetes-version 1.34.0 -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
  yaml/gateway-httproute.yaml
```

## Reproduce

kubectl-ai inspects the cluster of the current kubeconfig with read-only `kubectl` calls before
answering, so run it against a throwaway cluster, never against a real one:

```bash
kind create cluster --name prompt-portfolio --kubeconfig ~/.kube/prompt-portfolio.yaml
export KUBECONFIG=~/.kube/prompt-portfolio.yaml   # scripts/kai.sh refuses any non-kind context
read -rs GEMINI_API_KEY && export GEMINI_API_KEY  # key from https://aistudio.google.com/apikey

kubectl krew install ai
go install github.com/yannh/kubeconform/cmd/kubeconform@v0.8.0
export PATH="$PATH:$(go env GOPATH)/bin"         # kubeconform, ingress2gateway

scripts/kai.sh generate app-livenessProbe   # -> yaml/app-livenessProbe.yaml
KAI_MODEL=gemini-3.5-flash \
  scripts/kai.sh analyse app-livenessProbe  # -> yaml/app-livenessProbe.fixed.yaml
scripts/build-readme.py                     # regenerates the tables above from prompts/
```

## Notes

- `kubeconform` validates the schema only: it does not catch a probe pointing at the wrong port
  or a reference to a Secret that does not exist - that is what the analyse prompts are for.
- kubectl-ai has no temperature setting, so two runs of the same prompt can differ in details.
- With stdout redirected, kubectl-ai renders the code block without fences, indented and wrapped
  at about 72 characters; `scripts/kai.sh` strips the indent and rejects wrapped output.
- kubectl-ai writes a trace to `/tmp/kubectl-ai-trace.txt` by default and that trace contains
  the API key; `scripts/kai.sh` disables it with `--trace-path /dev/null`. It also logs full
  prompts and answers to the world-readable `/tmp/kubectl-ai.log` - delete it after a session.
- Two models: the analyse runs on `gemini-3.8-flash` got only "503 high demand" and timeouts,
  and on the free tier those failed requests still count against the daily request quota. The
  analyse prompts were therefore run on `gemini-3.5-flash`; `scripts/kai.sh` now retries a busy
  model only once.
- Long answers are cut off at a fixed length (kubectl-ai has no output-length setting), so the
  analysis instructions cap the findings at 5 and demand an end marker that `scripts/kai.sh`
  checks. The `app-job` review still did not fit and its prompt limits the answer further.
