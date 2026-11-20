Create a single Secret manifest (one YAML document, no ---) named mysecret1, type Opaque, for the
Pod app-secret-env. Keys username and password, set via stringData with the placeholder value
"change-me" (real values are injected at deploy time and never committed).
