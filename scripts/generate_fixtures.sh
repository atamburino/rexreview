#!/bin/sh
# Rebuild tests/fixtures from real git diffs. Run from anywhere.
set -eu

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_CONFIG_COUNT
i=0
while [ "$i" -lt 32 ]; do
  unset "GIT_CONFIG_KEY_$i" "GIT_CONFIG_VALUE_$i" || true
  i=$((i + 1))
done

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
OUT="$ROOT/tests/fixtures"
mkdir -p "$OUT"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cd "$TMP"
git init -q -b main
git config user.email "rexreview@example.com"
git config user.name "Rex Review"
git config commit.gpgsign false
git config core.autocrlf false
git config core.safecrlf false
git config core.quotePath true

git_diff() {
  git -c core.quotePath=true diff --cached \
    --no-color \
    --no-ext-diff \
    --find-renames \
    --src-prefix=a/ \
    --dst-prefix=b/
}

reset_tree() {
  git reset -q --hard
  git clean -q -fd
}

mkdir -p src assets
printf '1 alpha\n2 beta\n3 gamma\n4 delta\n5 epsilon\n6 zeta\n7 eta\n8 theta\n9 iota\n10 kappa\n' > src/app.txt
printf 'keep\n' > src/gone.txt
printf 'same\nstay\n' > src/move.txt
printf 'one\ntwo\nthree\nfour\nfive\n' > src/edit_move.txt
printf 'plain\n' > src/nonew.txt
printf 'hello\n' > "src/my file.txt"
mkdir -p "foo b"
printf 'a\n' > "foo b/bar.txt"
printf 'same\n' > "old name.txt"
printf 'function hello()\n\ta\n\tb\n\tc\n\td\n\treturn 1\nend\n' > src/widget.lua
cafe=$(printf 'src/caf\303\251.txt')
printf 'alpha\n' > "$cafe"
printf 'bin\0data' > assets/pic.bin
git add -A
git commit -q -m base
BASE=$(git rev-parse HEAD)

printf '1 ALPHA\n2 beta\n3 gamma\n4 delta\n5 epsilon\n6 zeta\n7 eta\n8 theta\n9 iota\n10 kappa\n11 extra\n' > src/app.txt
git add -A
git_diff > "$OUT/modified.diff"
reset_tree

printf 'fresh\nline\n' > src/fresh.txt
git add -A
git_diff > "$OUT/added.diff"
reset_tree

rm src/gone.txt
git add -A
git_diff > "$OUT/deleted.diff"
reset_tree

git mv src/move.txt src/moved.txt
git_diff > "$OUT/rename.diff"
reset_tree

git mv src/edit_move.txt src/relocated.txt
printf 'one\ntwo\nTHREE\nfour\nfive\n' > src/relocated.txt
git add -A
git_diff > "$OUT/rename_edit.diff"
reset_tree

printf 'bin\0changed' > assets/pic.bin
git add -A
git_diff > "$OUT/binary.diff"
reset_tree

printf 'x\0y' > assets/new.bin
git add -A
git_diff > "$OUT/binary_new.diff"
reset_tree

rm assets/pic.bin
git add -A
git_diff > "$OUT/binary_deleted.diff"
reset_tree

printf 'plain' > src/nonew.txt
git add -A
git_diff > "$OUT/no_newline.diff"
reset_tree

printf 'plain' > src/nonew.txt
git add -A
git commit -q -m "drop newline"
printf 'plain!' > src/nonew.txt
git add -A
git_diff > "$OUT/no_newline_both.diff"
git reset -q --hard "$BASE"
git clean -q -fd

printf 'hello\nworld\n' > "src/my file.txt"
git add -A
git_diff > "$OUT/space_path.diff"
reset_tree

printf 'b\n' > "foo b/bar.txt"
git add -A
git_diff > "$OUT/space_ambiguous.diff"
reset_tree

git mv "old name.txt" "new name.txt"
git_diff > "$OUT/rename_space.diff"
reset_tree

printf 'beta\n' > "$cafe"
git add -A
git_diff > "$OUT/escaped_path.diff"
reset_tree

printf 'function hello()\n\ta\n\tb\n\tc\n\td\n\treturn 2\nend\n' > src/widget.lua
git add -A
git_diff > "$OUT/function.diff"
reset_tree

git_diff > "$OUT/empty.diff"
