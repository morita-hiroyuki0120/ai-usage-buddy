# 固定 helper の依存ライセンス監査

監査日: 2026-10-23

## 判定

**NOT READY。** 固定commitのsourceとlockfileから、normalizedコピーの`aarch64-apple-darwin`依存候補とライセンス資料を対応づけたが、必要なライセンス本文、著作権表示、NOTICEの充足確認は未完了である。
対象別graphはsource由来の候補であり、配布済みhelperへの含有を確定するものではない。

この文書は依存ライセンス監査の完了や配布許可を意味しない。

## 確認できた資料

- 公式GitHubの固定commit `83086188ae0614bd882818ff1aa23f3194962012`のtree SHAは`e91f335e7a03e1d14fa1e5fc7fc7620cdfc60842`である。
  [commit](https://github.com/openai/codex/commit/83086188ae0614bd882818ff1aa23f3194962012)に固定したsource archiveを取得し、SHA-256 `e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`、圧縮後17,520,744 bytesを記録した。
  このSHA-256は取得したarchiveのローカル計算値であり、GitHubが公表するartifact checksumではない。
- archiveと展開sourceは`build/dependency-audit/codex-0.163.0/source-audit-83086188/`に保存した。
  事前検査では10,158 member（通常file 9,175、directory 982、symlink 1）を確認し、絶対path、`..` component、hardlink、特殊fileはなかった。
  唯一のsymlinkは`codex-rs/vendor/bubblewrap/LICENSE -> COPYING`で、同じvendor directory内の通常fileを指す。
  その確認後に新規checkout directoryへ展開し、source内のscriptやbinaryは実行していない。
- 固定sourceの`codex-rs/Cargo.toml`はworkspace memberを155個列挙し、resolver `2`、edition `2024`、version `0.163.0`、workspace license `Apache-2.0`を指定する。
  `codex-rs/Cargo.lock`は408,369 bytes、1,474個の`[[package]]` entryを含む。
  lockfileのGit blob SHAは`72658b908782ad8f90ba70260fba20a395999f0b`で、公式GitHub APIの値と保存copyから計算した値が一致する。
  保存copyのSHA-256は`17cdd862471774ba7aef836aaf0a0a3ed76bd23e503b1fc7278c89d1f2719d03`である。
- 固定sourceのRust 1.95.0 toolchainを、専用audit directoryだけに導入した。
  公式channel manifestのSHA-256 `821ff14e4c4a1cbe1e8915f35aff0a3fbbdf8d293ad48ab8f31e3b0440c581f9`は公開checksumと一致し、cargo、rustc、rust-std archiveの各checksumも公式manifestと一致した。
  systemのRust/Cargo 1.80.1、global PATH、rustup default、Homebrewは変更していない。
- 固定sourceの[公開release workflow](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/.github/workflows/rust-release.yml)は87,300 bytesで、Git blob SHA `42011c6867a49c481ad20fab086044dda1c5ebc8`が保存copyのGit object IDと一致する。
  保存copyのSHA-256は`536d07d677b2fa2b44a11eb1e853b001217e39c6fd3bae6845f57f90e9eea6da`である。
- workflowのapp-server matrixはrunner `macos-15-xlarge`、target `aarch64-apple-darwin`、bundle `app-server`、artifact名`aarch64-apple-darwin-app-server`を指定し、binary `codex-app-server`と`codex-code-mode-host`を選ぶ。
  workflow commentはCargoをrelease path、Bazelをadvisoryとし、Cargo commandは`cargo build --target "$target" --release --timings "${build_args[@]}"`である。
  `build_args`には上記2 binaryの`--bin`指定が入り、commandには`--features`も`--locked`もない。
  そのため、このworkflow定義はtargetとbuild commandの根拠になるが、既知のrelease binary digestが特定の成功runで生成されたことや、lockfileからの再解決が一切ないことまでは証明しない。
- `codex-rs/app-server/Cargo.toml`はpackage feature tableを持たない。
  production dependencyで明示するfeatureは、axumの`http1`、`json`、`tokio`、`ws`（`default-features=false`）、clapの`derive`、serdeの`derive`、tokioの`io-std`、`macros`、`process`、`rt-multi-thread`、`signal`、tracingの`log`、tracing-subscriberの`env-filter`、`fmt`、`json`、uuidの`serde`、`v7`である。
  これはmanifest上の直接指定であり、release commandが選択する2 binaryの解決済みfeature unionやtarget依存closureの一覧ではない。
- 固定sourceの`codex-rs/rust-toolchain.toml`とrelease workflowはRust `1.95.0`を指定する。
  同じcommitの[cargo-deny workflow](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/.github/workflows/cargo-deny.yml)はRust `1.95.0`とcargo-deny v2 actionを使い、policyは`codex-rs/deny.toml`にある。
  systemのRust/Cargoは引き続き`1.80.1`で、`rustup`と`cargo-deny`は見つからなかった。
- isolated `CARGO_HOME`を使ったmetadata-only試行は、`--no-deps --locked --offline`を付けてもexit code 101で失敗した。
  Cargo `1.80.1`がworkspace memberのedition `2024`を解析できず、registry accessやdependency resolutionより前に`feature edition2024 is required`を返した。
  依存crate、build script、helper binaryは実行しておらず、downloadもbuildもしていない。
- Rust/Cargo `1.95.0`による`cargo metadata --locked --filter-platform aarch64-apple-darwin`と対象binaryの`cargo tree --locked`はexit code 101で失敗した。
  stderrは`cannot update the lock file ... because --locked was passed to prevent this`である。
  固定lockfileの160個のlocal path packageは全てversion `0.0.0`だが、同じcommitの各manifestはworkspace version `0.163.0`を継承している。
  別のdiagnostic copyで行った一度のunlocked metadata試行では、lock差分はpath packageの160 versionだけで、registryのversion/source/checksumとGit revisionは変化しなかった。
  原sourceでは`--locked`が失敗する一方、このnormalizedコピーでは後続のoffline `--locked` metadata/treeが成功した。
  そのsource由来のtarget候補と配布binaryへの含有は区別する。
- lockfileの全package sourceとlicense欄を集めた機械生成inventoryは`build/dependency-audit/codex-0.163.0/rust-toolchain-audit-1.95.0/results/cargo-lock-license-inventory.json`に保存した。
  1,474 entryの内訳はregistry 1,296、local path 160、Git 18であり、binaryへの含有を断定する一覧ではなく保守的なsupersetである。
- registry 1,296件は、全件でlockfile checksumとcrate archive SHA-256が一致し、archive内のCargo manifest name/versionもlockfileと一致した。
  既存isolated cacheにあった1,097件に加え、未cacheの199件をlockfileのexact version/source/checksumに従って`static.crates.io`から取得し、全件のchecksum一致を確認した。
  archive member pathを検査した上で、通常ファイルのLICENSE、NOTICE、COPYING、COPYRIGHT等の候補2,082件を1,159 crateから`results/lockfile-license-texts/`へ保存した。
  137 crateはarchive内に候補文書がなかったため、manifestのrepository URLと`.cargo_vcs_info.json`のrevisionからGitHubの固定treeを調べた。
  113 packageに対応する48個のrepository/revision treeを取得し、55件のLICENSE、NOTICE等の候補本文を101 packageへ対応づけた。
  全treeはtruncatedではなく、55本文のSHA-256は保存manifestと一致した。
  後続確認では137件すべてのcrate archive SHA-256をlockfile checksumと再照合し、Cargo manifestのpackage name、version、license expression、repository URL、および`.cargo_vcs_info.json`のSHA-256、git SHA-1、`path_in_vcs`を記録した。
  URLに`/tree/...`を含むrepositoryの一部を前回解析が除外していたため、VCS SHAが明記された固定commitだけを使って追加の5 treeを照会し、9件のLICENSE候補本文を保存した。
  既存55件と合わせて64件の本文を114 packageへ対応づけ、候補ファイルのSHA-256とsource URLを再検証した。
  package別の監査結果は[missing-license-inventory.json](../build/dependency-audit/codex-0.163.0/rust-toolchain-audit-1.95.0/results/missing-license-followup-20261022/missing-license-inventory.json)に保存した。
  本文を取得できていない23 packageは次の通りである。
  - crateにVCS SHAがない10件: `allocative@0.3.6`、`allocative_derive@0.3.6`、`difflib@0.4.0`、`display_container@0.9.0`、`fxhash@0.2.1`、`lock_free_hashtable@0.1.4`、`rustls-platform-verifier-android@0.1.1`、`static_interner@0.1.2`、`strong_hash@0.1.0`、`strong_hash_derive@0.1.0`。
  - 固定revisionのrootまたはpackage祖先に候補本文がない12件: `cookie-factory@0.3.3`、`crc32c@0.6.8`、`debugserver-types@0.5.0`、`deno_core_icudata@0.77.0`、`eventsource-stream@0.2.3`、`fax@0.2.6`、`fax_derive@0.2.0`、`io_tee@0.1.1`、`linux-keyutils@0.2.4`、`r-efi@5.3.0`、`r-efi@6.0.0`、`winsplit@0.1.0`。
  - manifestからGitHub repositoryを特定できない1件: `pagable_derive@0.4.1`。
  これらは上流の候補資料であり、license適用範囲、copyright notice、NOTICE義務、対象binaryへの含有は未確認である。
- Git依存18件は8つのlockfile固定revisionに対応し、既存checkout全てのHEADがlockfile revisionと一致した。
  18 package全てでmanifest name/version/license expressionを対応させ、各repositoryからLICENSE等候補12件を`results/git-license-texts/`へ保存した。
- local path 160件は固定source内のmanifest directoryとpackage nameを照合し、全件でmanifest version `0.163.0`と`Apache-2.0` license expressionを確認した。
  元lockfile上のversionは全件`0.0.0`であり、不一致は残る。
- 固定source rootの`LICENSE`と`NOTICE`を`results/path-workspace-license-texts/`へ複製し、両方のSHA-256がsourceと一致することを確認した。
  `results/path-package-shared-license-evidence.json`は160件を共有候補へ対応づけるが、package別の適用範囲、対象binaryへの含有、NOTICE義務は確定しない。
- 既存の[app-server audit](codex-app-server-audit.md)は公式release binaryのSHA-256 `8165de84cc8e436d46d5e52fe6b68de053ba729c543e6310a1bd41e881cf4c37`とroot LICENSE・NOTICEを記録する。
  それらのroot資料は全推移依存のlicense textやNOTICEを網羅しない。
  [`config/EmbeddedAppServer.json`](../config/EmbeddedAppServer.json)の`noticeAudit`と`transitiveLicenseAudit`は`pending`、`distributionStatus`は`not-ready`のままである。

## normalizedコピーのtarget依存候補

保存済み[commands.json](../build/dependency-audit/codex-0.163.0/rust-toolchain-audit-1.95.0/results/target-closure-followup/commands.json)では、隔離Rust/Cargo 1.95.0によるoffline `--locked` metadataと通常/build依存、featuresのtree取得が成功している。
2026-10-23の再検証ではこれらの既存出力を読み、Cargoやhelperを再実行していない。
copy lockは原lockのpath package 160件のversionを`0.0.0`から`0.163.0`に置換した内容とbyte単位で一致し、registry 1,296件とGit 18件の外部pinに変更はなかった。

rootを含む通常/build候補のpackage数はapp-server単独907、code-mode-host単独543、公式releaseの同時2 binary buildに対応させた2 root候補union 936である。
metadataの1,270 packageはworkspace全体の件数であり、このclosureの総数として使用しない。
通常/build treeとfeatures treeのpackage集合はそれぞれ一致し、metadataの通常/build edgeを使ったrootからの経路も907件と936件すべてに到達した。
未知の`cfg(not(feature = "alloc"))`は保守的に保持している。

本文候補未対応の23 packageのうち、app-server単独の候補に13件、2 binary候補unionに14件を含み、差分は`deno_core_icudata@0.77.0`である。
今回の候補tree対象外は`crc32c@0.6.8`、`difflib@0.4.0`、`fax@0.2.6`、`fax_derive@0.2.0`、`linux-keyutils@0.2.4`、`r-efi@5.3.0`、`r-efi@6.0.0`、`rustls-platform-verifier-android@0.1.1`、`winsplit@0.1.0`の9件である。
この9件の分類は指定root、target、依存kind、feature解決に限定し、他platformや配布binary全体からの除外を断定しない。
[target-closure-inventory.json](../build/dependency-audit/codex-0.163.0/rust-toolchain-audit-1.95.0/results/target-closure-followup/target-closure-inventory.json)にpackage IDと到達経路を保存したが、同fileの`manifestIncomingEdges`はpackage名ベースの参考情報であり、version別の結合根拠には使用しない。

対象14件のREADME/header資料は30ファイルで、そのうち5件はcrate VCS commit固定の公開READMEである。
既存のlicense関連行検出規則に一致したpackageは10件だが、この検出件数はライセンス全文や義務充足の判定ではない。
保存資料の30件すべてについてSHA-256を再計算し、crate由来のREADMEとheaderはchecksum一致archiveの通常memberとも照合した。
これらのREADME/headerにはライセンス名や参照先の宣言があるものの、単独で必要な全文と帰属の充足を確定する資料としては扱わない。

[license-obligations-ledger-20261023.json](../build/dependency-audit/codex-0.163.0/rust-toolchain-audit-1.95.0/results/target-closure-followup/license-obligations-ledger-20261023.json)は14件ごとにmanifestのlicense expression、宣言と全文の区別、不足資料、次の取得方法を記録する。
2026-10-23の指定4件追補では、固定commitの完全treeと38資料を保存し、[license-text-inventory.json](../build/dependency-audit/codex-0.163.0/rust-toolchain-audit-1.95.0/results/license-text-followup-20261023/license-text-inventory.json)にURL、SHA-256、Git blob照合、本文と帰属の区別を記録した。
fxhashが参照するRust COPYRIGHTとdeno_core_icudataが参照するICUデータの出所と適用条件など、他10件の判定は変更していない。

| package | 資料収集status | 本文と帰属の確認結果 |
| --- | --- | --- |
| cookie-factory 0.3.3 | evidence-complete-for-review | README明示先のMIT全文と実帰属「Copyright (c) 2017-2023 Geoffroy Couprie」を取得した。`.reuse/dep5`の`Files: *`とMIT指定を保存し、重複するcrate資料11件はbyte一致した。 |
| debugserver-types 0.5.0 | explicit-missing | manifestのMIT宣言のみで、固定treeに本文や実著作権表示は見つからなかった。schemaの固定出所と適用帰属も不足する。crate対応5資料はCRLFをLFに正規化すると一致するが、元byte hashは別々に保持した。 |
| eventsource-stream 0.2.3 | explicit-missing | READMEとmanifestのMIT OR Apache-2.0宣言のみで、選択する本文と実帰属が不足する。固定treeのlicense下位directoryと保存source/headerにも本文は見つからず、crate対応11資料はbyte一致した。 |
| pagable_derive 0.4.1 | evidence-complete-for-review | packageのworkspace license継承、root manifestのApache-2.0、READMEのroot LICENSE参照、Apache-2.0全文、5 sourceの実Meta著作権表示を保存した。完全固定treeにNOTICE名のfileや当該package/ancestorの例外は見つからず、package資料6件はcrateとbyte一致した。headerが参照するLICENSE-MIT/LICENSE-APACHE名はrootに存在しないため、本文を確認したApache-2.0経路のみを採用し、MIT経路の充足は主張しない。 |

このstatusは資料がレビュー可能かを示し、配布物全体の本文、帰属、必要NOTICEの義務充足や法的適合を確定しない。
標準Apache付録の未記入欄は帰属として使用せず、配布用noticeへの組込みと全体判定は未完了で、NOT READYを維持する。
[verification-20261023.json](../build/dependency-audit/codex-0.163.0/rust-toolchain-audit-1.95.0/results/target-closure-followup/verification-20261023.json)に全文parse、package/version/source対応、保存資料hash、lock差分の検証結果を記録した。

## 完了に必要な証拠

1. source archive、workspace `Cargo.toml`、`Cargo.lock`、`app-server/Cargo.toml`、release workflow、および全lock entryのlicense候補supersetは保存した。
   local path 160件には共有root `LICENSE`と`NOTICE`の候補を対応づけたが、package別の適用範囲は未確認である。
   registry 137件のうち114 packageに上流sourceの候補本文を対応づけ、23 packageは本文未収集のままである。
   収集候補すべての著作権表示とNOTICE適用範囲も個別確認が必要である。
2. Rust/Cargo `1.95.0`で`cargo metadata --locked --filter-platform aarch64-apple-darwin`と対象binaryの`cargo tree --locked`を実行したが、固定sourceのpath package version不一致によりexit code 101となった。
   別copyで確認したlock差分はpath package 160件のversion同期のみで、registry packageのversion/source/checksumとGit revisionは不変だった。
   normalizedコピーでのoffline `--locked`成功とtarget候補は上記の通り確認したが、配布binaryとの対応は来歴根拠として引き続き評価する。
3. 収集済みlicense/NOTICE候補について具体的なlicense条件、著作権表示、NOTICEの同梱要否と、利用可能な`codex-rs/deny.toml`のpolicy結果を照合する。
   manifestとheaderの条件差など、根拠から確定できない具体事項はユーザー判断に残す。
   cargo-denyのworkspace全体checkだけでは、App Store向けbinaryの対象別closureや同梱すべき個別noticeを証明しない。
4. 固定release asset digest、tag、source commit、外部pin不変のlock差分、normalized target graph、収集noticeの対応を示し、artifactと依存資料を結び付ける来歴根拠として評価する。
   release workflowに`--locked`指定がない点を留保し、取得可能なActions provenance、SBOM、再現build/hashは追加の補強証拠とする。
   SBOMや再現hashを唯一の必須gateにはせず、来歴対応と必要なlicense本文、著作権表示、NOTICE確認を進める。

Cargo workspace全体のlockfile entry数は1,474だが、この総数をarm64 app-server binaryのdependency closureとして扱うことはできない。

## 安全性・配布状態

このsource/license auditでは認証情報を読み取らず、GitHub APIへ認証headerを送らず、helper binary、crate code、build scriptを実行せず、`cargo build`も行っていない。
公開registry crate archive 199件と、固定GitHub revisionにあるlicense候補本文64件を取得し、lockfile checksumと各本文hashを検証して専用audit directoryへ保存した。
source、workflow、lockfile、manifest、生成inventory以外のapp、Store project、正式release候補は変更していない。

当license job自身はauth操作を実施していない。
Store UIのログインと利用枠取得の確認状態はローカル作業記録（公開対象外）を参照する。

依存closure、全NOTICE、telemetry等の別監査が未完了であるため、配布状態は引き続き **NOT READY** とする。
