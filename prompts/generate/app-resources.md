Create a Pod manifest named app-resource that sets explicit compute resources.
- Container app, image gcr.io/kuar-demo/kuard-amd64:1, TCP 8080 named http, label app=demo.
- livenessProbe GET /healthy (delay 5s, timeout 1s, period 10s, failureThreshold 3) and readinessProbe
  GET /ready (delay 0s, period 2s, failureThreshold 3), both on port http.
- Requests: cpu 100m, memory 128Mi. Limits: cpu 1000m, memory 256Mi.
