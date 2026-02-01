. /tmp/pglite/pgopts.sh
. /tmp/sdk/wasm32-wasi-shell.sh
if ./pglite-REL_17_4_WASM/build.sh
then
    echo "TODO: tests"
else
    echo "pglite linking failed"; exit 545
fi
