Typical use:


emscripten+extensions rebuild:
```sh
rm -f /tmp/fs/tmp/pglite/dumps/dump.vector /tmp/fs/tmp/pglite/pg.emscripten.installed
CI=false DEBUG=true WASI=false /data/git/pglite-build/ci-17_4_WASM.sh
```
note this may also build some pglite-next typescript branch



wasi sdk 25 + plsql+vector (static) rebuild:
```sh
rm /tmp/fs/tmp/pglite/dumps/dump.vector
/tmp/fs/tmp/pglite/pg.wasi.installed
CI=false DEBUG=true WASI=true /data/git/pglite-build/ci-17_4_WASM.sh
```

NB: change to CI=true if you don't need dropping to the alpine shell.



WIP : how to use (lib)pglite.wasi :

see https://github.com/electric-sql/pglite-bindings
