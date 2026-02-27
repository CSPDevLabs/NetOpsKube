





Adding Network Device Targets using this format.

```yaml
apiVersion: nok.dev/v1alpha1
kind: NetworkDeviceTarget
metadata:
  name: clab-sros-bngt-agg
  namespace: nok-bng
spec:
  address: 172.21.20.21
  hostname: clab-sros-bngt-agg
  commonLabels:
    vendor: Nokia
    environment: production
  sdcio:
    enabled: true
    credentialsSecretRef: sros.nokia.sdcio.dev
    connectionProfileRef: gnmi-skipverify
    syncProfileRef: gnmi-get
    schema:
      provider: sros.nokia.sdcio.dev
      version: B-25.10.R1
    labels:
      sdcio.dev/region: us-central
      sdcio.dev/role: bng
  gnmic:
    enabled: true
    credentialsSecretRef: device-credentials
    targetProfileRef: default-profile
    port: "57400"
    labels:
      role: bng-ext
```    