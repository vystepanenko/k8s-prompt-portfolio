Create a batch Job manifest named app-job for a two-step data pipeline on GKE.
- Step 1, init container init (image google/cloud-sdk:275.0.0-alpine): sync the bucket into the input
  volume with: gsutil -m rsync -dr gs://glow-sportradar/ /data/input
- Step 2, container processor (image glowtools/soccer:latest-4e4254a): run /bin/sh -c "ls -l /data/input".
- Volumes: data-input from an existing PersistentVolumeClaim named glow-data-input, mounted at
  /data/input in both containers; data-output as emptyDir, mounted at /data/output in processor.
- Fail fast: restartPolicy Never, backoffLimit 0. No lifecycle hooks.
