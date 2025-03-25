#!/bin/bash
echo "pglite/build: begin"

WORKSPACE=$(pwd)
PGROOT=/tmp/pglite

if [ -d ${WORKSPACE}/src/fe_utils ]
then
    PGSRC=${WORKSPACE}
else
    PGSRC=${WORKSPACE}/postgresql
fi

WASI=${WASI:-false}

if ${WASI:-false}
then
    BUILD=wasi
else
    BUILD=emscripten
fi

BUILD_PATH=build/postgres-${BUILD}

LIBPGCORE=${BUILD_PATH}/libpgcore.a

WEBROOT=${PGBUILD}/web

PGINC=" -I${BUILD_PATH}/src/include \
-I${PGSRC}/src/include -I${PGSRC}/src \
-I${PGSRC}/src/interfaces/libpq -I${PGROOT}/include"

#  -I${PGROOT}/include/postgresql/server"


if $WASI
then

    GLOBAL_BASE_B=$(python3 -c "print(${CMA_MB}*1024*1024)")
echo "
________________________________________________________

wasi : $(which wasi-c) $(wasi-c -v)
python : $(which python3) $(python3 -V)
wasmtime : $(which wasmtime)

CC=${CC:-undefined}

Linking to libpgcore static from $LIBPGCORE

Folders :
    source : $PGSRC
     build : $BUILD_PATH
    target : $PGROOT

    CPOPTS : $COPTS
    DEBUG  : $DEBUG
        LOPTS  : $LOPTS
     CMA_MB : $CMA_MB
GLOBAL_BASE : $GLOBAL_BASE_B

 CC_PGLITE : $CC_PGLITE

  ICU i18n : $USE_ICU

INCLUDES: $PGINC
________________________________________________________


"


    if ${CC} -ferror-limit=1 ${CC_PGLITE} \
     ${PGINC} \
     -DPOSTGRES_C=\"../postgresql/src/backend/tcop/postgres.c\" \
     -DPQEXPBUFFER_H=\"../postgresql/src/interfaces/libpq/pqexpbuffer.h\" \
     -DOPTION_UTILS_C=\"../postgresql/src/fe_utils/option_utils.c\" \
     -o ${BUILD_PATH}/pglite.o -c ${WORKSPACE}/pglite-wasm/pg_main.c \
     -Wno-incompatible-pointer-types-discards-qualifiers
    then
        if ${CC} -fpic -ferror-limit=1 ${CC_PGLITE}  ${PGINC} \
         -o ${BUILD_PATH}/sdk_port-wasi.o \
         -c wasm-build/sdk_port-wasi/sdk_port-wasi-dlfcn.c \
         -Wno-incompatible-pointer-types
        then

            # some content that does not need to ship into .data
            for cleanup in snowball_create.sql psqlrc.sample
            do
                > ${PREFIX}/${cleanup}
            done

            COPTS="$LOPTS" ${CC} ${CC_PGLITE} -ferror-limit=1 -Wl,--global-base=${GLOBAL_BASE_B} -o pglite.wasi \
             -nostartfiles ${PGINC} ${BUILD_PATH}/pglite.o \
             ${BUILD_PATH}/sdk_port-wasi.o \
             $LINKER $LIBPGCORE \
             $LINK_ICU \
             build/postgres-wasi/src/backend/snowball/libdict_snowball.a \
             build/postgres-wasi/src/pl/plpgsql/src/libplpgsql.a \
             -lxml2 -lz
            reset
        fi
    fi

else
    . ${SDKROOT:-/opt/python-wasm-sdk}/wasm32-bi-emscripten-shell.sh

    touch placeholder

    export PGPRELOAD="\
--preload-file ${PGROOT}/share/postgresql@${PGROOT}/share/postgresql \
--preload-file ${PGROOT}/lib/postgresql@${PGROOT}/lib/postgresql \
--preload-file ${PGROOT}/password@${PGROOT}/password \
--preload-file ${PGROOT}/PGPASSFILE@/home/web_user/.pgpass \
--preload-file placeholder@${PGROOT}/bin/postgres \
--preload-file placeholder@${PGROOT}/bin/initdb\
"

    export CC=$(which emcc)


    EXPORTED_FUNCTIONS="_main,_use_wire,_ping,_pgl_initdb,_pgl_backend,_pgl_shutdown,_interactive_write,_interactive_read,_interactive_one"

    EXPORTED_RUNTIME_METHODS="MEMFS,IDBFS,FS,FS_mount,FS_syncfs,FS_analyzePath,setValue,getValue,UTF8ToString,stringToNewUTF8,stringToUTF8OnStack"
    EXPORTED_RUNTIME_METHODS="MEMFS,IDBFS,FS,setValue,getValue,UTF8ToString,stringToNewUTF8,stringToUTF8OnStack"



    if $DEBUG
    then
        # FULL
        LINKER="-sMAIN_MODULE=1 -sEXPORTED_FUNCTIONS=${EXPORTED_FUNCTIONS}"
    else
        # min
        # LINKER="-sMAIN_MODULE=2"

        # tailored
        LINKER="-sMAIN_MODULE=2 -sEXPORTED_FUNCTIONS=@exports"
