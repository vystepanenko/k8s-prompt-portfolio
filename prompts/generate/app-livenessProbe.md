Create a Pod manifest that shows an HTTP liveness probe.
- Pod name: app-liveness-probe, label app=demo; container app, image gcr.io/smartcity-gl/demo:v1.0.1.
- The container listens on TCP 8080, port name http.
- Liveness probe: HTTP GET / on the port name http (not a number, so the probe cannot drift from the
  container port); initialDelaySeconds 5, timeoutSeconds 1, periodSeconds 10, failureThreshold 3.
