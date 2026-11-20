Create a single Pod manifest (one YAML document, no ---) named app-secret-env.
- Container mycontainer, image redis:7.4; restartPolicy Never.
- Environment variables SECRET_USERNAME and SECRET_PASSWORD come from the keys username and
  password of the Secret mysecret1 via secretKeyRef. The Secret is a separate manifest
  (app-secret.yaml): do not include it here.
