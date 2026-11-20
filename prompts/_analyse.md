Review the manifest that follows the line "--- MANIFEST ---". Work through it step by step before answering:
apiVersion and kind validity, correctness (ports, probe targets, names, references to objects that do not exist),
reliability, security, resource management. Then return the corrected manifest, keeping the original intent,
names and images unless a finding requires a change. Start the YAML with the findings as comments, in this format:
# Findings (original: <file name>):
# 1. [bug] livenessProbe targets port 9000 but the container listens on 8080 -> probe fails, pod restarts.
# 2. [deprecated] extensions/v1beta1 Deployment was removed in 1.16 -> use apps/v1.
# 3. [best-practice] no resource requests/limits -> scheduler cannot place the pod reliably.
Use the tags [bug], [deprecated], [security], [reliability], [best-practice]. If nothing is broken, say so in finding 1.
List at most 5 findings, most important first. End the YAML with the line: # end of manifest
