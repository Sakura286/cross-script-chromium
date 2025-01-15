#!/bin/bash
OUT=out/Release-riscv64

pkgdir=chromium-dist
rm -rf "$pkgdir"
mkdir -p "$pkgdir"

<<COMMENT
files=(
    chrome_100_percent.pak
    chrome_200_percent.pak
    chrome_crashpad_handler
    resources.pak
    content_shell.pak
    shell_resources.pak
    snapshot_blob.bin
    v8_context_snapshot.bin

    # ANGLE
    libEGL.so
    libGLESv2.so

    # SwiftShader ICD
    libvk_swiftshader.so
    libvulkan.so.1
    vk_swiftshader_icd.json

    # ICU
    icudtl.dat
)


cp "${files[@]/#/$OUT/}" "$pkgdir"

COMMENT

for i in $(find $OUT -maxdepth 1 -type f)
do
    cp $i $pkgdir
done

install -D "$OUT"/chrome "$pkgdir/chromium"
install -Dm4755 "$OUT"/chrome_sandbox "$pkgdir/chrome-sandbox"

install -Dm644 -t "$pkgdir/locales" "$OUT"/locales/*.pak

tar --zstd -cf chromium-dist.tar.zst --directory="$pkgdir" .