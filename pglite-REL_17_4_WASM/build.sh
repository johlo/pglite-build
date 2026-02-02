export WASI=${WASI:-false}

if ${PGCRYPTO:-false}
then
    export LINK_CRYPTO="-lcrypto"
else
    export LINK_CRYPTO=""
fi

if ${WASI}
then
    BUILD=wasi
else
    BUILD=emscripten
    WEBROOT=${PG_DIST}/web
fi

echo "pglite/build-$BUILD: begin target BUILD_PATH=$BUILD_PATH"

WORKSPACE=$(pwd)
PGROOT=/tmp/pglite

if [ -d ${WORKSPACE}/src/fe_utils ]
then
    PGSRC=${WORKSPACE}
else
    PGSRC=${WORKSPACE}/postgresql-${PG_BRANCH}
fi

LIBPGCORE=${BUILD_PATH}/libpgcore.a



PGINC=" -I${BUILD_PATH}/src/include \
-I${PGROOT}/include -I${PGROOT}/include/postgresql/server \
-I${PGSRC}/src/include -I${PGSRC}/src/interfaces/libpq -I${PGSRC}/src"


GLOBAL_BASE_B=$(python3 -c "print(${CMA_MB}*1024*1024)")


if $WASI
then
    WASI_HSTORE=${WASI_HSTORE:-true}
    HSTORE_LIB=""
    HSTORE_OBJS=""
    if ${WASI_HSTORE}
    then
        if [ -d "${PGSRC}/contrib/hstore" ]
        then
            python3 ${WORKSPACE}/wasm-build/gen_wasi_ext_syms.py \
                --ext hstore \
                --sql-dir "${PGSRC}/contrib/hstore" \
                --out "${PGROOT}/include/wasi_hstore_syms.h"
            if [ ! -s "${PGROOT}/include/wasi_hstore_syms.h" ] || ! grep -Eq "wasi_hstore_syms|pg_finfo_" "${PGROOT}/include/wasi_hstore_syms.h"
            then
                echo "wasi hstore symbols header is empty: ${PGROOT}/include/wasi_hstore_syms.h"
                exit 173
            fi
        else
            echo "hstore contrib sources not found at ${PGSRC}/contrib/hstore"
            exit 171
        fi

        HSTORE_BUILD_DIR="${PG_BUILD}/${BUILD}/contrib/hstore"
        for candidate in \
            ${HSTORE_BUILD_DIR}/libhstore.a \
            ${HSTORE_BUILD_DIR}/hstore.a \
            ${HSTORE_BUILD_DIR}/.libs/libhstore.a \
            ${HSTORE_BUILD_DIR}/*.a
        do
            if [ -f "$candidate" ]
            then
                HSTORE_LIB="$candidate"
                break
            fi
        done

        if [ -z "${HSTORE_LIB}" ]
        then
            HSTORE_OBJS=$(ls -1 ${HSTORE_BUILD_DIR}/*.o 2>/dev/null | tr '\n' ' ')
        fi

        if [ -z "${HSTORE_LIB}" ] && [ -z "${HSTORE_OBJS}" ]
        then
            echo "hstore library/objects not found in ${HSTORE_BUILD_DIR} (set WASI_HSTORE=false to skip)"
            exit 172
        fi
    fi

    WASI_LDFLAGS=""
    WASI_SYSROOT_LIB="${WASISDK}/upstream/share/wasi-sysroot/lib/wasm32-wasip1"
    if [ -d "$WASI_SYSROOT_LIB" ]
    then
        WASI_LDFLAGS="${WASI_LDFLAGS} -L${WASI_SYSROOT_LIB} -lsetjmp"
    fi
    CLANG_RT_DIR="$(ls -d ${WASISDK}/upstream/lib/clang/*/lib/wasm32-unknown-wasip1 2>/dev/null | sort -V | tail -n1)"
    if [ -n "$CLANG_RT_DIR" ] && [ -d "$CLANG_RT_DIR" ]
    then
        for rtlib in libclang_rt.builtins.a libclang_rt.builtins-wasm32.a libclang_rt.builtins-wasm32-wasi.a
        do
            if [ -f "${CLANG_RT_DIR}/${rtlib}" ]
            then
                rtname="${rtlib#lib}"
                rtname="${rtname%.a}"
                WASI_LDFLAGS="${WASI_LDFLAGS} -L${CLANG_RT_DIR} -l${rtname}"
                break
            fi
        done
    fi


    echo "
_______________________ PG_BRANCH=${PG_BRANCH} _____________________

wasi : $(which wasi-c) $(wasi-c -v)
python : $(which python3) $(python3 -V)
wasmtime : $(which wasmtime)

CC=${CC:-undefined}

Linking to libpgcore static from $LIBPGCORE

Folders :
    source : $PGSRC
     build : $BUILD_PATH
    target : $PGROOT
  retarget : ${PGL_DIST_C}
    native : ${PGL_DIST_NATIVE} build $(arch) : ${NATIVE}

    CPOPTS : $COPTS
    DEBUG  : $DEBUG
        LOPTS  : $LOPTS

     CMA_MB : $CMA_MB
