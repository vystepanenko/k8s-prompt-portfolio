Create a Pod manifest for kuard that persists data on the node.
- Pod app-volume, label app=demo; container app, image gcr.io/kuar-demo/kuard-amd64:1, TCP 8080 named http.
- livenessProbe GET /healthy and readinessProbe GET /ready, both on port http; liveness: delay 5s,
  timeout 1s, period 10s, failureThreshold 3; readiness: delay 0s, period 2s, failureThreshold 3.
- Volume named data of type hostPath, path /var/lib/app, type DirectoryOrCreate, mounted at /data.
