Create a Pod manifest named app-two-containers that shows the sidecar content-generator pattern.
- Shared emptyDir volume html.
- Container nginx (image nginx:1.27) serves the volume mounted at /usr/share/nginx/html.
- Container writer (image debian:12-slim) mounts it at /html and appends the current date to
  /html/index.html once per second in an endless shell loop.