GLOBAL_BASE : $GLOBAL_BASE_B

  CC_PGLITE : $CC_PGLITE

   PGCRYPTO : ${LINK_CRYPTO}

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
        if ${CC} -fpic -ferror-limit=1 ${CC_PGLITE} ${PGINC} \
         -o ${BUILD_PATH}/sdk_port-wasi.o \
         -c wasm-build/sdk_port-wasi/sdk_port-wasi-dlfcn.c \
         -Wno-incompatible-pointer-types
        then
            COPTS="$LOPTS" ${CC} ${CC_PGLITE} -ferror-limit=1 -Wl,--global-base=${GLOBAL_BASE_B} -o ${PG_DIST}/pglite.wasi \
             -nostartfiles ${PGINC} ${BUILD_PATH}/pglite.o \
             ${BUILD_PATH}/sdk_port-wasi.o \
             $LINKER $LIBPGCORE \
             $LINK_ICU \
             ${PG_BUILD}/${BUILD}/src/backend/snowball/libdict_snowball.a \
             ${PG_BUILD}/${BUILD}/src/pl/plpgsql/src/libplpgsql.a \
             ${HSTORE_LIB} \
             ${HSTORE_OBJS} \
             ${WASI_LDFLAGS} \
             -lxml2 -lz
        else
            echo "compilation of libpglite ${BUILD} support failed"
        fi

        if [ -f ${PG_DIST}/pglite.wasi ]
        then
            echo "building minimal wasi FS"
            cp ${PG_DIST}/pglite.wasi ${PGROOT}/bin/
            touch ${PGROOT}/bin/initdb ${PGROOT}/bin/postgres
            WASMFS_LIST="${WORKSPACE}/wasmfs.txt"
            if [ ! -f "$WASMFS_LIST" ]
            then
                echo "missing wasmfs list: $WASMFS_LIST"
                exit 1
            fi
            WASMFS_TAR_LIST="$(mktemp)"
            while IFS= read -r path
            do
                if [ -z "$path" ]
                then
                    continue
                fi
                case "$path" in
                    *[\*\?\[]* )
                        for match in $path
                        do
                            if [ ! -e "$match" ]
                            then
                                echo "wasmfs: missing $match"
                                continue
                            fi
                            printf '%s\n' "${match#/}" >> "$WASMFS_TAR_LIST"
                        done
                        ;;
                    * )
                        if [ ! -e "$path" ]
                        then
                            echo "wasmfs: missing $path"
                            continue
                        fi
                        printf '%s\n' "${path#/}" >> "$WASMFS_TAR_LIST"
                        ;;
                esac
            done < "$WASMFS_LIST"
            tar -C / --use-compress-program="gzip -1" -cvf ${PG_DIST}/pglite-wasi.tar.gz --files-from="$WASMFS_TAR_LIST"
            rm -f "$WASMFS_TAR_LIST"
            mkdir -p ${PGL_BUILD_NATIVE}
            cat > ${PGL_BUILD_NATIVE}/pglite-native.sh <<END
mkdir -p ${PGL_BUILD_NATIVE} ${PGL_DIST_NATIVE}
pushd ${PGL_BUILD_NATIVE}
END
            if [ -f /tmp/portable.opts ]
            then
                cat /tmp/portable.opts >> ${PGL_BUILD_NATIVE}/pglite-native.sh
            fi
            cat >> ${PGL_BUILD_NATIVE}/pglite-native.sh <<END
    export WORKSPACE=${WORKSPACE}
    export WASM2C=pglite
    export PYBUILD=3.13
    export PGROOT=$PGROOT
    export PGL_DIST_C=${PGL_DIST_C}
    export PGL_BUILD_NATIVE=${PGL_BUILD_NATIVE}
    export PGL_DIST_NATIVE=${PGL_DIST_NATIVE}

    export PATH=\$PATH:$(dirname $HPY)
    export CC=gcc
    export PYTHON=$HPY
    export PYMAJOR=$PYMAJOR
    export PYMINOR=$PYMINOR

    time ${WORKSPACE}/pglite-${PG_BRANCH}/native.sh
    mv -v *.so ${PGL_DIST_NATIVE}/
popd
END
            chmod +x ${PGL_BUILD_NATIVE}/pglite-native.sh
            if $NATIVE
            then
                ${PGL_BUILD_NATIVE}/pglite-native.sh
            else
                    echo "

    * native build here : ${PGL_BUILD_NATIVE}/pglite-native.sh

