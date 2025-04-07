#!/bin/bash
export PGL_BRANCH=pmp-p/pglite-build17
export PG_VERSION=${PG_VERSION:-17.4}
export PG_BRANCH=${PG_BRANCH:-REL_17_4_WASM}

export CONTAINER_PATH=${CONTAINER_PATH:-/tmp/fs}
export DEBUG=${DEBUG:-false}
export USE_ICU=${USE_ICU:-false}
export GETZIC=${GETZIC:-false}
export ZIC=${ZIC:-/usr/sbin/zic}
export CI=${CI:-false}

export WORKSPACE=$(pwd)

export WASI=${WASI:-false}
if $WASI
then
    BUILD=wasi
else
    BUILD=emscripten
fi

export BUILD_PATH=${WORKSPACE}/build-${PG_BRANCH}/${BUILD}
export DIST_PATH=${WORKSPACE}/dist-${PG_BRANCH}


# for local testing
if [ -d /srv/www/html/pglite-web ]
then
    echo "local ${BUILD} build"
    export PG_DIST_WEB="/srv/www/html/pglite-web"
    export LOCAL=true
else
    export PG_DIST_WEB="${DIST_PATH}/web"
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

mkdir -p $CONTAINER_PATH/tmp

#TODO: pglite has .buildconfig in postgres source dir instead.
    cat > $CONTAINER_PATH/tmp/portable.opts <<END
export DEBUG=${DEBUG}
export USE_ICU=${USE_ICU}
export PG_VERSION=${PG_VERSION}
export PG_BRANCH=${PG_BRANCH}
export GETZIC=${GETZIC}
export ZIC=${ZIC}
export CI=${CI}
export WASI=${WASI}
END


if [ -d ${WORKSPACE}/pglite/packages/pglite ]
then
    echo "using local pglite tree"
else
    echo "

    *   getting pglite branch $PGL_BRANCH

"
    git clone --no-tags --depth 1 --single-branch --branch $PGL_BRANCH https://github.com/electric-sql/pglite pglite
fi


# execute prooted build
${WORKSPACE}/portable/portable.sh


if $LOCAL
then
    echo "TODO: start a test server for $PG_DIST_WEB"
else
    # gh pages publish
    PG_DIST_WEB=/tmp/web
    mkdir -p $PG_DIST_WEB
    touch $PG_DIST_WEB/.nojekyll
fi

[ -f $DIST_PATH/pglite.wasi ] &&  cp -vf $DIST_PATH/pglite.wasi $PG_DIST_WEB/
[ -f $DIST_PATH/pglite-wasi.tar.xz ] &&  cp -vf $DIST_PATH/pglite-wasi.tar.xz $PG_DIST_WEB/


if $WASI
then
    echo "TODO: wasi post link"
else

    if [ -f ${BUILD_PATH}/libpgcore.a ]
    then
        echo "found postgres core static libraries in ${BUILD_PATH}"
    else
        echo "failed to build libpgcore static at ${BUILD_PATH}/libpgcore.a"
        exit 85
    fi

    cp -f pglite/packages/pglite/dist/*.tar.gz $PG_DIST_WEB/
    cp -f pglite/packages/pglite/dist/pglite.* $PG_DIST_WEB/
    mv -v pglite/packages/pglite/release/pglite.html $PG_DIST_WEB/index.html
fi
