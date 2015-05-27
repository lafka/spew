# spew-cli

## Example

```
# open in different terminals
./bin/spew-cli run test --type=systemd --attach=true -- /bin/busybox sh -c 'read n; echo "got n"'
./bin/spew-cli log test
./bin/spew-cli attach test # send some date
```
