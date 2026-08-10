## DM200 tools

### initramfs
initramfs作成用スクリプト

### installer
インストーラに使っているスクリプトと画像リソース

### rootfs_script
rootfs作成用スクリプトと起動後のLinux用スクリプトいくつか

Debian 13 (trixie) のrootfs作成手順は
rootfs_script/README.mdを参照してください。

### docker/kernel-build
Linux 6.18のクロスビルドとDTB連結済みDM200用`kernel.img`の作成環境

通常は`multi_v7_defconfig`を使用します。

```sh
docker/kernel-build/build-kernel.sh
```

`--defconfig`でmakeのdefconfigターゲット名、またはDM200プロジェクトルートからの
設定ファイルの相対パスを指定できます。試験用の設定を使用する場合は次のようにします。

```sh
docker/kernel-build/build-kernel.sh --defconfig patch/dm200_defconfig
```

環境変数`DM200_KERNEL_DEFCONFIG`でも同じ指定ができます。コマンドラインの
`--defconfig`が指定された場合は、そちらが優先されます。
