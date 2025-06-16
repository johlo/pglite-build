#!/bin/bash

. wasm-build/extension.sh

pushd $PG_EXTRA
    if [ -d pg_uuiv7 ]
    then
        echo using local pg_uuiv7
    else
        wget https://github.com/fboulnois/pg_uuidv7/archive/refs/tags/v1.6.0.tar.gz -O-|tar xfz -
        mv pg_uuidv7-*.*.* pg_uuiv7
        if $WASI
        then
            echo "no patching"
        else
            echo "PATCH?"

        fi
    fi
popd

pushd $PG_EXTRA/pg_uuiv7
    PG_CONFIG=${PGROOT}/bin/pg_config emmake make OPTFLAGS="" install || exit 25
popd


