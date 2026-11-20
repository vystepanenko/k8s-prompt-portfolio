Create an Ingress (networking.k8s.io/v1) named app that publishes the demo app over HTTPS.
- ingressClassName: nginx.
- Host demo.example.com, path / with pathType Prefix, backend Service app on port 80.
- TLS for demo.example.com with the Secret demo-tls.
Use only standard fields: no controller-specific annotations.
