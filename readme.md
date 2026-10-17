# Pomera DM200 / DM250 / DM250US tools

PomeraでLinuxをSDから起動するためのビルド・イメージ作成ツールです。
Linux / U-Bootは別リポジトリから取得し、このリポジトリでrootfsとSDイメージを作成します。

対応する機種名は`dm200`、`dm250`、`dm250us`です。以下は`dm250`の例です。

## ディレクトリ

| 場所 | 用途 |
| --- | --- |
| [kernel/](kernel/) | Linux / U-Bootの取得・更新、共通Dockerビルド環境 |
| [rootfs_script/](rootfs_script/) | Debian / Ubuntuのarmhf rootfs、機種別ext4イメージ、実機用overlay |
| [idb/](idb/) | RK3128のSD起動用IDB生成 |
| [sd_image/](sd_image/) | 各成果物の収集、SDイメージ・配布ZIP・チェックサム生成 |
| [docs/THIRD_PARTY_NOTICES.md](docs/THIRD_PARTY_NOTICES.md) | ファームウェア等の第三者ライセンス |
| [initramfs/](initramfs/)、[installer/](installer/) | 旧インストール方式用。最新の手順では使用しない |

## ホスト環境

Linuxホスト、Git、利用可能なDocker Engine(または同等のビルド環境)、APT・Git・ファームウェア取得用のネットワークが必要です。
rootfs作成とext4イメージ作成はホスト上でroot権限を使います。

## 1. Linux / U-Bootのビルド

```sh
./kernel/docker_builder.sh
```

初回はLinuxとU-Bootをcloneし、既存のcloneは同じbranchのremoteへfast-forwardで更新します。
ローカル変更は保持されますが、競合・履歴の分岐・branchやoriginの不一致では停止します。
その後、共通ツールチェーンのDockerイメージを作り、対話シェルを開きます。

既定の取得先:

- Linux: `https://github.com/ichinomoto/linux`、branch `pomera/linux-6.18.y`
- U-Boot: `https://github.com/ichinomoto/u-boot`、branch `pomera/v2026.07`
- ホスト上の保存先: `kernel/linux`、`kernel/u-boot`

コンテナ内で実行:

```sh
cd /workspace/u-boot
./make_uboot_image.sh dm250

cd /workspace/linux
./make_kernel.sh dm250
```

`kernel_<機種>.img`はzImageのみを包んだRockchip KRNL形式、
`resource_<機種>.img`は別DTBを格納したRSCE形式です。

以下のファイルが生成されます:

- `u-boot/uboot_dm250.img`
- `linux/kernel_dm250.img`
- `linux/resource_dm250.img`
- `linux/modules_dm250.tar.gz`

## 2. rootfsの作成

指定しなければDebian 13 (trixie)、Xorg / Xfceを含む構成です。

```sh
cd rootfs_script
sudo ./make_rootfs.sh
```
出力ディレクトリは`rootfs`です。Xが不要な場合は`--no-x`

Ubuntu 26.04 を選ぶ場合

```sh
sudo ./make_rootfs.sh --distro ubuntu --suite 26.04
```

この場合は`rootfs-ubuntu-resolute`へ生成します。
共通設定は[rootfs_script/rootfs_config.sh](rootfs_script/rootfs_config.sh)、
実機に追加するファイルは[rootfs_script/files/](rootfs_script/files/)にあります。

## 3. 機種別rootfsイメージの作成

```sh
sudo ./make_rootfs_image.sh dm250
```

`rootfs`を元に、`kernel/linux/modules_dm250.tar.gz`のmodulesを組み込んだ
`rootfs_dm250.img`と`.sha256`を生成します。
元のrootfsディレクトリは共通のままで、機種別modulesは生成イメージへ反映されます。
対応するkernelのmodules archiveを先にビルドしておいてください。

Ubuntuを選んだ場合は、元ディレクトリを指定します。

```sh
sudo ./make_rootfs_image.sh dm250 --rootfs rootfs-ubuntu-resolute
```

サイズは既定で使用量から算出し、固定サイズが必要な場合は`--size 4G`等を指定できます。

## 4. IDBの作成

```sh
cd idb
sh ./make_idb.sh
```

必要な`dm200_uboot`と`rkbin`を未取得時だけcloneし、`idb.img`を生成します。
既存のcheckoutは自動更新しません。生成には旧U-Boot側のDDR/miniloaderバイナリと
`rkbin/tools/mkimage`を使用します。

## 5. SDイメージと配布ZIPの作成

```sh
cd sd_image
sh ./make_sd_boot_image.sh dm250
```

IDB、機種別U-Boot、kernel、resource、rootfsを上記で作成したところから取得し、
`sd_image/dm250/`へコピーしてから`sd_dm250.img`という名前でSDイメージに結合します。

各スクリプトのオプションは`--help`を参照してください。
