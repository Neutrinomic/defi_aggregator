#!/bin/sh
`mocv bin 0.12.1`/moc `mops sources` src/main.mo --idl --public-metadata candid:service --public-metadata candid:args -o build/main.wasm