LINKER="-sMAIN_MODULE=1 -sEXPORTED_FUNCTIONS=${EXPORTED_FUNCTIONS}"
    fi

    echo "

________________________________________________________

emscripten : $(which emcc ) $(cat ${SDKROOT}/VERSION)
python : $(which python3) $(python3 -V)
wasmtime : $(which wasmtime)

CC=${CC:-undefined}

Linking to libpgcore static from $LIBPGCORE

Folders :
    source : $PGSRC
     build : $BUILD_PATH
    target : $WEBROOT

    CPOPTS : $COPTS
    DEBUG  : $DEBUG
        LOPTS  : $LOPTS
    CMA_MB : $CMA_MB

 CC_PGLITE : $CC_PGLITE

  ICU i18n : $USE_ICU

$PGPRELOAD
________________________________________________________



"

    rm pglite.*

    mkdir -p $WEBROOT

    if $USE_ICU
    then
        LINK_ICU="${PREFIX}/lib/libicui18n.a ${PREFIX}/lib/libicuuc.a ${PREFIX}/lib/libicudata.a"
    else
        LINK_ICU=""
    fi

#    ${CC} ${CC_PGLITE} -DPG_INITDB_MAIN \
#     ${PGINC} \
#     -o ${PGBUILD}/initdb.o -c ${PGSRC}/src/bin/initdb/initdb.c

    ${CC} ${CC_PGLITE} ${PGINC} -o ${BUILD_PATH}/pglite.o -c ${WORKSPACE}/pglite-wasm/pg_main.c \
     -Wno-incompatible-pointer-types-discards-qualifiers

    COPTS="$LOPTS" ${CC} ${CC_PGLITE} -sGLOBAL_BASE=${CMA_MB}MB -o pglite-rawfs.js -ferror-limit=1  \
     -sFORCE_FILESYSTEM=1 $EMCC_NODE \
         -sALLOW_TABLE_GROWTH -sALLOW_MEMORY_GROWTH -sERROR_ON_UNDEFINED_SYMBOLS \
         -sEXPORTED_RUNTIME_METHODS=${EXPORTED_RUNTIME_METHODS} \
     ${PGINC} ${BUILD_PATH}/pglite.o \
     $LINKER $LIBPGCORE \
     $LINK_ICU \
     -lnodefs.js -lidbfs.js -lxml2 -lz


    # some content that does not need to ship into .data
    for cleanup in snowball_create.sql psqlrc.sample
    do
        > ${PREFIX}/${cleanup}
    done


    COPTS="$LOPTS" ${CC} ${CC_PGLITE} -sGLOBAL_BASE=${CMA_MB}MB -o pglite.html -ferror-limit=1 --shell-file ${WORKSPACE}/pglite-wasm/repl.html \
     $PGPRELOAD \
     -sFORCE_FILESYSTEM=1 -sNO_EXIT_RUNTIME=1 -sENVIRONMENT=node,web \
     -sMODULARIZE=1 -sEXPORT_ES6=1 -sEXPORT_NAME=Module \
         -sALLOW_TABLE_GROWTH -sALLOW_MEMORY_GROWTH -sERROR_ON_UNDEFINED_SYMBOLS \
         -sEXPORTED_RUNTIME_METHODS=${EXPORTED_RUNTIME_METHODS} \
     ${PGINC} ${BUILD_PATH}/pglite.o \
     $LINKER $LIBPGCORE \
     $LINK_ICU \
     -lnodefs.js -lidbfs.js -lxml2 -lz

fi

du -hs pglite.*

echo "pglite/build: end"

