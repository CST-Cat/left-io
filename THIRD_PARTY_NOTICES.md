# Third-Party Notices

LeftIO contains original application code and also uses Rime ecosystem
components and data.

## Project License

Unless otherwise noted, the original LeftIO source code and documentation are
licensed under the BSD 3-Clause License. See [LICENSE](LICENSE).

SPDX summary for the repository:

```text
BSD-3-Clause AND LGPL-3.0-only
```

## Rime Dictionary Data

`data/onehand_t9.dict.yaml` is generated from Rime dictionary data:

- `rime-luna-pinyin` / Luna Pinyin dictionary
- `rime-essay` / preset vocabulary and frequency data

These upstream Rime data projects are licensed under the GNU Lesser General
Public License version 3. See [LICENSES/LGPL-3.0-only.txt](LICENSES/LGPL-3.0-only.txt)
and [LICENSES/GPL-3.0-only.txt](LICENSES/GPL-3.0-only.txt).

The generated table keeps the upstream lexical data and transforms pinyin
readings into LeftIO T9 codes. Regenerate it with:

```sh
python3 scripts/generate_onehand_t9_dict.py \
  vendor/librime/data/minimal/luna_pinyin.dict.yaml \
  --supplement data/onehand_t9_phrases.tsv \
  > data/onehand_t9.dict.yaml
```

## Rime Engine

LeftIO dynamically loads or bundles `librime`, the Rime Input Method Engine.
`librime` is licensed under the BSD 3-Clause License. See
[LICENSES/librime-BSD-3-Clause.txt](LICENSES/librime-BSD-3-Clause.txt).

When distributing a binary build that includes `librime`, include the
corresponding license notices for `librime` and its dependencies.

## Bundled librime Dependencies

The local `vendor/librime` build may include or link the following components:

| Component | License text |
| --- | --- |
| Boost C++ Libraries | [LICENSES/boost-BSL-1.0.txt](LICENSES/boost-BSL-1.0.txt) |
| google-glog | [LICENSES/glog-BSD-3-Clause.txt](LICENSES/glog-BSD-3-Clause.txt) |
| GoogleTest | [LICENSES/googletest-BSD-3-Clause.txt](LICENSES/googletest-BSD-3-Clause.txt) |
| LevelDB | [LICENSES/leveldb-BSD-3-Clause.txt](LICENSES/leveldb-BSD-3-Clause.txt) |
| marisa-trie | [LICENSES/marisa-trie-COPYING.md](LICENSES/marisa-trie-COPYING.md) |
| OpenCC | [LICENSES/opencc-Apache-2.0.txt](LICENSES/opencc-Apache-2.0.txt) |
| yaml-cpp | [LICENSES/yaml-cpp-MIT.txt](LICENSES/yaml-cpp-MIT.txt) |

The ignored `vendor/` checkout is not part of the source distribution, but the
binary build scripts may fetch and package these components.
