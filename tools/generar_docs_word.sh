#!/usr/bin/env bash
# Solo para desarrollo: regenera los documentos de Word de docs/ a partir de los .md
# (el equipo no tiene visor de Markdown). Requiere pandoc.
set -euo pipefail
cd "$(dirname "$0")/.."
pandoc docs/MANUAL_INSTALACION_486.md -f gfm --reference-doc=tools/plantilla_word.docx \
  --shift-heading-level-by=-1 --toc --toc-depth=2 -M toc-title=Contenido -M lang=es-MX -s \
  -o "docs/Manual de migracion, instalacion y operacion Banbaj 486.docx"
pandoc docs/FUNCIONAMIENTO_486.md -f markdown --reference-doc=tools/plantilla_word.docx \
  --toc --toc-depth=1 -M toc-title=Contenido -M lang=es-MX -s \
  -o "docs/Como funciona Banbaj 486.docx"
echo "Listo: docs/*.docx"