"
            fi
        else
            echo "linking libpglite ${BUILD} failed in $(pwd)"
            exit 142
        fi
    else
        echo "${BUILD} compilation of libpglite ${PG_BRANCH} failed"
        exit 146
    fi

    touch ${WORKSPACE}/${BUILD}.done

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


    EXPORTED_FUNCTIONS="_main,_use_wire,_pgl_initdb,_pgl_backend,_pgl_shutdown,_interactive_write,_interactive_read,_interactive_one"
    EXPORTED_FUNCTIONS="$EXPORTED_FUNCTIONS,_get_channel,_get_buffer_size,_get_buffer_addr"

    EXPORTED_RUNTIME_METHODS="MEMFS,IDBFS,FS,setValue,getValue,UTF8ToString,stringToNewUTF8,stringToUTF8OnStack"


    if $DEBUG
    then
        # FULL
        LINKER="-sMAIN_MODULE=1 -sEXPORTED_FUNCTIONS=${EXPORTED_FUNCTIONS}"
        unset EMCC_FORCE_STDLIBS
    else
        # min
        # LINKER="-sMAIN_MODULE=2"


#        LINKER="-sMAIN_MODULE=1 -sEXPORTED_FUNCTIONS=${EXPORTED_FUNCTIONS}"
#        LINKER="-sMAIN_MODULE=1 -sEXPORTED_FUNCTIONS=@${PGL_DIST_LINK}/exports/pglite"

        # tailored
        LINKER="-sMAIN_MODULE=2 -sEXPORTED_FUNCTIONS=@${PGL_DIST_LINK}/exports/pglite"
        export EMCC_FORCE_STDLIBS=1

    fi

    echo "

_______________________ PG_BRANCH=${PG_BRANCH} _____________________

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
GLOBAL_BASE : $GLOBAL_BASE_B

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


    if ${CC} ${CC_PGLITE} ${PGINC} -o ${BUILD_PATH}/pglite.o -c ${WORKSPACE}/pglite-${PG_BRANCH}/pg_main.c \
     -Wno-incompatible-pointer-types-discards-qualifiers
    then
        echo "

          * linking node raw version of pglite ${PG_BRANCH} (with all symbols)
               PGCRYPTO : ${LINK_CRYPTO}

"

        # wgpu ???
        export EMCC_FORCE_STDLIBS=1

        if COPTS="-O2 -g3 --no-wasm-opt" ${CC} ${CC_PGLITE} ${PGINC} -o ${PGL_DIST_JS}/pglite-js.js \
         -sGLOBAL_BASE=${CMA_MB}MB -ferror-limit=1  \
         -sFORCE_FILESYSTEM=1 $EMCC_NODE -sMAIN_MODULE=1 -sEXPORT_ALL -sASSERTIONS=0 \
             -sALLOW_TABLE_GROWTH -sALLOW_MEMORY_GROWTH -sERROR_ON_UNDEFINED_SYMBOLS=0 \
             -sEXPORTED_RUNTIME_METHODS=${EXPORTED_RUNTIME_METHODS} \
         ${BUILD_PATH}/pglite.o \
         $LIBPGCORE \
         $LINK_ICU \
         -lnodefs.js -lidbfs.js ${LINK_CRYPTO} -lxml2 -lz
        then
            ./wasm-build/linkexport.sh
            ./wasm-build/linkimports.sh
        else
            echo "
    *   linking node raw version of pglite failed"; exit 261

        fi

        if $DEBUG
        then
            unset EMCC_FORCE_STDLIBS
        fi

        echo "

    * linking  version of pglite ( with .data initial filesystem, and html repl) (required symbols)

        BUILD_PATH=${BUILD_PATH}
        LINKER=$LINKER
        LIBPGCORE=$LIBPGCORE

       PGCRYPTO : ${LINK_CRYPTO}


"

#   function from :
#        ${BUILD_PATH}/src/interfaces/libpq/libpq.a
#   required are to be found in  :
#       pglite.o
#

# LOPTS="-Os -g0"
#
        if COPTS="$LOPTS" ${CC} ${CC_PGLITE} -o ${PGL_DIST_WEB}/pglite.html --shell-file ${WORKSPACE}/pglite-${PG_BRANCH}/repl.html \
         $PGPRELOAD \
         -sGLOBAL_BASE=${CMA_MB}MB -ferror-limit=1 \
         -sFORCE_FILESYSTEM=1 -sNO_EXIT_RUNTIME=1 -sENVIRONMENT=node,web \
         $LINKER \
         -sMODULARIZE=1 -sEXPORT_ES6=1 -sEXPORT_NAME=Module \
             -sALLOW_TABLE_GROWTH -sALLOW_MEMORY_GROWTH -sERROR_ON_UNDEFINED_SYMBOLS=1 \
             -sEXPORTED_RUNTIME_METHODS=${EXPORTED_RUNTIME_METHODS} \
         ${PGINC} ${BUILD_PATH}/pglite.o \
         $LIBPGCORE \
         $LINK_ICU \
         -lnodefs.js -lidbfs.js ${LINK_CRYPTO} -lxml2 -lz
        then
            du -hs du -hs ${PG_DIST}/*
            touch ${WORKSPACE}/${BUILD}.done
        else
            echo "
    * linking web version of pglite failed"; exit 302
        fi
    else
        echo "compilation of libpglite ${PG_BRANCH} failed"; exit 305
    fi
fi




echo "pglite/build($BUILD): end"
