#!/bin/sh

echo "Baseline:"
bin/crystal run --release samples/simd/utf8_valid_encoding.cr

echo "x86-64-v2:"
bin/crystal run --release samples/simd/utf8_valid_encoding.cr --mcpu=x86-64-v2 -Dx86_has_sse41

echo "x86-64-v3:"
bin/crystal run --release samples/simd/utf8_valid_encoding.cr --mcpu=x86-64-v3 -Dx86_has_sse41 -Dx86_has_avx2
