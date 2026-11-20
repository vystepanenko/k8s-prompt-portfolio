Create a single Pod manifest for a demo web application.
- Pod name: app; labels: app=demo, run=demo.
- One container named app, image gcr.io/k8s-k3s/demo:v1.0.0.
- It listens on TCP 8000; expose that port with the name http.
Do not add anything else: no probes, volumes, resources or extra labels.
