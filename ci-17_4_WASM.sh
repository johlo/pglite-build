#!/bin/bash
export WORKSPACE=$(pwd)
export PG_VERSION=${PG_VERSION:-17.4}
export PG_BRANCH=${PG_BRANCH:-REL_17_4_WASM}
export CONTAINER_PATH=${CONTAINER_PATH:-/tmp/fs}
export DEBUG=${DEBUG:-false}
export USE_ICU=${USE_ICU:-false}
export GETZIC=${GETZIC:-false}
export ZIC=${ZIC:-/usr/sbin/zic}

export WASI=${WASI:-false}
if $WASI
then
    export BUILD_PATH=build/postgres-wasi
else
    export BUILD_PATH=build/postgres-emscripten
fi


PG_DIST_EXT="${WORKSPACE}/postgresql/dist/extensions-emsdk"
PG_DIST_PGLITE="${WORKSPACE}/postgresql/dist/pglite-sandbox"

# for local testing
if [ -d /srv/www/html/pglite-web ]
then
    export PG_DIST_WEB="/srv/www/html/pglite-web"
    export LOCAL=true
else
    export PG_DIST_WEB="${WORKSPACE}/postgresql/dist/web"
    export LOCAL=false
fi


#
#[ -f postgresql-${PG_BRANCH}/configure ] \
# || git clone --no-tags --depth 1 --single-branch --branch ${PG_BRANCH} https://github.com/pygame-web/postgres postgresql-${PG_BRANCH}
#

[ -f postgresql-${PG_BRANCH}/configure ] \
 || git clone --no-tags --depth 1 --single-branch --branch ${PG_BRANCH} https://github.com/electric-sql/postgres-pglite postgresql-${PG_BRANCH}

chmod +x portable/*.sh wasm-build/*.sh
cp -R wasm-build* extra patches-${PG_BRANCH} postgresql-${PG_BRANCH}/

if [ -d postgresql-${PG_BRANCH}/pglite-wasm ]
then
    echo "using local pglite files"
else
    mkdir -p postgresql-${PG_BRANCH}/pglite-wasm
    cp -Rv pglite-${PG_BRANCH}/* postgresql-${PG_BRANCH}/pglite-wasm/
fi

cd postgresql-${PG_BRANCH}
#TODO: pglite has .buildconfig in postgres source dir instead.
    cat > $CONTAINER_PATH/portable.opts <<END
export DEBUG=${DEBUG}
export USE_ICU=${USE_ICU}
export PG_VERSION=$PG_VERSION
export PG_BRANCH=$PG_BRANCH
export GETZIC=$GETZIC
export ZIC=$ZIC
END


# execute prooted build
${WORKSPACE}/portable/portable.sh

if [ -f ${WORKSPACE}/postgresql/${BUILD_PATH}/libpgcore.a ]
then
    echo "found postgres core static libraries in ${BUILD_PATH}"
else
    echo "failed to build libpgcore static at ${WORKSPACE}/postgresql/${BUILD_PATH}/libpgcore.a"
    exit 73
fi

cd ${WORKSPACE}


for archive in ${PG_DIST_EXT}/*.tar
do
    echo "    packing extension $archive"
    gzip -f -9 $archive
done

echo "

    *   getting pglite

"

if [ -d ${WORKSPACE}/pglite/packages/pglite ]
then
    echo "using local pglite tree"
else
    git clone --no-tags --depth 1 --single-branch --branch pmp-p/pglite-build17 https://github.com/electric-sql/pglite pglite
fi

echo "
    *   preparing TS build assets
"

pushd ${WORKSPACE}/pglite
    # clean
    [ -d packages/pglite/release ] && rm packages/pglite/release/* packages/pglite/dist/* packages/pglite/dist/*/*

    # be safe
    mkdir -p packages/pglite/release packages/pglite/dist

    rmdir packages/pglite/dist/*

    #update
    mv -vf ${WORKSPACE}/postgresql-${PG_BRANCH}/pglite.* packages/pglite/release/
    mv -vf ${PG_DIST_EXT}/*.tar.gz packages/pglite/release/
popd


# when outside CI use emsdk node
if [ -d /srv/www/html/pglite-web ]
then
    . /opt/python-wasm-sdk/wasm32-bi-emscripten-shell.sh
fi

echo "
    *   compiling Typescript files

"
if $CI
then
    pushd ${WORKSPACE}/postgresql-${PG_BRANCH}/${BUILD_PATH}
        echo "# packing dev files to /tmp/sdk/libpglite-emsdk.tar.gz"
        tar -cpRz libpgcore.a pglite.* > /tmp/sdk/libpglite-emsdk.tar.gz
    popd

    pushd pglite
        npm install -g pnpm vitest
        pnpm install
    popd
fi

pushd ${WORKSPACE}/pglite
    pnpm run ts:build || exit 141
popd

mkdir -p ${PG_DIST_WEB}
if [ -d ${PG_DIST_WEB} ]
then
    pushd postgresql-${PG_BRANCH}
        git restore src/test/Makefile src/test/isolation/Makefile
    popd

    echo "# use released files for web test"
    mkdir -p ${PG_DIST_WEB}/examples
    cp -r ${WORKSPACE}/pglite/packages/pglite/dist ${PG_DIST_WEB}/
    cp ${WORKSPACE}/pglite/packages/pglite/examples/{styles.css,utils.js} ${PG_DIST_WEB}/examples/
    cp -f ${WORKSPACE}/pglite/packages/pglite/release/* ${PG_DIST_WEB}/
    du -hs ${PG_DIST_WEB}/pglite.*

    if $LOCAL
    then
        echo "# backup pglite workfiles"
        [ -d pglite-wasm ] && cp -R pglite-wasm/* ${WORKSPACE}/pglite-${PG_BRANCH}/
    else
        mv ${PG_DIST_WEB} /tmp/web/
    fi
fi


if $LOCAL
then
    echo "skipping tests"
else
    ./runtests.sh
fi

