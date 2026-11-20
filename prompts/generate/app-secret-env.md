Create two documents in one YAML stream, separated by ---:
1. Secret mysecret1 (type Opaque) with keys username and password, using stringData with the
   placeholder values "change-me" (they will be replaced at deploy time).
2. Pod app-secret-env with container mycontainer (image redis:7.4) that reads the secret into the
   environment variables SECRET_USERNAME and SECRET_PASSWORD via secretKeyRef; restartPolicy Never.
