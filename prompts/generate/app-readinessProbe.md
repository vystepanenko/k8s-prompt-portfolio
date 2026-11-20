Create a Pod manifest that combines liveness and readiness probes, from this specification:
pod: app-readiness-probe (label app=demo)
container: app, image gcr.io/smartcity-gl/harmonic:v2.0.2, TCP 8000 named http
livenessProbe: GET / on http; initialDelaySeconds 5, timeoutSeconds 1, periodSeconds 10, failureThreshold 3
readinessProbe: GET /ready on http; initialDelaySeconds 0, periodSeconds 2, failureThreshold 3, successThreshold 1
