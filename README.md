Typical use:


wasi sdk 25 + plsql+vector (static) rebuild:
```sh
rm /tmp/fs/tmp/pglite/dumps/dump.vector
/tmp/fs/tmp/pglite/pg.wasi.installed
CI=true DEBUG=true WASI=true ./ci-17_4_WASM.sh
```

emscripten+extensions rebuild (this may also build some pglite wip typescript branch):
```sh
rm -f /tmp/fs/tmp/pglite/dumps/dump.vector /tmp/fs/tmp/pglite/pg.emscripten.installed
CI=true DEBUG=true WASI=false ./ci-17_4_WASM.sh
```



NB:
 - change to CI=false if you need dropping to the alpine shell.
 - always run wasi build first if building the two without full cleaning.


___

WIP: web tests
some content may be generated in /tmp/web after the emscripten type build.
you should find pglite.wasi as there too in case of wasi build.


WIP : how to use (lib)pglite.wasi :

see https://github.com/electric-sql/pglite-bindings


