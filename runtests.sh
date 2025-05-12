#!/bin/bash
reset
if [ -d  /srv/www/html/pglite-web ]
then
    . /opt/python-wasm-sdk/wasm32-bi-emscripten-shell.sh
fi

pushd pglite/packages/pglite

    skipt=false

    for test in $(find ./tests/*.ts ./tests/contrib/*.ts)
    do
        for skip in tests/test-utils.js$ tests/test-utils.ts$
        do
            if echo $test|grep -q $skip
            then
                skipt=true
                break
            else
                skipt=false
            fi
        done

        if $skipt
        then
            echo skipping $test
            continue
        fi

        if vitest --bail 1 $test
        then
            echo -n
        else
            echo "Test: $test failed"
            break
        fi
    done

popd
