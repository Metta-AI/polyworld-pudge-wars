#!/usr/bin/env bash
# Stand-in for `docker pull python:3.12-slim` when Docker Hub's blob CDN is
# unreachable (automation network policy). Builds a minimal linux/amd64 rootfs
# from the host's pyenv CPython 3.12 (interpreter, stdlib, pip, CA certs and the
# shared libraries they link against), `docker import`s it and tags it
# python:3.12-slim so coworld/player/Dockerfile builds unchanged. Record the
# substitution (tag base_image=local-pyenv-<ver>-rootfs) on every upload built
# this way.
#
#     tools/offline_base_image.sh            # -> local image python:3.12-slim
#     docker build --platform linux/amd64 -f coworld/player/Dockerfile -t <image:tag> coworld
set -euo pipefail
PY_PREFIX="${PY_PREFIX:-$(python3 -c 'import sys; print(sys.prefix)')}"
OUT="${OUT:-${HOME}/pybase/rootfs}"
TAG="${TAG:-python:3.12-slim}"
rm -rf "$OUT"; mkdir -p "$OUT"/{usr/local/bin,usr/local/lib,lib/x86_64-linux-gnu,lib64,etc/ssl/certs,usr/lib/ssl,tmp,root,proc,sys,dev,bin,usr/bin}
chmod 1777 "$OUT/tmp"

cp -a "$PY_PREFIX/bin/python3.12" "$OUT/usr/local/bin/python3.12"
ln -s python3.12 "$OUT/usr/local/bin/python3"
ln -s python3.12 "$OUT/usr/local/bin/python"
cp -a "$PY_PREFIX"/lib/libpython3.12.so* "$OUT/usr/local/lib/"; cp -L "$PY_PREFIX"/lib/libpython3.12.so.1.0 "$OUT/lib/x86_64-linux-gnu/"
mkdir -p "$OUT/usr/local/lib/python3.12"
rsync -a --exclude='__pycache__' --exclude='test' --exclude='tests' --exclude='idlelib' --exclude='tkinter' --exclude='turtledemo' \
  --exclude='site-packages' "$PY_PREFIX/lib/python3.12/" "$OUT/usr/local/lib/python3.12/"
mkdir -p "$OUT/usr/local/lib/python3.12/site-packages"
for pkg in pip; do
  rsync -a --exclude='__pycache__' "$PY_PREFIX"/lib/python3.12/site-packages/${pkg} "$PY_PREFIX"/lib/python3.12/site-packages/${pkg}-*.dist-info "$OUT/usr/local/lib/python3.12/site-packages/"
done
# pip console script
cat > "$OUT/usr/local/bin/pip" <<'EOF'
#!/usr/local/bin/python3.12
import re, sys
from pip._internal.cli.main import main
if __name__ == "__main__":
    sys.argv[0] = re.sub(r"(-script\.pyw|\.exe)?$", "", sys.argv[0])
    sys.exit(main())
EOF
chmod +x "$OUT/usr/local/bin/pip"; ln -s pip "$OUT/usr/local/bin/pip3"

# shared libraries: everything the interpreter and the extension modules link against
libs=$( { ldd "$PY_PREFIX/bin/python3.12" "$PY_PREFIX"/lib/libpython3.12.so.1.0 "$PY_PREFIX"/lib/python3.12/lib-dynload/*.so 2>/dev/null || true; } \
  | awk '/=> \//{print $3} /^\s*\/.*ld-linux/{print $1}' | sort -u)
for l in $libs /lib/x86_64-linux-gnu/libnss_dns.so.2 /lib/x86_64-linux-gnu/libnss_files.so.2 /lib/x86_64-linux-gnu/libresolv.so.2 /lib64/ld-linux-x86-64.so.2; do
  real=$(readlink -f "$l")
  case "$real" in
    "$PY_PREFIX"/*) continue;;  # libpython already copied
  esac
  dest="$OUT$l"; mkdir -p "$(dirname "$dest")"
  cp -L "$real" "$dest"
done
# busybox-free minimal shell so `RUN` steps work: copy bash + coreutils it needs
for b in /bin/sh /bin/bash /bin/dash /usr/bin/env; do
  [ -e "$b" ] || continue
  real=$(readlink -f "$b"); mkdir -p "$OUT$(dirname "$b")"; cp -L "$real" "$OUT$b"
  for l in $(ldd "$real" | awk '/=> \//{print $3}'); do dest="$OUT$l"; [ -e "$dest" ] || { mkdir -p "$(dirname "$dest")"; cp -L "$(readlink -f "$l")" "$dest"; }; done
done
cp /etc/ssl/certs/ca-certificates.crt "$OUT/etc/ssl/certs/ca-certificates.crt"
ln -s /etc/ssl/certs "$OUT/usr/lib/ssl/certs"
ln -s /etc/ssl/certs/ca-certificates.crt "$OUT/usr/lib/ssl/cert.pem"
printf 'root:x:0:0:root:/root:/bin/sh\nnobody:x:65534:65534:nobody:/nonexistent:/usr/sbin/nologin\n' > "$OUT/etc/passwd"
printf 'root:x:0:\nnogroup:x:65534:\n' > "$OUT/etc/group"
printf 'passwd: files\ngroup: files\nhosts: files dns\n' > "$OUT/etc/nsswitch.conf"
echo "/usr/local/lib" > "$OUT/etc/ld.so.conf"
du -sh "$OUT"
tar -C "$OUT" -c . | docker import --platform linux/amd64 -c 'ENV PATH=/usr/local/bin:/usr/bin:/bin' -c 'ENV LANG=C.UTF-8' -c 'CMD ["python3"]' - "$TAG"
docker run --rm --platform linux/amd64 "$TAG" python -c 'import ssl, sqlite3, asyncio, ctypes, pip, sys; print(sys.version.split()[0], ssl.OPENSSL_VERSION, "pip", pip.__version__)'
