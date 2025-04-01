#!/bin/bash
export WORKSPACE=$(pwd)
export PG_VERSION=${PG_VERSION:-17.4}
export PG_BRANCH=${PG_BRANCH:-REL_17_4_WASM}
export CONTAINER_PATH=${CONTAINER_PATH:-/tmp/fs}
export DEBUG=${DEBUG:-false}
export USE_ICU=${USE_ICU:-false}
export GETZIC=${GETZIC:-false}
export ZIC=${ZIC:-/usr/sbin/zic}
export CI=${CI:-false}


export WASI=${WASI:-false}
if $WASI
then
    export BUILD_PATH=postgresql-${PG_BRANCH}/build/postgres-wasi
else
    export BUILD_PATH=postgresql-${PG_BRANCH}/build/postgres-emscripten
fi

PG_DIST_EXT="${WORKSPACE}/postgresql-${PG_BRANCH}/dist/extensions-emsdk"
PG_DIST_PGLITE="${WORKSPACE}/postgresql-${PG_BRANCH}/dist/pglite-sandbox"

# for local testing
if [ -d /srv/www/html/pglite-web ]
then
    echo "local build"
    export PG_DIST_WEB="/srv/www/html/pglite-web"
    export LOCAL=true
else
    export PG_DIST_WEB="${WORKSPACE}/dist/web"
    export LOCAL=false
    # is it a pre-patched postgres-pglite release tree ?
    if [ -f configure ]
    then
        [ -f postgresql-${PG_BRANCH}.patched ] && ln -s . postgresql-pglite
        [ -f postgresql-${PG_BRANCH}.patched ] && ln -s . postgresql-${PG_BRANCH}
        [ -f postgresql-${PG_BRANCH}.patched ] && ln -s . postgresql-${PG_VERSION}
    else
        # unpatched upstream ( pglite-build case )
        [ -f postgresql-${PG_BRANCH}/configure ] \
         || git clone --no-tags --depth 1 --single-branch --branch ${PG_BRANCH} https://github.com/electric-sql/postgres-pglite postgresql-${PG_BRANCH}
    fi
fi


if [ -f pglite-wasm/build.sh ]
then
    echo "using local pglite files"
else
    mkdir -p pglite-wasm
    cp -Rv pglite-${PG_BRANCH}/* pglite-wasm/
fi

mkdir -p $CONTAINER_PATH

#TODO: pglite has .buildconfig in postgres source dir instead.
    cat > $CONTAINER_PATH/portable.opts <<END
export DEBUG=${DEBUG}
export USE_ICU=${USE_ICU}
export PG_VERSION=$PG_VERSION
export PG_BRANCH=$PG_BRANCH
export GETZIC=$GETZIC
export ZIC=$ZIC
export CI=$CI
END


if [ -d ${WORKSPACE}/pglite/packages/pglite ]
then
    echo "using local pglite tree"
else
    echo "

    *   getting pglite

"
    git clone --no-tags --depth 1 --single-branch --branch pmp-p/pglite-build17 https://github.com/electric-sql/pglite pglite
fi


# execute prooted build
${WORKSPACE}/portable/portable.sh


du -hs $BUILD_PATH $PG_DIST_EXT $PG_DIST_PGLITE

if [ -f ${WORKSPACE}/${BUILD_PATH}/libpgcore.a ]
then
    echo "found postgres core static libraries in ${WORKSPACE}/${BUILD_PATH}"
else
    echo "failed to build libpgcore static at ${WORKSPACE}/postgresql-${PG_BRANCH}/${BUILD_PATH}/libpgcore.a"
    exit 85
fi

if $LOCAL
then
    cp -f pglite/packages/pglite/dist/*.tar.gz $PG_DIST_WEB/
    cp -f pglite/packages/pglite/dist/pglite.* $PG_DIST_WEB/
    mv -v pglite/packages/pglite/release/pglite.html $PG_DIST_WEB/
    echo "TODO: start test server"
else
    # gh pages
    mkdir -p /tmp/web
    cp -f pglite/packages/pglite/dist/*.tar.gz /tmp/web/
    cp -f pglite/packages/pglite/dist/pglite.* /tmp/web/
    mv -v pglite/packages/pglite/release/pglite.html /tmp/web/index.html
fi

