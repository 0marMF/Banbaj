#!/usr/bin/env bash
# Solo para desarrollo: convierte los diagramas Mermaid de docs/flujo/mmd/*.mmd en imágenes
# (docs/flujo/img/*.png para Word y GitHub, *.svg para verlos con zoom). Requiere mmdc (Mermaid CLI):
#   npm install -g @mermaid-js/mermaid-cli
# Después de cambiar un .mmd, corre este script y luego tools/generar_docs_word.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p docs/flujo/img
for f in docs/flujo/mmd/*.mmd; do
  n=$(basename "$f" .mmd)
  mmdc -q -i "$f" -o "docs/flujo/img/$n.png" -b white -s 2 -w 1400
  mmdc -q -i "$f" -o "docs/flujo/img/$n.svg" -b white
  echo "ok: $n"
done
