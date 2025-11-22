You can apply nok-tools to have a linux server for any communicatino testing inside a namespace

Testing if port is reacheable:
```
nc -vz srl1 57400
```

Checking if services are working
```
curl --resolve test.nok.dev:8080:127.0.0.1 http://test.nok.dev:8080/gnmic/metrics
```

