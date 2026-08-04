You can apply nok-tools to get a Linux server for communication testing inside a namespace.

Test whether a port is reachable:
```
nc -vz srl1 57400
```

Check whether services are working:
```
curl --resolve test.nok.dev:8080:127.0.0.1 http://test.nok.dev:8080/gnmic/metrics
```

