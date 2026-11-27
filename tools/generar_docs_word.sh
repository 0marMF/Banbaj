#!/usr/bin/env bash
# Solo para desarrollo: regenera los documentos de Word de docs/ a partir de los .md
# (el equipo no tiene visor de Markdown). Requiere pandoc.
set -euo pipefail
cd "$(dirname "$0")/.."
pandoc docs/MANUAL_INSTALACION_486.md -f gfm --reference-doc=tools/plantilla_word.docx \
  --shift-heading-level-by=-1 --toc --toc-depth=2 -M toc-title=Contenido -M lang=es-MX -s \
  -o "docs/Manual de migracion, instalacion y operacion Banbaj 486.docx"
pandoc docs/FUNCIONAMIENTO_486.md -f markdown --resource-path=docs --lua-filter=tools/ajustar_imagenes.lua --reference-doc=tools/plantilla_word.docx \
  --toc --toc-depth=1 -M toc-title=Contenido -M lang=es-MX -s \
  -o "docs/Como funciona Banbaj 486.docx"
pandoc docs/MIGRACION_PASO_A_PASO_486.md -f markdown --reference-doc=tools/plantilla_word.docx \
  --toc --toc-depth=1 -M toc-title=Contenido -M lang=es-MX -s \
  -o "docs/Migracion paso a paso Banbaj 486.docx"
# Manual técnico para el equipo de asignaciones (usa imágenes de docs/flujo/img)
pandoc docs/MANUAL_TECNICO_ASIGNACIONES_486.md -f markdown --resource-path=docs --lua-filter=tools/ajustar_imagenes.lua --reference-doc=tools/plantilla_word.docx \
  --toc --toc-depth=2 -M toc-title=Contenido -M lang=es-MX -s \
  -o "docs/Manual tecnico para asignaciones Banbaj 486.docx"
# Flujo y diagramas: índice + un capítulo por diagrama (las imágenes salen de docs/flujo/img, ver tools/generar_diagramas.sh)
pandoc docs/flujo/README.md docs/flujo/[0-9]*.md -f markdown --resource-path=docs/flujo --lua-filter=tools/ajustar_imagenes.lua --reference-doc=tools/plantilla_word.docx \
  --toc --toc-depth=1 -M toc-title=Contenido -M lang=es-MX -s \
  -o "docs/Flujo y diagramas Banbaj 486.docx"
# Guía de pruebas de entorno (ruta de los archivos del banco y los 8 scripts)
pandoc pruebas_entorno/GUIA_PRUEBAS_ENTORNO.md -f markdown --reference-doc=tools/plantilla_word.docx \
  --toc --toc-depth=2 -M toc-title=Contenido -M lang=es-MX -s \
  -o "pruebas_entorno/Guia de pruebas de entorno Banbaj 486.docx"
# Qué correr en el servidor (ACTUALIZAR_SERVIDOR.md), con las rutas de entrada y salida
pandoc ACTUALIZAR_SERVIDOR.md -f gfm --reference-doc=tools/plantilla_word.docx \
  --shift-heading-level-by=-1 --toc --toc-depth=2 -M toc-title=Contenido -M lang=es-MX -s \
  -o "docs/Actualizar servidor Banbaj 486.docx"
echo "Listo: docs/*.docx"
