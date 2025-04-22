
i make a pglite


git clone --recursive --no-tags --depth 1 --single-branch --branch



cd  postgres-pglite
git checkout REL_17_4_WASM-pglite
git checkout -b REL_17_4_WASM-pglite-experiment

..... add some files

make changes


git push --set-upstream origin REL_17_4_WASM-pglite-mypexperiment (you can rename)


[ click on create pull request button ]

select the patch -pglite which match your current major/minor postgres


[ NOTES: what about C code style ]


[ NOTES: have a branch that trigger static build + 1 extension ]


CI SUCCESS !


going into parent


git checkout -b mypglite-test-with-updated-submodule


git add postgres-pglite

git commit -m "updated submodule"
push --set-upstream origin mypglite-test-with-updated-submodule (you can rename)

select main


create pull request as a draft with the arrow drop donw menu
