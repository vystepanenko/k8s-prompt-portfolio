Create a CronJob manifest (apiVersion batch/v1) named app-cronjob.
- Schedule: every 5 minutes. A run must not start while the previous one is still running.
- Keep the last 3 successful and the last 1 failed Jobs.
- Container hello, image bash:5.2, command: echo "Hello world"; restartPolicy OnFailure.
