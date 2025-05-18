# Web Front End

To test, first make cluster available locally:

```
export KUBECONFIG=kubeconfig.yaml
kubectl port-forward -n trading svc/centrifugo 8000:8000 9000:9000
```

Then run in VSC with these settings:

```
    {
      "type": "chrome",
      "request": "launch",
      "name": "Launch Chrome against localhost",
      "url": "http://localhost:5173",
      "webRoot": "${workspaceFolder}/fe",
      "sourceMaps": true,
      "sourceMapPathOverrides": {
        "webpack:///./~/*": "${webRoot}/node_modules/*",
        "webpack:///./*": "${webRoot}/*",
        "webpack:///*": "*"
      },
      "preLaunchTask": "npm: dev"
    },
```
